---
layout: post
title: "Development environment setup"
date: 2015-06-17
comments: true
sharing: true
footer: true
categories: [ansible, unetlab]
keywords: tdd, ansible, unetlab, setup, development
description: Setting up of development and testing environments
---
Before we proceed with TDD framework build it is important to have the development environment setup. In our case it will consist of two major components:

* Network Simulation Environment
* Ansible Development Environment

To simplify things I will run both of these environments on the same Virtual Machine. For network simulation I will use [UnetLab][unetlab-link], a wonderful product developed by Andrea Dainese. Currently, UnetLab is distributed as an OVA package and is available for free download [the website](http://www.unetlab.com/download/). To simulate network devices I will run [IOU](abbr:IOS on Unix) which will be interconnected to form a simple network. Finally, I will show how to setup development environment with Ansible, git and Python.
<!--more-->

## UnetLab setup
UnetLab is a network simulation environment very similar to GNS3. The biggest advantage for me, personally, is that it runs as a single entity and doesn't require a separate front-end like GNS3. That being said, the only requirement for this project is for the test network to have remote connectivity to a machine running Ansible, so having UnetLab specifically is not required and any network simulator would do, including a real (non-virtual) lab. One of the side effects of choosing UnetLab is that all development will have to be done on Ubuntu which is the OS pre-installed in the OVA.  
Here are the steps required to get the network environment setup:

1. [Download](http://www.unetlab.com/download/) and import OVA file into the hypervisor of your choice.  
2. Download and [import](http://www.unetlab.com/2014/11/adding-cisco-iouiol-images/) Cisco L3 IOU file. 
3. Create a simple 4-device network ([example](http://www.unetlab.com/2014/11/create-the-first-lab/)) and [connect it to the network of host machine](http://www.unetlab.com/2014/11/using-cloud-devices/).
4. [Configure](http://www.unetlab.com/2015/03/url-telnet-ssh-vnc-integration-on-windows/) your favourite terminal program to work with UnetLab's web interface

This is the topology I will be using for testing:
{% img center /images/lab-topo.png 'Test Topology'%}

Each device will have a Loopback interface in `10.0.0.0/24` subnet which I will statically point to `interface Eth0/2` of R1 on the host machine. Here's the example of R1's configuration:

~~~
! Configure hostname and domain to enable SSH
hostname R1
ip domain name tdd.lab
! Point AAA to local database
aaa new-model
aaa authentication login default local
aaa authorization exec default local
username cisco privilege 15 secret cisco
! Enable remote ssh connections
line vty 0 4
 transport input ssh
! Configure interfaces
interface Loopback0
 ip address 10.0.0.1 255.255.255.255
!
interface Ethernet0/0
 ip address 12.12.12.1 255.255.255.0
!
interface Ethernet0/1
 ip address 14.14.14.1 255.255.255.0
!
interface Ethernet0/2
 description connection to host machine
 ip address 192.168.247.25 255.255.255.0
! Enable dynamic routing
router eigrp 100
 network 0.0.0.0
!
end
write 
~~~

All other devices will have similar configuration with the end goal of having connectivity between any pair of Loopback interfaces.

In order to to have connectivity to devices from a host machine we need to add a static route for `10.0.0.0/24` network:

``` bash
$ route add -net 10.0.0.0 netmask 255.255.255.0 gw 192.168.247.25
``` 

At this point host machine should be able to ping each one of those Loopbacks:

``` bash
$ for i in {1..4}; do ping -c 1 10.0.0.$i; done | grep packets
1 packets transmitted, 1 received, 0% packet loss, time 0ms
1 packets transmitted, 1 received, 0% packet loss, time 0ms
1 packets transmitted, 1 received, 0% packet loss, time 0ms
1 packets transmitted, 1 received, 0% packet loss, time 0ms
```

## Dev environment setup
Ansible is written in Python and therefore has better support for modules written in the same language. 

1. Install Python and git packages
2. Install Ansible

``` bash
$ sudo apt-get install software-properties-common
$ sudo apt-add-repository ppa:ansible/ansible
$ sudo apt-get update
$ sudo apt-get install ansible
``` 

3. Test connectivity from Ansible to a test network environment
4. Create a project directory and initialise git repo 

This completes the initial environment setup. I highly recommend at this stage, hypervisor permitting, to take a snapshot of a current state of a virtual machine to avoid having to rebuild it every time something goes pear-shaped.

[unetlab-link]: http://www.unetlab.com/