+++
title = "The problem of unpredictable interface order in multi-network Docker containers"
date = 2018-03-03T00:00:00Z
categories = ["automation"]
tags = ["network-ci", "devops"]
summary = "Exploring the problem of and solution to the random interface attachment order inside multi-network Docker containers"
+++

Whether we like it or not, the era of DevOps is upon us, fellow network engineers, and with it come opportunities to approach and solve common networking problems 
in new, innovative ways. One such problem is automated network change validation and testing in virtual environments, something I've already [written about][network-ci] a few years ago. The biggest problem with my original approach was that I had to create a custom [REST API SDK][unl-rest] to work with a network simulation environment (UnetLab) that was never designed to be interacted with in a programmatic way. On the other hand, technologies like Docker have been very interesting since they were built around the idea of non-interactive lifecycle management and came with all [API batteries][docker-py] already included. However, Docker was never intended to be used for network simulations and its support for multiple network interfaces is... somewhat problematic.

# Problem demonstration

The easiest way to understand the problem is to see it. Let's start with a blank Docker host and create a few networks:

```bash
docker network create net1
docker network create net2
docker network create net3
```
Now let's see what prefixes have been allocated to those networks:

```bash
docker network inspect -f "{{range .IPAM.Config }}{{.Subnet}}{{end}}" net1
172.17.0.0/16
docker network inspect -f "{{range .IPAM.Config }}{{.Subnet}}{{end}}" net2
172.18.0.0/16
docker network inspect -f "{{range .IPAM.Config }}{{.Subnet}}{{end}}" net3
172.19.0.0/16
```

Finally, let's create a container and attach it to these networks:

```bash
docker create --name test -it alpine sh
docker network connect net1 test
docker network connect net2 test
docker network connect net3 test
```

Now obviously you would expect for networks to appear in the same order as they were attached, right? Let's see if it's true:

```bash
docker start test
docker exec -it test sh -c "ip a | grep 'inet'"
inet 127.0.0.1/8 scope host lo
inet 172.26.0.2/16 brd 172.26.255.255 scope global eth0
inet 172.17.0.2/16 brd 172.17.255.255 scope global eth1
inet 172.18.0.2/16 brd 172.18.255.255 scope global eth2
inet 172.19.0.2/16 brd 172.19.255.255 scope global eth3
```

Looks good so far. The first interface (172.26.0.2/16) is the docker bridge that was attached by default in `docker create` command. Now let's add another network.

```bash
docker network create net4
docker stop test
docker network connect net4 test
docker start test
```

Let's examine our interfaces again:

```bash
docker exec -it test sh -c "ip a | egrep 'eth\d|inet'"
inet 127.0.0.1/8 scope host lo
inet 172.26.0.2/16 brd 172.26.255.255 scope global eth0
inet 172.20.0.2/16 brd 172.20.255.255 scope global eth3
inet 172.17.0.2/16 brd 172.17.255.255 scope global eth2
inet 172.18.0.2/16 brd 172.18.255.255 scope global eth1
inet 172.19.0.2/16 brd 172.19.255.255 scope global eth4
```

Now we're seeing that networks are in a completely different order. Looks like net1 is connected to eth2, net2 to eth1, net3 to eth4 and net4 to eth3. In fact, this issue should manifest itself even with 2 or 3 networks, however, I've found that it doesn't always reorder them in that case.

# CNM and libnetwork architecture

In order to better understand the issue, it help to know the CNM terminology and network lifecycle events which are explained in libnetwork's [design document][libnet-arch]. 

