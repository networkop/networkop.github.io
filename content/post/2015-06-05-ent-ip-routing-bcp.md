+++
title = "Best practices for enterprise IP routing"
date = 2015-06-05T00:00:00Z
categories = ["design"]
url = "/blog/2015/06/03/ent-ip-routing-bcp/"
tags = ["BGP", "IGP", "routing", "enterprise"]
summary = "IGP/BGP best practices for enterprise network"
draft = false
+++

What motivated me to write this post is a state of the IP routing of some of the enterprise networks I've seen.
A quick `show ip route` command reveals a non-disentanglable mixture of dynamic and static route with multiple points of redistribution and complex, 
rigid filtering rules, something you'd only see in your bad dream or a CCIE-level lab. It certainly takes
a good engineer to understand how it works and even that can take up to several hours. I think the reason for that
is that people have generally been concentrated on learning about the routing protocol, how it works, all the knobs you can twist
to influence a routing decision logic. However, one thing often overlooked is the routing protocols best practice design, 
i.e. **when** and **how** to use a particular protocol.
And since the latter is often an acquired skill, a lot of not-so-lucky engineers end up with wrong ideas and concepts 
in the heads. Below I'll try to list what *I* consider a best practice design of today's enterprise networks. 

---

# OSPF, EIGRP, BGP? Which one to use?
Golden rule is to always use a protocol where it was designed to be used. Use and constrain IGP to a single autonomous system.
For enterprise networks autonomous system can be:

* a single, geographically-constrained office network
* remote branch office network
* campus network
* data centre

Use BGP to interconnect these systems. When there's a choice to use iBGP vs eBGP, always prefer eBGP since it has less restrictions. 
However for some designs iBGP is a better fit (i.e. Hub-and-Spoke topologies). Almost for every WAN technology there's a *preferred*
WAN protocol, e.g. eBGP for L3VPN, iBGP for DMVPN/FlexVPN, so always check with the vendor's design guide.

# IGP best practices
The choice of a particular IGP is mainly irrelevant. EIGRP scales better in a well-structured hierarchical network, whereas link-state protocol like OSPF
don't require any underlying structure. In fact, best practice for OSPF design, for quite some time, has been to put all routers in a single Area 0 regardless
of their geographical location. This rule, like any, has its' exceptions and special dampening/ advertisement containment rules need to be applied 
to links prone to flapping (e.g. aerial links). However, both EIGRP and OSPF have proven to be quite stable and scalable even with *not-so-good* designs.  
I follow the these rules when designing an IGP:

* Advertise all routers' networks, i.e. `network 0.0.0.0 255.255.255.255` command

> ideally within a single AS there will be a full-mesh reachability between the devices

* Explicitly control which interfaces will form routing adjacencies with `passive interface` commands
* statically set router-id to the address of loopback interface which uniquely identifies the device 
(not included in any other summary and not advertise by anyone else)
* When using EIGRP exclude bandwidth and leave only delay in metric calculation with `metric weights 0 0 0 1 0 0`

> as opposed to bandwidth, interface delay is uniquely used by EIGRP so changing it won't negatively affect any other processes

* When using OSPF always update reference bandwidth on all routers to 100G with `auto-cost reference-bandwidth 100000`
* All WAN links should be known to IGP natively but should be passive at the same time
* Avoid redistribution between IGP and BGP at all costs

> redistribution can create routing loops due to loss of native routing protocol metric. troubleshooting these loops is one of the most difficult
tasks for a network engineer


# BGP best practices
Whenever I design a non-stub (i.e. transit) network I try to enable BGP on all transit devices. This rule helps me avoid using redistribution between
IGP and BGP. Assuming a standard dual-core, dual-wan link topology the core will become a route-reflector whereas WAN routers will become RR-clients.
The only issue is that a lot of devices used in the network core still come with limit or no BGP support. In this case redistribution can be an option, however
carefull planning and strict filtering rules need to be put in place in order to prevent any potential routing loops.
These are my BGP best practices:

* Always statically configure BGP router-id to be equal to ip address of loopback interface
* Always send/receive both standard and extended communities `neighbor X.X.X.X send-community both`
* Always add description to a neighbor. You can't overdocument your network
* When configuring iBGP always use loopbacks (advertised by your IGP) for peering. This will help a lot with performance optimisation described below
* Always keep track of BGP AS numbers in use in the network
* For every network that doesn't need to be transit assign community `local-as` in the inbound route-map
* Whenever possible filter **outbound** rather than **inbound**

