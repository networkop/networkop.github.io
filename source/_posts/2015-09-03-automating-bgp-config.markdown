---
layout: post
title: "Automating new network build - Part 2 (BGP)"
date: 2015-09-03
comments: true
sharing: true
footer: true
categories: [network, automation]
description: BGP configuration automation
---

In this post we'll have a look at how to automate a typical BGP setup. This is where configuration may get particularly messy especially in presence of backdoor links and complex routing failover policies. However, as I will show, it is still possible to create a standard set of routing manipulation policies and selectively apply them to the required adjacencies to achieve the desired effect.

<!--more-->

## Requirements and assumptions

The new office network is designed with several layers of WAN redundancy. Primary WAN link is the preferred option to reach all other WAN destination except for the Main office which is connected via a dedicated high-throughput link. Secondary WAN link should only be used in case both primary and backdoor links are unavailable.  
All routed devices within Branch-2 will be running iBGP AS#3 with BR2-CORE playing a role of route-reflector for the two WAN routers. iBGP convergence timers should rely on IGP's timers (OSPF default timers of 10 and 40 seconds). Site's core switch should originate a site summary prefix as well as any other non-standard prefixes falling outside of the standard site summary (e.g. links to 3rd Parties, DMZ etc.). All prefixes originated by the site should be tagged with specific community values in order to be easily identifiable at the remote end. 

{% img centre /images/full-network-topo.png Full network topology%}


## eBGP configuration automation

Each site will have a unique set of eBGP peers, hence, it is logical to put all eBGP-related variables into a site-specific directory `group_vars/branch-2/`. In order to understand how to configure each eBGP neighbor the following values need to be defined for each eBGP neighbor:

1. IP addresses 
2. AS number 
3. (optional) Routing manipulation policies 

The above values correspond to the following Ansible variables:

``` yaml ./group_vars/branch-2/bgp
ebgp_peers:
  BR2-WAN1:
    1.1.1.2:
      - remote-as 1000
  BR2-WAN2:
    2.2.3.2:
      - remote-as 2000
      - route-map RM-BGP-PREPEND-OUT out
  BR2-CORE:
    10.0.2.49:
       - remote-as 2
```

Here `ebgp_peers` variable contains a mapping between network devices and their eBGP neighbors identified by their IP addresses. BGP path manipulation policies ideally should belong to global variables and are defined under the company-wide `routing` group

{% raw %}
``` yaml ./group_vars/routing/route-maps
bgp_out_rmap_prepend:
    - set as-path prepend {{ site_ASN }} {{ site_ASN }} {{ site_ASN }} {{ site_ASN }} {{ site_ASN }} {{ site_ASN }} {{ site_ASN }}
```
{% endraw %}

All information defined above will be reused by the `bgp` template of the `routing` ansible roles:

{% raw %}
``` yaml ./roles/routing/template/bgp
route-map RM-BGP-PREPEND-OUT permit 10
{%- for clause in bgp_out_rmap_prepend %}
  {{ clause }}
{% endfor -%}

router bgp {{ site_ASN }}
{%- if inventory_hostname in ebgp_peers %}
  {%- for neighbor_ip in ebgp_peers[inventory_hostname] %}
    {%- for option in ebgp_peers[inventory_hostname][neighbor_ip] %}
  neighbor {{ neighbor_ip }} {{ option }}
    {% endfor -%}
  {% endfor -%}
{% endif -%}
```
{% endraw %}

## iBGP configuration automation

Each site will be running a simple iBGP topology with a single route-reflector with two clients. Each routed device within the new branch will need to have it's iBGP role  defined (server or client). 

``` yaml ./group_vars/branch-2/bgp
ibgp_topo:
  route_reflector: [BR2-CORE]
  rr_clients: [BR2-WAN1, BR2-WAN2]

bgp_originate_redistribute:
  BR2-CORE:
    - summary
    - static

bgp_originate_network:
  BR2-WAN1:
    - Loopback0
  BR2-WAN2:
    - Loopback0

```

Special variables that start with `bgp_originate_` define which subnets should be originated by which router. RR-server will originate site-wide summary and any 3rd party subnets while WAN routers will inject their own loopbacks in order to be remotely accessible even if BR2-CORE goes down. Specific route maps responsible for prefix origination should be defined in the global scope:

{% raw %}
``` yaml ./group_vars/routing/route-maps
bgp_redistr_route_maps:
  static:
    - match tag {{ tags.static }}
    - set community {{ bgp_comm_static }}
  summary:
    - match tag {{ tags.summary }}
    - set community {{ bgp_comm_summary }}
```
{% endraw %}

The resulting configuration for BR2-CORE will looks like this:

``` text ./files/BR2-CORE.bgp
route-map RM-BGP-FROM-STATIC permit 10
  match tag 110
  set community 3:1
route-map RM-BGP-FROM-SUMMARY permit 10
  match tag 210
  set community 3:0

route-map RM-BGP-PREPEND-OUT permit 10
  set as-path prepend 3 3 3 3 3 3 3
!
ip prefix-list PL-ALL-LOOPBACKS permit 0.0.0.0/0 le 32 ge 32
!
route-map RM-BGP-FALLOVER permit 10
  match ip address prefix PL-ALL-LOOPBACKS
!
router bgp 3
  redistribute static route-map RM-BGP-FROM-SUMMARY
  redistribute static route-map RM-BGP-FROM-STATIC
  neighbor 10.0.2.49 remote-as 2
  neighbor RR-CLIENTS peer-group
  neighbor RR-CLIENTS remote-as 3
  neighbor RR-CLIENTS update-source Loopback0
  neighbor RR-CLIENTS fall-over route-map RM-BGP-FALLOVER
  neighbor RR-CLIENTS route-reflector-client
  neighbor 10.0.3.2 peer-group RR-CLIENTS
  neighbor 10.0.3.3 peer-group RR-CLIENTS
```

## Conclusion

This post concludes the series of articles describing how to automate enteprise network configuration. We first looked at how to automate [legacy network configuration][configuration-automation-intro], interface and OSPF configuration for the [new network build][configuration-automation-part1] and, finally, BGP configuration. Full version of files and scripts can be found in [my github repository][github-network-build].  

[configuration-automation-intro]: http://networkop.github.io/blog/2015/08/14/automating-legacy-networks/
[configuration-automation-part1]: http://networkop.github.io/blog/2015/08/26/automating-network-build-p1/
[github-network-build]: https://github.com/networkop/cisco-ansible-provisioning