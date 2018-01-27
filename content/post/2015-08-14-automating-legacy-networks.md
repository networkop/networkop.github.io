+++
title = "Automating Legacy Network Configuration"
date = 2015-08-14T00:00:00Z
categories = ["automation"]
url = "/blog/2015/08/14/automating-legacy-networks/"
slug = "/blog/2015/08/14/automating-legacy-networks/"
tags = ["network-ansible","Ansible", "DevOps"]
summary = "In this post I'll show how to take an already established network, pull out some of the common configuration pieces and put them all into a standard Ansible environment"
draft = false
+++

A lot of configuration files referenced throughout this post will be omitted for the sake of brevity, however all of them can be found in my [github repository][github-repo-link].

# Legacy network overview

The network I'm using for demonstration is a cut-down version of a typical enterprise network. At this point of time it consists of a branch office network and a central DC network interconnected via redundant WAN links.
The branch office consists of a main computer room hosting all core network devices and interconnecting with access switches on each of the office floors. Data Centre consists of a comms rack hosting all networking devices and a compute rack with [TOR](abbr:Top-Of-the-Rack) switch connected back to the core.

![Legacy Network Topology](/img/legacy-network-design.png)

# Ansible environment setup

As per the Ansible's [best practices][ansible-bcp-link] all configuration tasks are split into separate `roles`. Variables will be assigned to groups and we'll use host-specific variables to override them if necessary. A special directory `./files` will store all Ansible-generated configuration files.

``` bash
drwxr-xr-x  2 root root 4096 Jul 12 20:54 host_vars
drwxrwxrwx  2 root root 4096 Jul 12 16:32 files
drwxr-xr-x  7 root root 4096 Jul 12 20:56 group_vars
drwxr-xr-x  7 root root 4096 Jul 12 15:18 roles
-rw-r--r--  1 root root  120 Jul 12 19:57 ansible.cfg
-rw-r--r--  1 root root  549 Jul 12 15:20 hosts
-rw-r--r--  1 root root  104 Jul 12 15:20 init.yml
-rw-r--r--  1 root root  240 Jul 12 15:20 site.yml
```

All network devices will be defined within two sets of groups - geographical and functional. This dual-homing of devices in multiple groups will give us greater flexibility when it comes to variable assignment and device configuration.

``` bash
[acme:children]
DC
branch-1

[DC]
DC-CORE ansible_ssh_host=10.0.1.1
DC-WAN-1 ansible_ssh_host=10.0.1.2
DC-WAN-2 ansible_ssh_host=10.0.1.3
DC-TOR ansible_ssh_host=10.0.1.130

[branch-1]
BR-1-CORE ansible_ssh_host=10.0.2.1
BR-1-WAN-1 ansible_ssh_host=10.0.2.2
BR-1-WAN-2 ansible_ssh_host=10.0.2.3
BR-1-AS01 ansible_ssh_host=10.0.2.130
BR-1-AS02 ansible_ssh_host=10.0.2.131
BR-1-AS03 ansible_ssh_host=10.0.2.132

[routers]
DC-CORE
DC-WAN-1
DC-WAN-2
BR-1-CORE
BR-1-WAN-1
BR-1-WAN-2

[switches:children]
access_switches
core_switches

[core_switches]
DC-CORE
BR-1-CORE

[access_switches]
DC-TOR
BR-1-AS01
BR-1-AS02
BR-1-AS03
```

# Create variables

Now we need to create variables we'll use in our template files. To do that we'll create another directory structure within the `./group_vars` directory

``` bash
drwxr-xr-x 2 root root 4096 Jul 13 04:41 access_switches
-rw-r--r-- 1 root root  118 Jul 12 15:21 all
drwxr-xr-x 2 root root 4096 Jul 12 20:55 branch-1
drwxr-xr-x 2 root root 4096 Jul 12 20:56 branch-2
drwxr-xr-x 2 root root 4096 Jul 12 20:54 DC
-rw-r--r-- 1 root root  120 Jul 12 15:21 passwords
drwxr-xr-x 2 root root 4096 Jul 12 15:20 routers
drwxr-xr-x 2 root root 4096 Jul 13 04:41 switches
```

The two files - `all` and `passwords` will contain variables relevant to network as a whole and confidential information respectively. Each of the directories within `./group_vars` corresponds to a particular inventory group. Within those directories there are files containing group-specific variables, like ` ./group_vars/routers/common` below:

```bash

management_interface: Loopback0

external_interface_bw:
  DC-WAN-1:
    Ethernet0/1: 10000
  DC-WAN-2:
    Ethernet0/1: 5000
  BR-1-WAN-1:
    Ethernet0/0: 10000
  BR-1-WAN-2:
    Ethernet0/0: 5000
```

This file contains management interface for all routed devices as well as external interface bandwidth information which will be used for QoS configuration later. 

# Create device configuration templates

To get started, we need to dump running configuration from all network devices and put it into Jinja templates. This only needs to be done once by running `ansible-playbook init.yml` command. This playbook uses `raw` module to get the running configuration from each device and stores this information in `./roles/non-standard/templates/{{"{{inventory_hostname"}}}}.j2` files.

# System management configuration automation