> this way only infromation **that is needed** is sent to the neighbor

* Always configure `ip bgp community new-format` on all routers
* Only inject **summaries** into BGP. The only exception can be routers' loopback address which can be used by remote SLA monitoring.

> This is the key distinction between IGP and BGP. IGPs deal with all networks within an AS big or small. 
BGP deals with networks that represent a whole AS, i.e. summaries.
Normally, the core device in the network originates a summary from a static *null* route and advertises it to all the neighbors. 

* Always tag all prefixes injected into BGP with communities. For example:

> 65000:0 - for site-specific summary  
> 65000:1 - for smaller, site-specific subnets outside of summary range (e.g. DMZ)  
> 65000:3 - for 3rd-party routes (e.g. provider-originated routes, interconnects with other clients)  

* Always filter based on communities rather than prefix lists or access-lists
* Do not use route filtering as a security measure. Firewalls are designed to do that
* For any route decision manipulation rely on explicitly configured metrics and not on, say, router-id or IGP metric

> Use as few metric manipulations as possible. For example use local-preference for outbound and as-path for inbound path selection

* Always tune BGP convergence timers (more on that below)

# BGP performance tuning

* BFD

This seemingly *old* technology unfortunately still sees very little adoption in the enterprise market. It is the best option for
fast high-bandwidth links and should be used whenever possible

* external/internal fall-over

This convergence optimisation techniques rely on the presence of route to neighbor in the routing table. 
as soon the route is gone, the neighborship is brought down. Fast fall-over is enabled by default for eBGP neighbors
on Cisco devices and should be enabled manually per neighbor(-group) for iBGP neighbors. 

```
# the following triggers fall-over only if host-route to neighbor disappears
router bgp 10
 neighbor 1.1.1.1 remote-as 10
 neigbhor 1.1.1.1 fall-over route-map RM-BGP-FALLOVER
!
ip prefix-list PL-ALL-LOOPBACKS 0.0.0.0/0 ge 32
!
route-map RM-BGP-FALLOVER
 match ip address prefix-list PL-ALL-LOOPBACKS
!
```

* BGP keepalive timer

Default BGP timers 30/180 seconds are too big for most of the cases. However, if fast fall-over is properly used they never need to be modified.
Internal fall-over effectively makes BGP neighborships rely on IGP default timers instead, while external fall-over will work only for directly connected
neighbor (or if a route to this neighbor recurses over a directly connected interface). The only reason to change the default timer values would be if the route
to external neighbor can potentially recurse over an internal interface (e.g. in case default route is present). In this case using `neighbor X.X.X.X keepalive 10 30`
would set keepalive/dead timers to 10/30 seconds. The timer values are negotiated to the lowest values between the two peers during neighborship establishment.

* Prefix-independent convergence and ip next-hop tracking

These two optimisation techniques do not require any configuration and are enabled by default in all recent code versions.
PIC decouples ip prefixes and next-hops and allows for quicker convergence when multiple BGP prefixes are present in BGP RIB with different next-hops.
IP NH-tracking triggers route recomputation based on changes in the routing table (i.e. next-hop becoming unavailable) rather than waiting for the periodic update 
scanner to run every 60 seconds. There's plenty of additional information about both PIC ([one][PIC-1], [two][PIC-2], [three][PIC-3]) and 
IP NH-tracking ([one][NH-1], [two][NH-2]) on the internet.


# Conclusion
Enterprise network designers should more often look at their Service Provider counterparts and how they do things. 
SP design practices have been evolving for years and proved to be stable and scalable. License permitting, we can 
apply the same rules in enterprise networks and end up with a more stable and scalable network.



[PIC-1]: http://blog.ipspace.net/2012/01/prefix-independent-convergence-pic.html
[PIC-2]: http://blog.ine.com/2010/11/22/understanding-bgp-convergence/
[PIC-3]: http://www.cisco.com/c/en/us/td/docs/routers/7600/ios/15S/configuration/guide/7600_15_0s_book/BGP.html
[NH-1]: http://blog.ine.com/2010/11/22/understanding-bgp-convergence/
[NH-2]: http://www.cisco.com/c/en/us/td/docs/ios/12_2sb/feature/guide/sbbnhop.html