![](https://github.com/docker/libnetwork/raw/master/docs/cnm-model.jpg?raw=true)


Each time we run a `docker network create` command a new **CNM network** object is created. This object has a specific network type (`bridge` by default) which identifies the driver to be used for the actual network implementation.

```go
network, err := controller.NewNetwork("bridge", "net1", "")
```

When container gets attached to its networks, first time in `docker create` and subsequently in `docket network connect` commands, an **endpoint object** is created on each of the networks being connected. This endpoint object represents container's point of attachment (similar to a switch port) to docker networks and may allocate IP settings for a future network interface.

```go
ep, err := network.CreateEndpoint("ep1")
```

At the time when container gets attached to its first network, a **sandbox object** is created. This object represents a container inside CNM object model and stores pointers to all attached network endpoints.

```go
sbx, err := controller.NewSandbox("test")
```

Finally, when we start a container using `docker start` command, the corresponding **sandbox gets attached** to all associated network endpoints using the `ep.Join(sandbox)` call: 

```go
for _, ep := range epList {
	if err := ep.Join(sb); err != nil {
		logrus.Warnf("Failed attach sandbox %s to endpoint %s: %v\n", sb.ID(), ep.ID(), err)
	}
}
```

# Going down the rabbit hole

Looking at the above snippet from `sandbox.go`, we can assume that the order in which networks will be attached to a container will depend on the order of elements inside the `epList` array, which gets built earlier in the function:

```go
epList := sb.getConnectedEndpoints()
```

Now let's see what happens inside that method call:

```go
func (sb *sandbox) getConnectedEndpoints() []*endpoint {
	sb.Lock()
	defer sb.Unlock()

	eps := make([]*endpoint, len(sb.endpoints))
	for i, ep := range sb.endpoints {
		eps[i] = ep
	}

	return eps
}
```

So `epList` is just an array of endpoints that gets built by copying values from `sb.endoints`, which itself is an attribute (or field) inside the `sb` struct. 

```go
type epHeap []*endpoint

type sandbox struct {
  id                 string
  containerID        string
...
  endpoints          epHeap
...
}
```

At this point it looks like `endpoints` is just an array of pointers to endpoint objects, which still doesn't explain the issue we're investigating. Perhaps it would make more sense if we saw how a sandbox object gets created. 

Since sandbox object gets created by calling `controller.NewSandbox()` method, let's see exactly how this is done by looking at the code inside the `controller.go`:

```go
func (c *controller) NewSandbox(containerID string, options ...SandboxOption) (Sandbox, error) {
...
  // Create sandbox and process options first. Key generation depends on an option
  if sb == nil {
    sb = &sandbox{
      id:                 sandboxID,
      containerID:        containerID,
      endpoints:          epHeap{},
...
    }
  }

  heap.Init(&sb.endpoints)
```

The last statement explains why sandbox connects networks in random order. The `endpoints` array is, in fact, a [heap][heap] - an ordered tree, where parent node is always smaller than (or equal to) its children (minheap). Heap is used to implement a priority queue, which should be familiar to every network engineer who knows QoS. One of heap's properties is that it re-orders elements every time an element gets added or removed, in order to maintain the heap invariant (parent <= child).

# Problem solution

It turns out the problem demonstrated above is a very well-known problem with multiple opened issues on Github [[1][issue-1],[2][issue-2],[3][issue-3]]. I was lucky enough to have discovered this problem right after [this pull request][pull-fix] got submitted, which is what helped me understand what the issue was in the first place. This pull request reference a [patch][patch] that swaps the heapified array with a normal one. Below I'll show how to build a custom docker daemon binary using this patch. We'll start with a privileged centos-based Docker container:

```bash
docker run --privileged -it centos bash
```

Inside this container we need to install all the dependencies along with Docker. Yes, you need Docker to build Docker:

```bash
yum install -y git iptables \
            make "Development Tools" \
            yum-utils device-mapper-persistent-data \
            lvm2

yum-config-manager --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

yum install docker-ce -y

# Start docker in the background
/usr/bin/dockerd >/dev/null &
```

Next let's clone the Docker master branch and the patched fork of libnetwork:

```bash
git clone --depth=1 https://github.com/docker/docker.git /tmp/docker-repo
git clone https://github.com/cziebuhr/libnetwork.git /tmp/libnetwork-patch
cd /tmp/libnetwork-patch
git checkout d047825d4d156bc4cf01bfe410cb61b3bc33f572
```

I tried using [VNDR](https://github.com/LK4D4/vndr) to update the libnetwork files inside the Docker repository, however I ran into problems with incompatible git options on CentOS. So instead I'll update libnetwork manually, with just the files that are different from the original repo:

```bash
cd /tmp/libnetwork-patch
/usr/bin/cp controller.go endpoint.go sandbox.go sandbox_store.go /tmp/docker-repo/vendor/github.com/docker/libnetwork/
```

Final step is to build docker binaries. This step may require up to 100G of free disk space and may take up to 60 minutes depending on your network speed.

```bash
cd /tmp/docker-repo
make build
make binary
...
Created binary: bundles/binary-daemon/dockerd-dev
```

# Verification

Once done, we can retrieve the binaries outside of the build container:

```bash
find /var/lib/docker -name dockerd
/var/lib/docker/overlay2/ac310ef5172acac7e8cb748092a9c9d1ddc3c25a91e636ab581cfde0869f5d76/diff/tmp/docker-repo/bundles/binary-daemon/dockerd
```

Now we can swap the current docker daemon with the patched one:

```bash
yum install which -y
systemctl stop docker.service
DOCKERD=$(which dockerd)
mv $DOCKERD $DOCKERD-old
cp /tmp/docker-repo/bundles/latest/binary-daemon/dockerd $DOCKERD
systemctl start docker.service
```

If we re-run our tests now, the interfaces are returned in the same exact order they were added:

```bash
docker start test
docker exec -it test sh -c "ip a | grep 'inet'"
inet 127.0.0.1/8 scope host lo
inet 172.26.0.2/16 brd 172.26.255.255 scope global eth0
inet 172.17.0.2/16 brd 172.17.255.255 scope global eth1
inet 172.18.0.2/16 brd 172.18.255.255 scope global eth2
inet 172.19.0.2/16 brd 172.19.255.255 scope global eth3
inet 172.20.0.2/16 brd 172.20.255.255 scope global eth4
```

---

Huge kudos to the original [author](https://github.com/cziebuhr) of the [libnetwork patch][patch] which is the sole reason this blogpost exists. I really hope that this issue will get resolved, in this form or another (could it be possible to keep track of the order in which endpoints are added to a sandbox and use that as a criteria for heap sort?), as this will make automated network testing much more approachable. 


[network-ci]: /blog/2016/02/19/network-ci-intro/
[unl-rest]: /blog/2016/01/01/rest-for-neteng/
[docker-py]: http://docker-py.readthedocs.io/en/stable/containers.html
[issue-1]: https://github.com/moby/moby/issues/25181
[issue-2]: https://github.com/moby/moby/issues/23742
[issue-3]: https://github.com/moby/moby/issues/35221
[pull-fix]: https://github.com/docker/libnetwork/issues/2093
[heap]: https://golang.org/pkg/container/heap/
[patch]: https://github.com/cziebuhr/libnetwork/commit/d047825d4d156bc4cf01bfe410cb61b3bc33f572
[libnet-arch]: https://github.com/docker/libnetwork/blob/master/docs/design.md