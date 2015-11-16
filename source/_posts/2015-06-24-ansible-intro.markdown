---
layout: post
title: "Getting started with Ansible for Cisco IOS"
date: 2015-06-24
comments: true
sharing: true
footer: true
categories: [ansible, cisco]
description: Learn how to use Ansible to run commands on Cisco IOS
---

Ansible is well-known for it's low entry threshold. All what's required to get started is just one inventory file. However Cisco IOS devices require special considerations.
Passwordless SSH RSA-based authentication is still a novelty and in most cases users are authenticated based on their passwords. Another problem is the lack of Python execution
environment on IOS devices, which seriously limits the choice of Ansible modules that can be used. In this post I will show how to setup Ansible
environment to control Cisco IOS devices

<!--more-->

## Ansible overview

There's been a lot written about what Ansible is and what it was built to accomplish. I will just provide a brief summary of its features focusing on what we're gonna be using it for, leaving an in-depth explanation to the official [Ansible documentation](http://docs.ansible.com/).

* What is it? 

> Ansible is an IT automation and orchestration framework

* What was it built to accomplish?

> Ansible was designed to automate routine tasks like server/application deployment and configuration

* How does it work?

> It connects to several hosts at the same time and executes small programs called "modules" in the order specified in a file called "playbook"

To build what we've set out to accomplish I'm gonna be using the latter feature. I am not gonna be using Ansible for system provisioning or service orchestration. Instead, I will be exploiting Ansible's ability to run multiple parallel connections to remote hosts, execute commands on them and return their result. Due to that, I will diverge from some of the [Ansible's best practices](https://docs.ansible.com/playbooks_best_practices.html) of splitting functions into roles and I will use one flat playbook file segregating different functions with tags.

## Ansible configuration file

Ansible configuration file `ansible.cfg` contains [application-wide settings](http://docs.ansible.com/intro_configuration.html) like default timeouts, port numbers and other flags. The default Ansible configuration file is located in `/etc/ansible/` directory. However, instead of overwriting the defaults it is possible to create a configuration file in a local directory with only the settings that need to be overridden. To better work with Cisco devices the following settings will need to be modified:

* Default SSH library (transport) needs to be set to `paramiko` which is more stable than its alternative, OpenSSH, when working with Cisco IOS.
* For a small project it is easier to maintain a local copy of inventory file which is configured with `hostfile` setting.
* Strict SSH key checking is a MUST in every production environment, however, for development environment an exception can be made.
* Default SSH timeout is decreased to 5 seconds reflecting a small size of the testing environment.

``` bash ~/tdd_ansible/ansible.cfg
[defaults]
transport=paramiko
hostfile = ./myhosts
host_key_checking=False
timeout = 5
```

## Inventory file

Inventory contains the list of hosts to be managed by Ansible. Hosts are normally combined into groups (`cisco-devices` in our case) and Ansible performs actions on all hosts in the group in parallel.

``` bash ~/tdd_ansible/myhosts
[cisco-devices]
R1
R2
R3
R4
```
It is considered a [best practice](https://docs.ansible.com/playbooks_best_practices.html#group-and-host-variables) to keep all variables in separate folders and files. We need to define additional host variables to let Ansible know which IP address to use to connect to a remote device. I will also add SSH password to a host variable file which is a VERY bad practice, however this will prevent me from typing password every time I run a playbook. If I ever did this in production, I'd add host variables directory to `.gitignore` file so that it doesn't get uploaded to Github. Host variables files must follow YAML formatting, must be stored in a `./host_vars` directory and must match the name of the host they are being assigned to.
``` yaml ~/tdd_ansible/host_vars/R1
---
ansible_ssh_host: 10.0.0.1
ansible_ssh_pass: cisco
```

Similar files need to be created for R2, R3 and R4.

## Run a test traceroute commands

Now it is time to finally see Ansible in action. Let's first see if we can run a standalone traceroute command. I will manually define SSH username with `-u` flag and use a module called `raw` passing traceroute command as an argument with `-a` option.

``` bash Ad-hoc traceroute command
$ ansible cisco-devices -u cisco -m raw -a "traceroute 10.0.0.4 source Loopback0 probe 1 numeric"
SSH password:
R1 | success | rc=0 >>

Type escape sequence to abort.
Tracing the route to 10.0.0.4
VRF info: (vrf in name/id, vrf out name/id)
  1 14.14.14.4 0 msec *  0 msec

R2 | success | rc=0 >>

Type escape sequence to abort.
Tracing the route to 10.0.0.4
VRF info: (vrf in name/id, vrf out name/id)
  1 12.12.12.1 0 msec 0 msec 0 msec
  2  *  *
    14.14.14.4 0 msec

R3 | success | rc=0 >>

Type escape sequence to abort.
Tracing the route to 10.0.0.4
VRF info: (vrf in name/id, vrf out name/id)
  1 34.34.34.4 0 msec 0 msec *

R4 | success | rc=0 >>

Type escape sequence to abort.
Tracing the route to 10.0.0.4
VRF info: (vrf in name/id, vrf out name/id)
  1 10.0.0.4 0 msec 0 msec *
``` 

Ansible ad-hoc commands are a good way to quickly test something out and learn how things work. Next step would be to create a playbook file which will contain several of those commands in a more structured way. Playbooks use YAML syntax and follow strict formatting rules. At the top of the file there's a name of the play along with the target hosts group. Following that are a list of tasks, each of which calls its own module and passes arguments to it. In this example playbook does the following:

1. Defines a `loopbacks` variable which stores in a hash a list of devices along with their loopback IP addresses.
2. Uses `raw` module to run traceroute commands. This is the only module that doesn't require Python to be installed on a target machine.
3. For each host in `cisco-devices` group runs traceroute to every other hosts' loopback IP
4. Stores the result in a `trace_result` variable

{% raw %}
``` yaml ~/tdd_ansible/cisco-trace-run.yml
---
- name: Run traceroute commands
  hosts: cisco-devices
  gather_facts: false
  remote_user: cisco
  
  vars:
    loopbacks: {
    "R1": "10.0.0.1",
    "R2": "10.0.0.2",
    "R3": "10.0.0.3",
    "R4": "10.0.0.4",
    }
  
  tasks:

    - name: run traceroute to every other host
      raw: traceroute {{ item.value }} source Loopback0 probe 1 numeric
      when: item.key != inventory_hostname
      with_dict: loopbacks
      register: trace_result

#    - name: Debug registered variables
#      debug: var=trace_result
```
{% endraw %}

In this Playbook I use several useful Ansible features:

* [Variables defined in playbooks](https://docs.ansible.com/playbooks_variables.html#variables-defined-in-a-playbook)
* [Looping over hashes](https://docs.ansible.com/playbooks_loops.html#looping-over-hashes)
* [Conditionals](https://docs.ansible.com/playbooks_conditionals.html)
* [Registered variables](https://docs.ansible.com/playbooks_variables.html#registered-variables)

The end result of this task is that traceroute is run 12 times - one time from each of the hosts to each other host except for when source and destination are equal.

``` bash Running the playbook
$ ansible-playbook cisco-trace-run.yml

PLAY [Run traceroute commands] ************************************************

TASK: [run traceroute to every other host] ************************************
skipping: [R4] => (item={'key': 'R4', 'value': '10.0.0.4'})
ok: [R1] => (item={'key': 'R4', 'value': '10.0.0.4'})
skipping: [R1] => (item={'key': 'R1', 'value': '10.0.0.1'})
ok: [R3] => (item={'key': 'R4', 'value': '10.0.0.4'})
ok: [R4] => (item={'key': 'R1', 'value': '10.0.0.1'})
ok: [R1] => (item={'key': 'R2', 'value': '10.0.0.2'})
ok: [R3] => (item={'key': 'R1', 'value': '10.0.0.1'})
ok: [R1] => (item={'key': 'R3', 'value': '10.0.0.3'})
ok: [R3] => (item={'key': 'R2', 'value': '10.0.0.2'})
skipping: [R3] => (item={'key': 'R3', 'value': '10.0.0.3'})
ok: [R2] => (item={'key': 'R4', 'value': '10.0.0.4'})
ok: [R2] => (item={'key': 'R1', 'value': '10.0.0.1'})
skipping: [R2] => (item={'key': 'R2', 'value': '10.0.0.2'})
ok: [R4] => (item={'key': 'R2', 'value': '10.0.0.2'})
ok: [R2] => (item={'key': 'R3', 'value': '10.0.0.3'})
ok: [R4] => (item={'key': 'R3', 'value': '10.0.0.3'})

PLAY RECAP ********************************************************************
R1                         : ok=1    changed=0    unreachable=0    failed=0
R2                         : ok=1    changed=0    unreachable=0    failed=0
R3                         : ok=1    changed=0    unreachable=0    failed=0
R4                         : ok=1    changed=0    unreachable=0    failed=0

```

The above shows that all 12 tasks were completed successfully, meaning the command was executed and result was stored in a registered variable. To view the actual output of `traceroute` commands uncomment the two debug lines at the end of the playbook and rerun it.

***

Now that the goal of running commands on multiple devices in parallel is achieved, the next step would be to decide how to make use of the received output. In the next posts I will attempt to tackle the following problems:

* Parse textual output of traceroute command and extract transit IP addresses.
* Find a way to convert these transit IP addresses into hostnames without relying on DNS.
* Verify TDD scenarios against traceroute outputs and produce an intelligible result of this verification.

