---
layout: post
title: "Network-CI Part 3 - OSPF to BGP migration in Active/Standby DC"
date: 2016-03-23
comments: true
sharing: true
footer: true
published: false
categories: [network, automation, devops, routing]
description: Migrating a small DC from OSPF to BGP the DevOps-way
---

The final post in a series demonstrates how to use the **network-ci** tools to safely replace a core routing protocol inside a small Active/Standby Data Centre. 

<!--more-->

## Current network overview

Let's start by taking a high-level look at our DC network routing topology. The core routing protocol is OSPF, it is responsible for distributing routing information between the Core and WAN layers of the network. WAN layer consists of two MPLS L3VPN services running BGP as PE-CE protocol and two DMVPN Hubs running EIGRP. All WAN layer devices perform mutual redistribution between the respective WAN protocol and OSPF. 

{% img center  /images/network-ci-dc-before.png Current network topology %} 


## Target network overview

The task is to replace OSPF with BGP as the core routing protocol inside the DC. There are many advantages to using BGP inside a DC, in our case they are:

* Enhanced trafic routing and filtering policies
* Reduced number of redistribution points

We're not going getting rid of OSPF completely, but rather reduce its function to a simple distribution of *internal* DC prefixes. BGP will be running on top of OSPF and distribute all the DC and WAN *summary* prefixes. 

{% img center  /images/network-ci-dc-after.png Target network topology %} 

## Physical topology overview

Now let's take a closer look at the network that we're going to emulate. All green devices on the left-hand side constitute the **Active** Data Centre, that is where all the traffic will flow under normal conditions. All green devices have red **Standby** counterparts. These devices will pick up the function of traffic forwarding in case their green peer becomes unavailable.

{% img center  /images/network-ci-dc-full.png Full demo topology %} 

When simulating a real-life network it's often impossible to fit an exact replica inside a network emulator. That's why using **mock** devices is a crucial part in every simulation. The function of a mock is to approximate a set of network devices. There's a number of mock devices on our diagram colour-coded in purple. These devices simulate the remaining parts of the network. For example, **Cloud** devices may represent [TOR](abbr: Top-Of-the-Rack) switches, while **MPLS/DMVPN** devices represent remote WAN sites. Normally these devices will have some made-up configuration that best reflects real life, but not necessarily a copy-paste from an exisiting network device.  

 

It's also important to pick the right amount of mock devices to strike the balance between accuracy and complexity. For example, for WAN sites it may suffice to create one site per unique combination of WAN links to make sure WAN failover works as expected.

##  Traffic flow definition

Let's define how we would expect the traffic to flow through the network. Let's assume that we should always try to use MPLS links when possible and only use DMVPN when both MPLS links are down. This translates to the following order of WAN links' precedence:

1. Primary MPLS link
2. Standby MPLS link
3. Primary DMVPN link
4. Standby DMVPN link

Based on that we can create the following traffic flows definition for network working under normal conditions.

``` text /network/tests/traffic_flows.txt
1 Failed None
  From FW to MPLS-DMVPN via Primary-WAN, Primary-MPLS
  From FW to DMVPN-ONLY via Primary-CORE-SW, Primary-DMVPN
  From FW to MPLS-ONLY via Primary-WAN, Primary-MPLS
  From Cloud-1 to FW Loopback0 via Primary-CORE-SW
  From Cloud-2 to MPLS-DMVPN via Primary-WAN, Primary-MPLS
```

We expect all traffic to flow through active devices, even when the path may be suboptimal, like it's the case with traffic from Cloud-2. Similarly, we can create traffic flows definitions for different failure conditions. You can find complete traffic flows definition file in [this project's github repository][traffic-flows-links].

## Live demo

YOUTUBE LINK

## Source code
All code from this post and previous posts is available on [Github][config-after]


[traffic-flows-links]: https://github.com/networkop/network-ci/blob/master/acme-large/network/tests/traffic_flows.txt
[config-before]: https://github.com/networkop/network-ci/tree/29be6e0c7169ea51b501d110e59c44853d2fe1c5/acme-large/config
[config-after]: 