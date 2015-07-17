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

This post gives a quick overview of how to use network Test Driven Development framework. As an example I'll use a simplified version of a typical enterprise network with a Data Centre/HQ and a Branch office. A new branch is being added and the task is to configure routing for that branch using a TDD approach. First we'll devise a set of TDD scenarios to be tested and then, going through each one of them, modify routing to make sure those scenarios don't fail (a so-called red-green-refactor approach)

<!--more-->

## Network overview

Let's assume you're working in a proverbial Acme Inc. It has a Data Centre hosting all centralised services and a single office branch (Branch #1). Sites are interconnected using active/backup WAN links. The company decides to expand and adds a new office in a city nearby. In additional to standard dual WAN links it's possible to buy a cheap and high throughput backdoor link between the two branches.

{% img centre /images/tdd-big-topo.png Acme Inc. Topology%}  

## Network configuration

Acme Inc. uses OSPF for intra-site routing and BGP for WAN routing. A standard configuration assumes that the core router at each site is the route reflector for the two WAN routers. 

``` text CORE ROUTER CONFIG
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

``` text WAN ROUTER 1 CONFIG
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

No special path manipulation is done on either WAN routers by default.

``` text WAN ROUTER 2 CONFIG
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

The same pattern is repeated on all sites with the exception of an additional backdoor link between the branch sites over which the two cores run eBGP. Inter-device transit subnets can be anything within the site-allocated range.

## Devising TDD scenarios

After careful consideration of all links' bandwidths you devise a set of TDD scenarios and along with the high-level network topology present them to your management for endorsement. The idea is to always try to use the primary WAN link if possible. However for the inter-branch communication, backdoor link should be the preferred option. When the primary link fails at the new branch, all traffic to and from the DC should traverse the backdoor link only falling back to the secondary WAN link in case both primary and backdoor link fail. This corresponds to the 4 TDD scenarios (shown with coloured arrows on the above diagram):

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

## Preparing the test environment

First, you need to get a Linux machine connected to internet and to your network. A simply VM inside a VirtualBox would do. Now clone the git repository:
``` bash Cloning git repository
git clone https://github.com/networkop/simple-cisco-tdd.git tdd-acme-inc
cd tdd-acme-int
```
Populate Ansible hosts inventory. In this case hosts are assigned to the group corresponding to their site and all the site groups are assigned to a parent group.
``` text ./myhosts
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

Optionally, you can define your username/password credentials.
``` yaml ./group_vars/cisco-devices.yml
---
ansible_ssh_user: cisco
ansible_ssh_pass: cisco
```

Do the IP address information gathering and scenario processing first.
``` bash Run the fact gathering
./ansible-playbook cisco-ip-collect.yml
```

Verify that IP addresses and scenarios are now recorded in a global group variable file.
``` bash Verify the content of all.yml file
cat ./group_vars/all.yml
```

## Test the default scenario

Now it's time to test. First, the default scenario:
``` bash Testing scenario #1
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

All tests succeeded. 

## Testing the primary link failure

Now, let's simulate the failure of a primary WAN link by shutting down the uplink on the WAN router:
``` text BR2-WAN1
BR2-WAN1#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
BR2-WAN1(config)#int eth 0/0
BR2-WAN1(config-if)#shut
```

And now run the second scenario:
``` bash Testing scenario #2 - failed
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

Right, here is where it gets interesting. You see that the two scenarios have failed. Specifically traffic between the new branch and the DC has not traversed the backdoor link preferring the backup WAN instead. So we need to make the backup WAN less preferred. The easiest way is to use `as-path prepend` feature. Let's modify the configuration of our backup WAN router:

``` text BR2-WAN1
route-map RM-BGP-PREPEND-IN permit 10
 set as-path prepend last-as 4
route-map RM-BGP-PREPEND-OUT permit 10
 set as-path prepend 3 3 3 3
!
router bgp 3
neighbor 2.2.3.2 route-map RM-BGP-PREPEND-IN in
neighbor 2.2.3.2 route-map RM-BGP-PREPEND-OUT out
```

Now let's run the same test again:

``` bash Testing scenario #2 - success
ansible-playbook cisco_tdd.yml
Enter scenario number [1]: 2
ok: [DC-CORE] => (item={'key': 'BR2-CORE', 'value': ['DC-WAN1', 'BR1-WAN1']})
ok: [BR1-WAN2] => (item={'key': 'BR2-WAN2', 'value': ['BR1-CORE', 'BR2-CORE']})
ok: [BR2-CORE] => (item={'key': 'DC-CORE', 'value': ['BR1-CORE', 'BR1-WAN1']})
ok: [BR2-WAN2] => (item={'key': 'BR1-WAN2', 'value': ['BR2-CORE', 'BR1-CORE']})
```

Looks better now. Let's move on.

## Testing the Backdoor link failure
Next in order, backdoor link failure. First let's restore our primary WAN link first:
``` text BR2-WAN1
BR2-WAN1#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
BR2-WAN1(config)#int eth 0/0
BR2-WAN1(config-if)#no shut
```

And bring down the link between the two branches:
``` text BR2-CORE
BR2-CORE#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
BR2-CORE(config)#int eth 0/2
BR2-CORE(config-if)#shut
```

Run the third scenario:
``` bash Testing scenario #3
root@netops:~/quickstart# ansible-playbook cisco_tdd.yml
Enter scenario number [1]: 3
ok: [BR1-WAN2] => (item={'key': 'BR2-WAN2', 'value': ['BR1-WAN1', 'BR2-WAN1']})
ok: [BR2-WAN2] => (item={'key': 'BR1-WAN2', 'value': ['BR2-WAN1', 'BR1-WAN1']})
```

Looking good. Now even the backup WAN routers traverse the primary WAN to talk to each other. Just as we expected.

## Testing of backup WAN

Finally, let's see what would happen when both primary WAN and backdoor links go down. First, bring down the primary WAN link again:

``` text BR2-WAN1
BR2-WAN1#conf t
Enter configuration commands, one per line.  End with CNTL/Z.
BR2-WAN1(config)#int eth 0/0
BR2-WAN1(config-if)#shut
```

Run the last scenario:
``` bash
ansible-playbook cisco_tdd.yml
Enter scenario number [1]: 4
ok: [DC-CORE] => (item={'key': 'BR2-CORE', 'value': ['DC-WAN2', 'BR2-WAN2']})
ok: [BR1-CORE] => (item={'key': 'BR2-CORE', 'value': ['BR1-WAN2', 'BR2-WAN2']})
ok: [BR2-CORE] => (item={'key': 'DC-CORE', 'value': ['BR2-WAN2', 'DC-WAN2']})
ok: [BR2-CORE] => (item={'key': 'BR1-CORE', 'value': ['BR2-WAN2', 'BR1-WAN2']})
```

All tests passed. Now the network at the new branch is behaving exactly as we expect it to.

## Conclusion

The above scenario, of course, is a gross simplification of a real life, however the demonstrated approach can be applied to varied network topologies. The desired state may be achieved through not one but several red-green-refactor cycles. The benefit of using this approach is not only confidence that you haven't broken anything by fixing one particular failure condition scenario, but also for future growth and development, when new devices are added or traffic flows are modified, these same tests can be re-run to ensure that the agreed assumptions still hold. 