Now, it's finally time to do some automation. Since all our devices have similar configuration of AAA, SYSLOG, NTP, VTY and SNMP we can easily remove these parts from `non-standard` templates and put them into a `management` role.
To do this we'll:

1. Create a template configuration file for each of the system management components (aaa, syslog etc.)
2. Remove all IP addresses from those templates and replace them with variables
3. Remove the duplicate lines from each of the templates in `non-standard` role

The main management template `./roles/management/templates/management.j2` will have a number of references to other template files

```json 
{% include "services.j2" %}
!
{% include "aaa.j2" %}
!
clock timezone {{ time_zone_name }} {{ time_zone_hours }} {{ time_zone_minutes }}
!
ip domain-name {{ domain_name }}
no ip domain-lookup
!
{% include "logging.j2" %}
!
{% include "snmp.j2" %}
!
{% include "ntp.j2" %}
!
{% include "ssh.j2" %}
!
{% include "vty.j2" %}
```

Each of the included template files will contain only relevant configuration and will have some of its values replaced with variables, like the `snmp.j2` below:

```json
snmp-server community {{ snmp_ro_community }} RO
snmp-server trap-source {{ management_interface }}
snmp-server contact {{ snmp_contact }}
{% for ip in snmp_servers %}
snmp-server host {{ ip }} {{ snmp_servers[ip] }}
{% endfor %}
```

# Access switchport configuration

The trickiest part with automating switchport configuration is picking the right data structure to hold that information. There can be many switchport numbering schemes depending on whether the switches are stacked or the module number within the switch. I've decided to store all switchport allocation as port ranges defined for a particular VLAN. The variable will be a hash (dictionary) with VLAN number as keys and another dictionary as value. That other dictionary will have a `EtherTypeSwitch/Module` as a key and list of ranges as values, where each range is defined with a start and stop value. In our case the switches are not stacked so the `EtherTypeSwitch/Module` key can be reduced to simply `EtherTypeModule`. The below variable defines VLAN 10 on ports `Ethernet0/0-3` and `Ethernet2/0-3`:

```bash

access_ports:
  10:
    Ethernet0:
      - - 0
        - 3
    Ethernet2:
      - - 0
        - 3
  30:
    Ethernet3:
      - - 0
        - 3
  50:
    Ethernet5:
      - - 0
        - 3
  40:
    Ethernet4:
      - - 0
        - 3
  999:
    Ethernet0:
      - - 1
        - 3

```

Should the switch configuration differ from the above 'standard' (e.g. DC-TOR in our case) it can be included in a host-specific file under `./host_vars` directory which will override the variable defined above.  
The template which will generate the switchport configuration is designed to have VLAN-specific configuration elements like port shutdown in case the VLAN is unused or an additional voice vlan number.

```json
{%- for vlan in access_ports %}
  {%- for sw_module in access_ports[vlan] %}
    {%- for int_range in access_ports[vlan][sw_module] %}
      {%- for x in range(int_range[0],int_range[1]) %}
        interface range {{ sw_module }}/{{ x }}
        switchport mode access
        switchport access vlan {{ vlan }}
        switchport spanning-tree portfast
        {% if vlan == 999 -%}
        shutdown
        {% endif -%}
        {% if vlan == 10 -%}
        switchport voice vlan 20
        {% endif -%}
      {% endfor -%}
    {% endfor -%}
  {% endfor -%}
{% endfor -%}
```

# VLANs configuration

The other common bit amongst most of the switches is VLAN and STP configuration. This can be easily extracted and put into a separate `vlans` role. To allocate VLANs we'll use the `group_vars/switches/vlans` file with the following variables:

``` 
vlans:
  10: DATA
  20: VOICE
  30: MGMT
  40: PRINTER
  50: WLAN
  999: UNUSED
```

# QoS configuration

QoS configuration automation is relatively easy. Once we've identifies the common configuration commands and removed them from `non-standard` templates, we will put them into their own `wan-qos` role and use the `external_interface_bw` variable defined above to populate the QoS template.


# Site Playbook

Finally we'll combine all the roles defined above in a single playbook `./site.yml` which will generate configuration files for all devices and place them under `./files` directory.

```
- hosts: acme
  gather_facts: false
  connection: local
  vars_files:
  - group_vars/passwords
  roles:
    - non-standard
    - management

- hosts: routers
  gather_facts: false
  connection: local
  roles:
    - wan-qos

- hosts: switches
  gather_facts: false
  connection: local
  roles:
    - access-ports
    - vlans
```

By this time `.non-standard` files should only contain inter-device link and routing configuration. All management, access switchport, VLANs and QoS configuration has been removed and allocated to different roles.

---

This post demonstrated how to abstract common pieces of configuration and lay the groundwork for future site provisioning and enterprise-wide configuration changes. In the next post I'll show how to use the information collected so far to automate the build of a new branch office network.

[ansible-bcp-link]: http://docs.ansible.com/ansible/playbooks_best_practices.html
[ansible-intro-link]: http://networkop.github.io/blog/2015/06/24/ansible-intro/
[github-repo-link]: https://github.com/networkop/cisco-ansible-provisioning
[ansible-variable-prec]: http://docs.ansible.com/ansible/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable
