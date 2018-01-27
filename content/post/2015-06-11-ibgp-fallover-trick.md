+++
title = "iBGP Fall-over Trick"
date = 2015-06-11T00:00:00Z
categories = ["design"]
tags = ["BGP"]
url = "/blog/2015/06/11/ibgp-fallover-trick/"
summary = "iBGP fall-over trick"
+++

BGP fall-over is a neat BGP convergence optimisation technique whereby BGP peering is brought down as soon as the route to neighbor disappears from a routing table.
The difference between external and internal BGP is that the former usually peers over a directly-attached interface so that when the interface to neighbor is disconnected,
route is withdrawn from the routing table which triggers eBGP fall-over to bring down the neighborship.
iBGP, on the other hand, normally uses device loopbacks to establish peering sessions. What this means is if a summary or a default route is present in the routing table (either static or learned
via IGP), there is always a route to iBGP neighbor. In this case BGP has to wait for default 180 seconds (3 x keepalive timer) to bring down the neighborship and withdraw all the routes learned from dead neighbor.  
To overcome that there's a route-map option for a `neighbor fall-over` command which allows user to specify the exact prefix for which to look in the routing table. In the example below, the router will 
look for specific host routes representing neighbor's loopbacks and will trigger reconvergence as soon as those routes disappear. 

```
!
router bgp 100
 neighbor 1.1.1.1 remote-as 100
 neighbor 1.1.1.1 fall-over route-map RM-BGP-FALLOVER-1
 neighbor 2.2.2.2 remote-as 200
 neighbor 2.2.2.2 fall-over route-map RM-BGP-FALLOVER-2
!
ip prefix-list PL-ROUTER-1 seq 5 permit 1.1.1.1/32
!
ip prefix-list PL-ROUTER-2 seq 5 permit 2.2.2.2/32
!
route-map RM-BGP-FALLOVER-1 permit 10
 match ip address prefix-list PL-ROUTER-1
!
route-map RM-BGP-FALLOVER-2 permit 10
 match ip address prefix-list PL-ROUTER-2
!
```

It's obvious that this configuration is not very scalable as it requires a separate route-map and a separate prefix-list for each of the iBGP neighbors which, 
on a device like a route-reflector, can easily turn into dozens of lines of code.

# Solution
There is a nice and short way of how to accomplish the same task which relies on a prefix-list property often overlooked. Cisco's ip prefix-list are often used in the 
most straight-forward way, e.g. to define a a link-local subnet we'd use `169.254.0.0/16` or `0.0.0.0/0 le 32` for all possible prefixes. However, there's a way 
to define, for example, a list of prefixes that start with 10.0. and have a length from /24 to /25 with `10.0.0.0/16 ge 24 le 25`. In this case the first /16 defines
the number of bits in the prefix to be matched and ge, le simple define the length boundaries. Using a similar logic it is possible to define all prefix-list that
would match all possible host-routes - `ip prefix-list PL-ALL-LOOPBACKS seq 5 permit 0.0.0.0/0 ge 32`. The first part `0.0.0.0/0` makes the router ignore the actual
bits in the prefix effectively making it match ALL prefixes, while the second part `ge 32` tells the router to only match prefixes that are => 32 effectively matching 
only host-specific routes.  
With that in mind, it is possible to re-write the former 
config in a much more concise format so that all iBGP neighbors would use a single route-map with a single prefix-list.

```
!
router bgp 100
 neighbor 1.1.1.1 remote-as 100
 neighbor 1.1.1.1 fall-over route-map RM-BGP-FALLOVER
 neighbor 2.2.2.2 remote-as 200
 neighbor 2.2.2.2 fall-over route-map RM-BGP-FALLOVER
!
ip prefix-list PL-ALL-LOOPBACKS seq 5 permit 0.0.0.0/0 ge 32
!
route-map RM-BGP-FALLOVER permit 10
 match ip address prefix-list PL-ALL-LOOPBACKS
!
```

What happens now is that Cisco router, when bringing up the neighbor, scans it's own routing table looking for a /32 host-route that matches the ip address of that neighbor and 
attaches a listener to this route. If the neighbor goes down, the IGP will detect it a lot sooner than BGP and will withdraw that host-route; our router's bgp process will get notified
and will re-scan it's routing table for any other matches and, having found none, will bring down the neighborship immediately. Effectively this makes iBGP rely totally on timers of underlying IGP, which,
needless to say, dramatically speeds up convergence times for BGP.
