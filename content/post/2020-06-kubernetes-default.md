+++
title = "Anatomy of the \"kubernetes.default\""
date = 2020-06-29T00:00:00Z
categories = ["howto"]
tags = ["devops", "k8s"]
summary = "Understanding how the default kubernetes service is configured"
description = "Understanding how the default kubernetes service is configured"
+++

Every Kubernetes cluster is provisioned with a special service that provides a way for internal applications to talk to the API server. However, unlike the rest of the components that get spun up by default, you won't find the definition of this service in any of the static manifests and this is just one of the many things that make this service unique.

## The Special One

To make sure we're on the same page, I'm talking about this:

```
$ kubect get svc kubernetes -n default
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   161m
```

This service is unique in many ways. First, as you may have noticed, it always occupies the first available IP in the Cluster CIDR, a.k.a. `--service-cluster-ip-range`. 

Second, this service is invincible, i.e. it will always get re-created, even when it's manually removed:

```
$ kubectl get svc
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   118s
$ kubectl delete svc kubernetes
service "kubernetes" deleted
$ kubectl get svc
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   0s
```

You may notice that it comes up with the same ClusterIP, regardless of how many services may already exist in the cluster. 

Third, this service does not have any matching pods, however it does have a fully populated `Endpoints` object:

```
$ kubectl get pod --selector component=apiserver --all-namespaces
No resources found
$ kubectl get endpoints kubernetes
NAME         ENDPOINTS                                         AGE
kubernetes   172.18.0.2:6443,172.18.0.3:6443,172.18.0.4:6443   4m16s
```

This last bit is perhaps the most curious one. How can a service have a list of endpoints when there are no pods that match this service's label selector? This goes against how services controller [works][service-ctrl].  Note that this behaviour is true even for managed kubernetes clusters, where the API server is run by the provider (e.g. GKE).

Finally, the IP and Port of this service get injected into every pod as environment variables:

```
KUBERNETES_SERVICE_HOST=10.96.0.1
KUBERNETES_SERVICE_PORT=443
KUBERNETES_SERVICE_PORT_HTTPS=443
```

