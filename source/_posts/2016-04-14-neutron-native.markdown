---
layout: post
title: "Building a multi-node OpenStack environment inside UNetLab"
date: 2016-04-17
comments: true
sharing: true
footer: true
published: false
categories: [openstack, unetlab]
description: Building a 3-node Openstack environment with Leaf/Spine underlay
---

In this post we'll explore some of the basic concepts of Openstack networking project called Neutron. We'll peak inside the internal implementation of virtual networks created by Neutron and see what are some of the obvious drawbacks.

<!--more-->

## Previously on my blog

In the [previous post][openstack-post-1] I've demonstrated how to get a working instance of a single-node Openstack demo lab inside [UNetLab][unl]. In this post we'll continue building on that by adding two new compute nodes and redesigning our network to resemble something you might actually see in a real life.

### Openstack network requirements

Depending on the number of deployed [components][os-projects], Openstack physical network requirements could be different. In our case we're no going to deploy any storage solution and simply use the **ephemeral** storage, i.e. storage that's a part of a virtual machine. However, even in minimal installations, there are a number networks that should be considered separately due to different connectivity requirements:

* Server [OOB](abbr: Out-Of-Band) **management** network - this is usually a separate physical networks used mainly for server bootstrapping and OS deployment. It is a Layer 3 network with DHCP relays configured at each edge L3 interface and access to Internet package repositories.

* **API** network - used for internal communication between various Openstack services. This can be a routed network without Internet access. The only requirement is any-to-any reachability within a single Openstack environment.

* **External** network - used for public access to internal Openstack virtual machines. This is the *outside* of Openstack, similar to the zone of your perimeter firewall. All VMs will get IPs from the network when they get outside of Openstack environment. This network **must** be Layer 2 adjacent with our network control node.

* **Tenant** network - used for communication between virtual machines within Openstack environment. Thanks to the use of VXLAN overlay, this can be a simple routed network that has any-to-any reachability between all Compute and Network nodes.

### Simulating a server

Based on my experience a standard server would have at least 3 physical interfaces - one for OOB management and a pair of interfaces for application traffic. Our virtual VM will have only have `eth0` and `eth1` interfaces. 

To satisfy the requirement of a direct Internet access I'll connect `eth0` of all our servers to Workstation's NAT interface

The two applcation interfaces will normally be combined in a single [LAG](abbr: Link Aggregation Group) and connected to a pair of MLAG-capable TOR switches. Multi-chassis LAG or [MLAG][mlag] is a pretty old and well-understood technology so I'm not going to try and simulate it in the lab. Instead I'll simply assume that a server will be connected to a TOR switch via a single physical link. 

The above two simplifications will not have any effect on the final results of our simulations.

### Simulating a network

Our data centre network will be a routed leaf/spine [Clos][clos] fabric comprised of 3 leafs and 2 spine switches running a single-area 0 OSPF on all their links. Since we're going to need to fit more than one network into a single link to servers, all edge ports are going to be setup as trunks with the following Vlans:

* VLAN 100 - Openstack's tenant network. Terminated on leaf switches and subnet injected into OSPF. The subnet used for this Vlan is going to be `10.0.X.0/24`, where X equals the number of the leaf switch.
* VLAN 300 - Openstack's external network. In our case I'll connect it to Workstation's Host-only network interface configured with `192.168.247.0/24` subnet.

The links between switches are all L3 point-to-point with addresses borrowed from 169.254.0.0/16 range specifically to emphasize the fact that the fabric does not need to know anything about VM subnets. The sole function of a fabric is to deliver packets from one leaf to any other leaf via multiple equal cost paths, thereby achieving maximum link utilisation. Here's an example of a traceroute between Vlan100's of Leaf #1 and Leaf #3.

```text Traceroute inside an ECMP routed Clos frabric
L3#traceroute 10.0.1.1 source 10.0.3.1
Type escape sequence to abort.
Tracing the route to 10.0.1.1
VRF info: (vrf in name/id, vrf out name/id)
  1 169.254.31.111 1 msec
    169.254.32.222 0 msec
    169.254.31.111 0 msec
  2 169.254.12.1 1 msec
    169.254.11.1 1 msec *
``` 

All the above requirements result in the network that looks like this:

{% img center /images/neutron-native.png %}  

## Server configuration and Openstack installation

Refer to my [previous blogpost][openstack-post-1] for instructions on how to install Openstack. Most of those steps will still be valid with the following few exceptions:

