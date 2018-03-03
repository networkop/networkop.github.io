+++
title = "Development Environment Setup"
date = 2015-06-17T00:00:00Z
categories = ["automation"]
url = "/blog/2015/06/17/dev-env-setup/"
tags = ["network-TDD", "Ansible", "DevOps"]
summary = "Setting up development and test environments"
draft = false
+++

Before we proceed with TDD framework build it is important to have the development environment setup. In our case it will consist of two major components:

* Network Simulation Environment
* Ansible Development Environment

To simplify things I will run both of these environments on the same Virtual Machine. For network simulation I will use [UnetLab](http://www.unetlab.com/), a wonderful product developed by Andrea Dainese. Currently, UnetLab is distributed as an OVA package and is available for free download on [the website](http://www.unetlab.com/download/). To simulate network devices I will run [IOU](abbr:IOS on Unix) which will be interconnected to form a simple network. Finally, I will show how to setup development environment with Ansible, git and Python.

# UnetLab setup
UnetLab is a network simulation environment very similar to GNS3. The biggest advantage for me, personally, is that it runs as a single entity and doesn't require a separate front-end like GNS3. That being said, the only requirement for this project is for the test network to have remote connectivity to a machine running Ansible, so having UnetLab specifically is not required and any network simulator would do, including a real (non-virtual) lab. One of the side effects of choosing UnetLab is that all development will have to be done on Ubuntu which is the OS pre-installed in the OVA.  
Here are the steps required to get the network environment setup:

1. [Download](http://www.unetlab.com/download/) and import OVA file into the hypervisor of your choice.  
2. Download and [import](http://www.unetlab.com/2014/11/adding-cisco-iouiol-images/) Cisco L3 IOU file. 
3. Create a simple 4-device network ([example](http://www.unetlab.com/2014/11/create-the-first-lab/)) and [connect it to the network of host machine](http://www.unetlab.com/2014/11/using-cloud-devices/).
4. [Configure](http://www.unetlab.com/2015/03/url-telnet-ssh-vnc-integration-on-windows/) your favourite terminal program to work with UnetLab's web interface

This is the topology I will be using for testing:

![Test topology](/img/lab-topo.png)

Each device will have a Loopback interface in `10.0.0.0/24` subnet which I will statically point to `interface Eth0/2` of R1 on the host machine. Here's the example of R1's configuration:

```
! Configure hostname, domain and RSA key to enable SSH
hostname R1
ip domain name tdd.lab
crypto key generate rsa modulus 1024
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
``` 

All other devices will have similar configuration with the end goal of having connectivity between any pair of Loopback interfaces.

In order to to have connectivity to devices from a host machine we need to add a static route for `10.0.0.0/24` network:

```bash
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

# Dev environment setup

Ansible is one of the most popular automation and orchestration tools in IT industry. Part of its popularity is due to the "clientless" architecture where
the only requirement to a managed system is to have ssh access and Python execution environment. The latter pretty much rules out the biggest part of common
networking infrastructure. However it is still possible to use Ansible in a "raw" mode and write modules of our own. That's exactly what we're gonna do in this exercise. 
Due to the fact that Ansible is written in Python, it has better support for modules written in the same language, therefore all modules will be written in Python.  
One important tool every developer uses is version control. It allows to track changes made to the code and enables collaboration between multiple 
people working on the same project. For beginners it always makes sense to stick to the most popular tools, that's why I'll be using git for version control and store all my code on Github.  
    
This is what's needed to setup the development environment:

``` bash
$ sudo apt-get update && sudo apt-get install python git-core
```  

``` bash
$ git config --global user.name "Network-oriented programming"
$ git config --global user.email "networkop@example.com"
```  

``` bash 
$ sudo apt-get install software-properties-common
$ sudo apt-add-repository ppa:ansible/ansible
$ sudo apt-get update
$ sudo apt-get install ansible
```  

``` bash
$ sudo echo "R1 ansible_ssh_host=10.0.0.1" >> /etc/ansible/hosts
$ printf "[defaults]\nhost_key_checking=False\n" >> ansible.cfg
$ ansible R1 -u cisco --ask-pass -m "raw" -a "show version | include IOS"
SSH password:
R3 | success | rc=0 >>
Cisco IOS Software, Linux Software (I86BI_LINUX-ADVENTERPRISEK9-M), Version 15.4(1)T, DEVELOPMENT TEST SOFTWARE
Connection to 10.0.0.1 closed by remote host.
```

The above script first populates Ansible `inventory` file with an ip address of R1, then disables ssh key checking,
 and finally runs an `ad-hoc` command `show version | include IOS` which should prompt for a password and return a result of command execution on R1.
 I will explain about inventory and configuration files in a bit more detail in the next post. At this stage all what's required is a meaningful response from a Cisco router.  
 
Next step is to create a free Github account and setup a new repository. For my blog I will be using `networkop` as a Github username and `simple-cisco-tdd` as a repository name. Once respository is created, Github will provide instructions to setup repository on a local machine which will be done in the next step.  

``` bash 
$ mkdir ~/tdd_ansible && cd ~/tdd_ansible
$ echo "simple-cisco-tdd" >> README.md
$ git init
$ git add README.md
$ git commit -m "first commit"
$ git remote add origin https://github.com/networkop/simple-cisco-tdd.git
$ git push -u origin master
Username for https://github.com: networkop
Password for https://networkop@github.com:
Counting objects: 3, done.
Writing objects: 100% (3/3), 206 bytes | 0 bytes/s, done.
Total 3 (delta 0), reused 0 (delta 0)
To https://github.com/networkop/simple-cisco-tdd.git
 * [new branch]      master -> master
Branch master set up to track remote branch master from origin.
```
 
The above result indicates that `README.md` file has been pushed to Github successfully. Needless to say that all pushed local files can be also viewed from Github's web page.  


 * * *

This completes the initial environment setup. I highly recommend at this stage, hypervisor permitting, to take a snapshot of a current state of a virtual machine to avoid having to rebuild it every time something goes pear-shaped.
In the next post I will show how to setup Ansible to work with Cisco devices.