These values can later be used by k8s controllers to [configure](https://github.com/kubernetes/client-go/blob/master/tools/clientcmd/client_config.go#L561) the client-go's rest interface that is used to establish connectivity to the API server:

```go
func InClusterConfig() (*Config, error) {

  host := os.Getenv("KUBERNETES_SERVICE_HOST"), 
  port := os.Getenv("KUBERNETES_SERVICE_PORT")

  return &Config{
		Host: "https://" + net.JoinHostPort(host, port),
  }
```

## Controller of controllers

To find out who's behind this magical service, we need to look at the code for the k/k's [master controller](https://github.com/kubernetes/kubernetes/blob/master/pkg/master/controller.go), that is described as the "controller manager for the core bootstrap Kubernetes controller loops", meaning it's one of the first controllers that gets spun up by the API server binary. Let's break it down into smaller pieces and see what's going on inside it. 


When the controller is started, it spins up a runner, which is a group of functions that run forever until they receive a stop signal via a channel. 

```go
// Start begins the core controller loops that must exist for bootstrapping
// a cluster.
func (c *Controller) Start() {
  
	c.runner = async.NewRunner(c.RunKubernetesNamespaces, c.RunKubernetesService, repairClusterIPs.RunUntil, repairNodePorts.RunUntil)
	c.runner.Start()
}

```

The most interesting is the second function - `RunKubernetesService()`, which is a control loop that constantly updates the default kubernetes service.

```go
// RunKubernetesService periodically updates the kubernetes service
func (c *Controller) RunKubernetesService(ch chan struct{}) {

	if err := c.UpdateKubernetesService(false); err != nil {
		runtime.HandleError(fmt.Errorf("unable to sync kubernetes service: %v", err))
	}
}
```

Most of the work is done by the `UpdateKubernetesService()`. This function does three things:

* Creates the "default" namespace whose name is defined in the `metav1.NamespaceDefault` variable.
* Creates/Updates the default kuberentes service.
* Creates/Updates the endpoints resource for this service.

```go
// UpdateKubernetesService attempts to update the default Kube service.
func (c *Controller) UpdateKubernetesService(reconcile bool) error {

	if err := createNamespaceIfNeeded(c.NamespaceClient, metav1.NamespaceDefault); err != nil {
		return err
   }

	if err := c.CreateOrUpdateMasterServiceIfNeeded(kubernetesServiceName, c.ServiceIP, servicePorts, serviceType, reconcile); err != nil {
		return err
	}

	if err := c.EndpointReconciler.ReconcileEndpoints(kubernetesServiceName, c.PublicIP, endpointPorts, reconcile); err != nil {
		return err
	}

	return nil
}
```

Finally, the `CreateOrUpdateMasterServiceIfNeeded()` function is where the default service is being built. You can see the skeleton of this service's object in the below snippet:
```go
const kubernetesServiceName = "kubernetes"

// CreateOrUpdateMasterServiceIfNeeded will create the specified service if it
// doesn't already exist.
func (c *Controller) CreateOrUpdateMasterServiceIfNeeded(serviceName string, serviceIP net.IP, servicePorts []corev1.ServicePort, serviceType corev1.ServiceType, reconcile bool) error {

	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      serviceName,
			Namespace: metav1.NamespaceDefault,
			Labels:    map[string]string{"provider": "kubernetes", "component": "apiserver"},
		},
		Spec: corev1.ServiceSpec{
			Ports: servicePorts,
			// maintained by this code, not by the pod selector
			Selector:        nil,
			ClusterIP:       serviceIP.String(),
			SessionAffinity: corev1.ServiceAffinityNone,
			Type:            serviceType,
		},
	}

	_, err := c.ServiceClient.Services(metav1.NamespaceDefault).Create(context.TODO(), svc, metav1.CreateOptions{})

	return err
}
```

The code above explains why this service can never be completely removed from the cluster - the master controller loop will always recreate it if it's missing, along with its endpoints object. However, this still doesn't explain how the IP for this service is selected nor where the endpoint IPs are coming from. In order to do this, we need to get a deeper look at how the API server builds its runtime configuration.


## Always the first

One of the interesting qualities of the ClusterIP of the `kubernetes.default` is that it always (unless manually overridden) occupies the first IP in the Cluster CIDR. The answer is hidden in the `ServiceIPRange()` function of the master controller's [service.go](https://github.com/kubernetes/kubernetes/blob/master/pkg/master/services.go):

```go

func ServiceIPRange(passedServiceClusterIPRange net.IPNet) (net.IPNet, net.IP, error) {

	size := integer.Int64Min(utilnet.RangeSize(&serviceClusterIPRange), 1<<16)
	if size < 8 {
		return net.IPNet{}, net.IP{}, fmt.Errorf("the service cluster IP range must be at least %d IP addresses", 8)
	}

	// Select the first valid IP from ServiceClusterIPRange to use as the GenericAPIServer service IP.
	apiServerServiceIP, err := utilnet.GetIndexedIP(&serviceClusterIPRange, 1)
	if err != nil {
		return net.IPNet{}, net.IP{}, err
	}

	return serviceClusterIPRange, apiServerServiceIP, nil
}
```

This function gets [called](https://github.com/kubernetes/kubernetes/blob/master/pkg/master/master.go#L292) when the master controller is started and hard-codes the service IP for the default service to the first IP of the range. Another interesting fact in this function is that it always checks that the Cluster IP range is at least /29, which fits 6 usable addresses in the worst case. The latter can probably be explained by the fact that the next size down is /30, which doesn't leave much room for user-defined clusterIPs after the `kubernetes.default` and `kube-dns.kube-system` are configured, so in the smallest possible cluster you can at least configure a few non-default services before you run out of IPs.

## Endpoint IPs

The way endpoint addresses are populated is different between managed (GKE, AKS, EKS) and non-managed clusters. Let's first have a look at a highly-available kind cluster:

```
$ kubectl describe svc kubernetes | grep Endpoints
Endpoints:         172.18.0.3:6443,172.18.0.4:6443,172.18.0.7:6443
```

Bearing in mind that by default kind would use `10.244.0.0/16` as the pod IP range and `10.96.0.0/12` as the cluster IP range, these IPs don't make a lot of sense. However, since kind uses kubeadm under the hood, which spins up control plane components as static pods, we can find API server pods in the `kube-system` namespace:


```
kubectl -n kube-system get pod -l tier=control-plane -o wide | grep api
kube-apiserver-kind-control-plane             1/1     Running   172.18.0.3
kube-apiserver-kind-control-plane2            1/1     Running   172.18.0.4
kube-apiserver-kind-control-plane3            1/1     Running   172.18.0.7
```

If we check the manifest of any of the above pods, we'll see that they are run with `hostNetwork: true` and those IP come from the underlying containers that kind uses as nodes. As a part of the `UpdateKubernetesService()` mentioned above, each API server in the cluster goes and [updates](https://github.com/kubernetes/kubernetes/blob/master/pkg/master/controller.go#L243) the `endpoints` object with its own IP and Port as defined in the [mastercount.go](https://github.com/kubernetes/kubernetes/blob/master/pkg/master/reconcilers/mastercount.go#L62):


```go
func (r *masterCountEndpointReconciler) ReconcileEndpoints(serviceName string, ip net.IP, endpointPorts []corev1.EndpointPort, reconcilePorts bool) error {

	e.Subsets = []corev1.EndpointSubset{{
		Addresses: []corev1.EndpointAddress{{IP: ip.String()}},
		Ports:     endpointPorts,
	}}
	klog.Warningf("Resetting endpoints for master service %q to %#v", serviceName, e)
	_, err = r.epAdapter.Update(metav1.NamespaceDefault, e)
}
```

---

With managed Kubernetes clusters, control-plane nodes are not accessible by end users, so it's harder to say exactly how endpoints are getting populated. However, it's fairly easy to imagine that a cloud provider spins up a 3-node control-plane with a load-balancer and configures all three API servers with this LB's IP as the `advertise-address`. This would results in a single endpoint that represents that managed control-plane load-balancer:


```
$ kubectl get ep kubernetes
NAME         ENDPOINTS          AGE
kubernetes   172.16.0.2:443   40d
```



[service-ctrl]: https://kubernetes.io/docs/concepts/services-networking/service/#defining-a-service
[capi-goals]: https://cluster-api.sigs.k8s.io/introduction.html
[kind-install]: https://kind.sigs.k8s.io/docs/user/quick-start/
[clusterctl]: https://cluster-api.sigs.k8s.io/user/quick-start.html#install-clusterctl 
[book-docker]: https://cluster-api.sigs.k8s.io/clusterctl/developers.html#additional-steps-in-order-to-use-the-docker-provider