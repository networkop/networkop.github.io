---
layout: post
title: "Network TDD quickstart guide"
date: 2015-07-17
comments: true
sharing: true
footer: true
categories: [cisco, tdd]
description: Network TDD quickstart 
---

This post gives a quick overview of how to use network Test Driven Development framework. As an example I'll use a simplified version of a typical enterprise network with a Data Centre/HQ and a Branch office. A new branch is being added and the task is to configure routing for that branch using a TDD approach. First thing we'll devise a set of TDD scenarios to be tested and then, going through each one of them, modify routing to make sure those scenarios don't fail (a so-called red-green-refactor approach)

<!--more-->

## Network overview

Let's assume you're working in a proverbial Acme Inc. It has a Data Centre hosting all centralised services and a single office branch (Branch #1). Sites are interconnected using redundant active/backup WAN links. The company decides to expand and adds a new office in a city nearby. In additional to standard dual WAN links it's possible to buy a cheap and high throughput backdoor link between the two branches.

{% img centre /images/tdd-big-topo.png Acme Inc Topology%}  

## Devising TDD scenarios

After careful consideration of all links' bandwidths you devise a set of TDD scenarios and along with the high-level network topology present them to your management for endorsement. The idea is to always try to use the primary WAN link if possible. However for inter-branch communication, backdoor link should be the preferred option. When the primary link fails at the new branch, all traffic to and from the DC should traverse the backdoor link only falling back to the secondary WAN link in case both primary and backdoor link fail. This corresponds to the 4 TDD scenarios below:

{% codeblock lang:text ./scenarios/all.txt %}
1. Testing of Primary Link (default scenario)

1.1 From DC-CORE to BR2-CORE via DC-WAN1,BR2-WAN1
1.2 From BR2-CORE to DC-CORE via BR2-WAN1, DC-WAN1
1.3 From BR2-WAN1 to BR1-WAN1 via BR2-CORE,BR1-CORE
1.4 From BR1-WAN1 to BR2-WAN1 via BR1-CORE, BR2-CORE

2. Primary WAN failed at Branch #2

2.1 From DC-CORE to BR2-CORE via DC-WAN1,BR1-WAN1,BR1-CORE
2.2 From BR2-CORE to DC-CORE via BR1-CORE, BR1-WAN1, DC-WAN1
2.3 From BR2-WAN2 to BR1-WAN2 via BR2-CORE, BR1-CORE
2.4 From BR1-WAN2 to BR2-WAN2 via BR1-CORE, BR2-CORE

3. Backdoor link failed

3.1 From BR2-WAN2 to BR1-WAN2 via BR2-WAN1, BR1-WAN1
3.2 FROM BR1-WAN2 to BR2-WAN2 via BR1-WAN1, BR2-WAN1

4. Both Primary and Backdoor links failed at Branch #2

4.1 From DC-CORE to BR2-CORE via DC-WAN2, BR2-WAN2
4.2 From BR2-CORE to DC-CORE via BR2-WAN2, DC-WAN2
4.3 From BR2-CORE to BR1-CORE via BR2-WAN2, BR1-WAN2
4.4 From BR1-CORE to BR2-CORE via BR1-WAN2, BR2-WAN2
{% endcodeblock  %} 

## Network configuration

Acme Inc. uses OSPF for intra-site routing and BGP for WAN routing. A standard configuration assumes that the core router at each site is the route reflector for the two WAN routers. 

``` text CORE router configuratoin
interface Loopback0
 ip address 10.0.X.1 255.255.255.255
!
router ospf 100
 network 0.0.0.0 255.255.255.255 area 0
!
router bgp X
 bgp log-neighbor-changes
 timers bgp 1 5
 neighbor RR-CLIENTS peer-group
 neighbor RR-CLIENTS remote-as 1
 neighbor RR-CLIENTS update-source Loopback0
 neighbor RR-CLIENTS route-reflector-client
 neighbor 10.0.X.2 peer-group RR-CLIENTS
 neighbor 10.0.X.3 peer-group RR-CLIENTS
```

WAN routers originate site summary by first injecting their own Loopback IP address into BGP RIB and then aggregating it to site summary boundary (/24).

``` text WAN router 1 configuration
router ospf 100
 network 0.0.0.0 255.255.255.255 area 0
!
router bgp X
 bgp log-neighbor-changes
 network 10.0.X.2 mask 255.255.255.255
 aggregate-address 10.0.X.0 255.255.255.0
 neighbor <PRIMARY_PE_IP> remote-as <PRIMARY_WAN_AS>
 neighbor 10.0.X.1 remote-as 1
 neighbor 10.0.X.1 update-source Loopback0
```

No special path manipulation is done on either WAN routers.

``` text WAN router 2 configuration
router ospf 100
 network 0.0.0.0 255.255.255.255 area 0
!
router bgp X
 bgp log-neighbor-changes
 network 10.0.X.2 mask 255.255.255.255
 aggregate-address 10.0.X.0 255.255.255.0
 neighbor <BACKUP_PE_IP> remote-as <BACKUP_WAN_AS>
 neighbor 10.0.X.1 remote-as 1
 neighbor 10.0.X.1 update-source Loopback0
```

The same pattern is repeated on all sites with the exception of an additional backdoor link between the branch sites over which the two cores run eBGP.

## Preparing the test environment

``` bash Getting it
git clone https://github.com/networkop/simple-cisco-tdd.git tdd-acme-inc
cd tdd-acme-int
```

``` INI ./myhosts
[dc-devices]
DC-CORE ansible_ssh_host=10.0.1.1
DC-WAN1 ansible_ssh_host=10.0.1.2
DC-WAN2 ansible_ssh_host=10.0.1.3

[br1-devices]
BR1-CORE ansible_ssh_host=10.0.2.1
BR1-WAN1 ansible_ssh_host=10.0.2.2
BR1-WAN2 ansible_ssh_host=10.0.2.3

[br2-devices]
BR2-CORE ansible_ssh_host=10.0.3.1
BR2-WAN1 ansible_ssh_host=10.0.3.2
BR2-WAN2 ansible_ssh_host=10.0.3.3

[cisco-devices:children]
dc-devices
br1-devices
br2-devices
```

``` yaml ./group_vars/cisco-devices.yml
---
ansible_ssh_user: cisco
ansible_ssh_pass: cisco
```

``` bash
ansible-playbook cisco-ip-collect.yml
```

``` bash 
cat ./group_vars/all.yml
```

## Test the default scenario

``` bash
ansible-playbook cisco_tdd.yml
Enter scenario number [1]: 1
...
skipping: [DC-WAN1]
skipping: [BR1-CORE]
skipping: [DC-WAN2]
skipping: [BR1-WAN2]
skipping: [BR2-WAN2]
ok: [BR2-CORE] => (item={'key': 'DC-CORE', 'value': ['BR2-WAN1', 'DC-WAN1']})
ok: [BR2-WAN1] => (item={'key': 'BR1-WAN1', 'value': ['BR2-CORE', 'BR1-CORE']})
ok: [BR1-WAN1] => (item={'key': 'BR2-WAN1', 'value': ['BR1-CORE', 'BR2-CORE']})
ok: [DC-CORE] => (item={'key': 'BR2-CORE', 'value': ['DC-WAN1', 'BR2-WAN1']})

```

Seeing all green

## Testing the primary link failure

``` text BR2-WAN1
BR2-WAN1#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
BR2-WAN1(config)#int eth 0/0
BR2-WAN1(config-if)#shut
```

``` bash
ansible-playbook cisco_tdd.yml
Enter scenario number [1]: 2
...
failed: [DC-CORE] => (item={'key': 'BR2-CORE', 'value': ['DC-WAN1', 'BR1-WAN1']}) => {"failed": true, "item": {"key": "BR2-CORE", "value": ["DC-WAN1", "BR1-WAN1"]}}
msg: Failed scenario Primary WAN failed at Branch #2.
Traceroute from DC-CORE to BR2-CORE has not traversed ['DC-WAN1', 'BR1-WAN1']
 Actual path taken: DC-CORE -> DC-WAN2 -> 2.2.2.2 -> BR2-WAN2 -> BR2-CORE
ok: [BR1-WAN2] => (item={'key': 'BR2-WAN2', 'value': ['BR1-CORE', 'BR2-CORE']})
failed: [BR2-CORE] => (item={'key': 'DC-CORE', 'value': ['BR1-CORE', 'BR1-WAN1']}) => {"failed": true, "item": {"key": "DC-CORE", "value": ["BR1-CORE", "BR1-WAN1"]}}
msg: Failed scenario Primary WAN failed at Branch #2.
Traceroute from BR2-CORE to DC-CORE has not traversed ['BR1-CORE', 'BR1-WAN1']
 Actual path taken: BR2-CORE -> BR2-WAN2 -> 2.2.3.2 -> DC-WAN2 -> DC-CORE

ok: [BR2-WAN2] => (item={'key': 'BR1-WAN2', 'value': ['BR2-CORE', 'BR1-CORE']})
```

``` text BR2-WAN1
route-map RM-BGP-PREPEND-IN permit 10
 set as-path prepend last-as 4
route-map RM-BGP-PREPEND-OUT permit 10
 set as-path prepend 3 3 3 3
!
router bgp 3
neighbor 2.2.3.2 route-map RM-BGP-PREPEND-IN in
neighbor 2.2.3.2 route-map RM-BGP-PREPEND-OUT out
!
```

``` bash
root@netops:~/quickstart# ansible-playbook cisco_tdd.yml
Enter scenario number [1]: 2
ok: [DC-CORE] => (item={'key': 'BR2-CORE', 'value': ['DC-WAN1', 'BR1-WAN1']})
ok: [BR1-WAN2] => (item={'key': 'BR2-WAN2', 'value': ['BR1-CORE', 'BR2-CORE']})
ok: [BR2-CORE] => (item={'key': 'DC-CORE', 'value': ['BR1-CORE', 'BR1-WAN1']})
ok: [BR2-WAN2] => (item={'key': 'BR1-WAN2', 'value': ['BR2-CORE', 'BR1-CORE']})


## Testing the Backdoor link failure

``` text BR2-WAN1
BR2-WAN1#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
BR2-WAN1(config)#int eth 0/0
BR2-WAN1(config-if)#no shut
```

``` text BR2-CORE
BR2-CORE#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
BR2-CORE(config)#int eth 0/2
BR2-CORE(config-if)#no shut
```

``` bash
root@netops:~/quickstart# ansible-playbook cisco_tdd.yml
Enter scenario number [1]: 3
ok: [BR1-WAN2] => (item={'key': 'BR2-WAN2', 'value': ['BR1-WAN1', 'BR2-WAN1']})
ok: [BR2-WAN2] => (item={'key': 'BR1-WAN2', 'value': ['BR2-WAN1', 'BR1-WAN1']})
```

## Testing of backup WAN

``` text BR2-WAN1
BR2-WAN1#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
BR2-WAN1(config)#int eth 0/0
BR2-WAN1(config-if)#shut
```

``` bash
ansible-playbook cisco_tdd.yml
Enter scenario number [1]: 4
ok: [DC-CORE] => (item={'key': 'BR2-CORE', 'value': ['DC-WAN2', 'BR2-WAN2']})
ok: [BR1-CORE] => (item={'key': 'BR2-CORE', 'value': ['BR1-WAN2', 'BR2-WAN2']})
ok: [BR2-CORE] => (item={'key': 'DC-CORE', 'value': ['BR2-WAN2', 'DC-WAN2']})
ok: [BR2-CORE] => (item={'key': 'BR1-CORE', 'value': ['BR2-WAN2', 'BR1-WAN2']})
```

## Conclusion