1. Configuring `eth1` interface as dot1q trunk
2. 

```bash Controller
packstack --allinone \
    --os-cinder-install=n \
    --os-ceilometer-install=n \
    --os-trove-install=n \
    --os-ironic-install=n \
    --nagios-install=n \
    --os-swift-install=n \
    --os-gnocchi-install=n \
    --os-aodh-install=n \
    --os-neutron-ovs-bridge-mappings=extnet:br-ex \
    --os-neutron-ovs-bridge-interfaces=br-ex:eth1.300 \
    --os-neutron-ml2-type-drivers=vxlan,flat \
    --provision-demo=n \
    --os-compute-hosts=192.168.91.10,192.168.91.11,192.168.91.12 \
    --os-neutron-ovs-tunnel-if=eth1_100
```


## Creating a virtual network for a pair of VMs

```bash 
  neutron subnet-create --name public_subnet \
    --enable_dhcp=False \
    --allocation-pool=start=192.168.247.90,end=192.168.247.126 \
    --gateway=192.168.247.1 external_network 192.168.247.0/24

```

## Following the packet inside Openstack

### Unicast

### BUM


Add static ip
`neutron port-update e1788cfb-a731-4cc0-a28c-b279e876f3ff --allowed-address-pairs type=dict list=true mac_address=fa:16:3e:33:9f:06,ip_address=10.0.0.100`

## Looking inside the virtual network


## Cisco CLI to OVS dictionary

Similat to Cisco to Juniper command [conversion tables][cisco-junos]

| Goal | Cisco | Open vSwitch |
|------|-------|-------------|
| Show MAC address table | show mac address table | `ovs-appctl fdb/show br-int` |
| Show port numbers | show interface status | `ovs-ofctl show br-int` |
| Show OVS configuration | show run | `ovs-vsctl show` |
| Show packet forwarding rules | show ip route  | `ovs-appctl bridge/dump-flows` |
| Simulate packet flow | `packet-tracer` | `ovs-appctl ofproto/trace br-int in_port=1` |
| View configuration command history | `show archive log config` | `ovsdb-tool show-log -m` |

## Drawbacks

* Overhead created by multicast source replication
* All intra-tenant routed traffic needs to go through the network node
* Inability to control physical devices
* Network node must be layer 2 adjacent to external network segment

## Things to explore:
In the following posts I'll continue poking around Neutron and explore some of the less "standard" features like:

* [Load-Balancing-as-a-Service][lbaas]
* [L2 population][l2-pop]
* [Distributed Virtual Router][dvr]
* [L2 hardware gateway][l2-gw]
* [Network High Availability][ha]
* [Open Virtual Network for OVS][ovn]

[openstack-post-1]: http://networkop.github.io/blog/2016/04/04/openstack-unl/
[cisco-junos]: http://www.net-gyver.com/?page_id=1166
[ovs-tables-intro]: https://assafmuller.com/2013/10/13/open-vswitch-basics/
[ovs-tshoot]: http://www.yet.org/2014/09/openvswitch-troubleshooting/
[neutron-packet-flow]: https://www.rdoproject.org/networking/networking-in-too-much-detail/
[ovs-flow-logic]: https://wiki.openstack.org/wiki/Ovs-flow-logic
[ovs-flow-walkthrough]: http://www.opencloudblog.com/?p=300
[l2-pop]: https://wiki.openstack.org/wiki/L2population_blueprint
[l2-gw]: https://wiki.openstack.org/wiki/Neutron/L2-GW
[ml2-vxlan]: https://kimizhang.wordpress.com/2014/04/01/how-ml2vxlan-works/
[ovs-cheatsheet]: http://therandomsecurityguy.com/openvswitch-cheat-sheet/
[ovn]: https://github.com/openstack/networking-ovn
[dvr]: https://wiki.openstack.org/wiki/Neutron/DVR
[unl]: http://www.unetlab.com/
[lbaas]: https://wiki.openstack.org/wiki/Neutron/LBaaS
[ha]: https://wiki.openstack.org/wiki/Neutron/L3_High_Availability_VRRP
[mlag]: http://blog.ipspace.net/2010/10/multi-chassis-link-aggregation-basics.html
[clos]: https://en.wikipedia.org/wiki/Clos_network
[os-projects]: https://www.openstack.org/software/project-navigator/