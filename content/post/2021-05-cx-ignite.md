+++
title = "Containerising Cumulus Linux"
date = 2021-05-10T00:00:00Z
categories = ["howto"]
tags = ["cumulus", "docker"]
summary = "The story of containerising Cumulus VX"
description = "The story of containerising Cumulus VX"
images = ["/img/cumulus-cx.png"]
+++

In one of his [recent posts](https://blog.ipspace.net/2021/04/katacoda-netsim-containerlab-frr.html?utm_source=atom_feed), Ivan raises a question: "I can’t grasp why Cumulus releases a Vagrant box, but not a Docker container". Concidentally, only a few weeks before that I had [managed](https://twitter.com/networkop1/status/1384175045950414848) to create a Cumulus VX container image. Since then, I've done a lot of testing and discovered limitations of the pure containerised approach and how to overcome them while still retaining the container user experience. This post is a documentation of my journey from the early days of running Cumulus on Docker to the integration with containerlab and, finally, running Cumulus in microVMs backed by AWS's Firecracker VMM and Weavework's Ignite.

## Innovation Trigger

One of the main reason for running infrastructure simulation in containers is the famous Docker UX. Containers existed for a very long time but they only became mainstream when docker released their container engine. The simplicity of a typical docker workflow (build, ship, run) made it accessible to a large number of not-so-technical users and was the key to its popularity. 

Physical infrastructure, including networking hardware, has mainly been distributed in a VM form-factor, retaining much of the look and feel of the real hardware for the software processes running on top. However it didn't stop people from looking for a better and easier way to run and test it, some of the smartest people in the industry are always [looking](https://twitter.com/ibuildthecloud/status/1362162684637061121) for an alternative to a traditional VM/Vagrant approach.

While VM tooling has been pretty much stagnant for the last decade (think Vagrant), containers have a huge ecosystem of tools and an active community around it. Specifically in the networking area, in the last few years we've seen commercial companies like [Tesuto](https://www.fastly.com/press/press-releases/fastly-achieves-100-tbps-edge-capacity-milestone) and multiple open-source projects like [vrnetlab](https://github.com/plajjan/vrnetlab), [docker-topo](https://github.com/networkop/docker-topo), [k8s-topo](https://github.com/networkop/k8s-topo) and, most recently [containerlab](https://containerlab.srlinux.dev/).

When I joined Nvidia in April 2020, I thought it'd be a fun experiment for me to try to containerise Cumulus Linux and learn how the operating system works in the process.

## Peak of Inflated Expectations

This was the first problem to solve and, as it turned out, the easiest one as well. Thanks to the Debian-based architecture of Cumulus Linux, I was able to build a full Cumulus Linux container image with just a few lines:

```Dockerfile
FROM debian:buster

COPY data/packages packages
COPY data/sources.list /etc/apt/sources.list
COPY data/trusted.gpg /etc/apt/trusted.gpg
RUN apt install --allow-downgrades -y $(cat packages)
```

I extracted the list of installed packages and public APT repos from an existing Cumulus VX image, copied them into a debian-based base image and ran `apt install` -- that's how easy it was. Obviously the [actual Dockerfile](https://github.com/networkop/cx/blob/main/Dockerfile) ended up being a lot longer, but the main work is done in just these 4 lines. The rest of the steps are just setting up the required 3rd party packages and implement various workarounds and hacks.

![](/img/cumulus-cx.png)

Once the image is built, it can be run with just a single command. Note the presence of  the `privileged` flag, which is the easiest way to run systemd and provide NET_ADMIN and other capabilities required by Cumulus daemons:

```
docker run -d --name cumulus --privileged networkop/networkop/cx:latest
```

A few seconds later, the entire Cumulus software stack is fully initialised and ready for action. Users can either start an interactive session or run ad-hoc commands to communicate with Cumulus daemons:

```
$ docker exec cumulus net show system
Hostname......... 5b870d5c3d31
Build............ Cumulus Linux 4.3.0
Uptime........... 13 days, 5:03:30.690000

Model............ Cumulus VX
Memory........... 12GB
Disk............. 256GB
Vendor Name...... Cumulus Networks
Part Number...... 4.3.0
Base MAC Address. 02:42:C0:A8:DF:02
Serial Number.... 02:42:C0:A8:DF:02
Product Name..... Containerised VX
```

All this seemed pretty cool, but I still had doubts over the functionality of Cumulus dataplane on a general-purpose kernel. Most of the traditional networking vendors do not rely on native kernel dataplane and heavily modify or bypass it completely in order to implement all of the required NOS features. My secret hope was the Cumulus, being the Linux-native NOS, would somehow make it work with just a standard set of netlink APIs. The only way to find this out was to test.

## Building a test lab

I've decided that the best way to test is to re-implement the [Cumulus Test Drive](https://gitlab.com/cumulus-consulting/goldenturtle/cldemo2) environment to make use of Ansible playbooks that come with it. Here's a short snippet of containerlab's topology definition to match the CTD's topology:

```yaml
name: cldemo2-mini

topology:
  nodes:
    leaf01:
      kind: linux
      image: networkop/cx:latest
    leaf02:
      kind: linux
      image: networkop/cx:latest
...

  links:
    - endpoints: ["leaf01:swp1", "server01:eth1"]
    - endpoints: ["leaf01:swp2", "server02:eth1"]
    - endpoints: ["leaf01:swp3", "server03:eth1"]
    - endpoints: ["leaf02:swp1", "server01:eth2"]
    - endpoints: ["leaf02:swp2", "server02:eth2"]
    - endpoints: ["leaf02:swp3", "server03:eth2"]
    - endpoints: ["leaf01:swp49", "leaf02:swp49"]
    - endpoints: ["leaf01:swp50", "leaf02:swp50"]
```

The entire lab can be spun up with a single command in under 20 seconds (10th gen i7 in WSL2):

```bash
$ sudo containerlab deploy -t cldemo2.yaml
```

At the end of the `deploy` action, containerlab generates an Ansible inventory file which, with a few minor modifications, can be re-used for the Cumulus Ansible [modules](https://gitlab.com/cumulus-consulting/goldenturtle/cumulus_ansible_modules). At this stage I was able to test any of the 4 available EVPN-based [designs](https://gitlab.com/cumulus-consulting/goldenturtle/cumulus_ansible_modules#how-to-use) and swap them around with just a few commands. This is where the fairy tale ended.

## The Trough of Disillusionment

The first few topologies I'd spun up and tested worked pretty well out of the box, however I did notice that my fans were spinning up like crazy. Upon further examination I had noticed that the `clagd` and `neighmgrd` were intermittently fighting to take over all available CPU threads while nothing was showing up in the logs. That's when I decided to have a look at the peerlink, thankfully it was super easy to do `ip netns exec FOO tcpdump` from my WSL2 VM. When I saw hundreds of lines flying on my screen in the next few seconds, I quickly realised it was a L2 loop (also because all of the packets were BUM). 

At this point it is worth mentioning that one of the hacks/workarounds I had to implement when building an image was stubbing out the `mstpd`. At first I didn't think too much of it, kernel was still running CSTP and the speed of convergence wasn't that big of an issue for me. However, as I was digging deeper, I realised that `mstpd` must be communicating with `clagd` in order to control the status of the peerlink VLANs (traffic is not forwarded over the peerlink under normal conditions). That fact alone meant that the standard kernel STP implementation will never be able to by controller by the `clagd`. My heart sank, at this stage I was ready to give up and admit that there's no way that one of the widely deployed features (CLAG) would work inside a container. 

The only way to make Cumulus Linux work in a containerised environment would be to run it on a native Cumulus Kernel which, as I discovered later, was very [heavily patched](http://oss.cumulusnetworks.com/CumulusLinux-2.5.1/patches/kernel/). So, in theory, I could run tests on a beefy Cumulus VX VM with all services but docker disabled, but that's a big ask and not a nice UX I was hoping for...

## Slope of Enlightenment


[Firecracker](https://firecracker-microvm.github.io/)





![](/img/cumulus-fc.png)


## Plateau of Productivity

This stage is still a fair way out. There are multiple pull requests to be merged before this kind of experience can become accessible to a wider audience. I'm still not sure about some of the approaches I had taken and need to verify and discuss them with the projects maintainers. However, the results I've achieved so far can definitely quialify as the bright light at the end of the tunnel and, hopefully, it's only a matter of time. In the meantime, if you're interested, feel free to reach out to me and I'll try to help you get started using containerised Cumulus Linux both as a node in containerlab and, potentially, even using it for large-scale simulations on top of Kubernetes. 



