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
Before we proceed with TDD framework build it is important to have the development environment setup. In our case the it will consist of two major components:

* Network Simulation Environment
* Ansible Development Envrionment

To simplify things I will run both of these environments on the same Virtuan Machine. For network simulation I will use [UnetLab][unetlab-link], a wonderful product developed by Andrea Dainese. Currently, UnetLab is distributed as an OVA package available for free download on it's website. To simulate network devices I will run [IOU](abbr:IOS on Unix) which will be interconnected to form a simple network. Finally, I will show how to setup development environment with Ansible, git and python.
<!--more-->

## UnetLab setup
UnetLab is a network simulation environment very similar to GNS3. The biggest advantage for me, personally, is that runs as a single entity and doesn't require a separate front-end like GNS3. That being said, the only requirement for this project is for the test network to have remote connectivity to a machine running Ansible, so having UnetLab specifically is not required and any network simulator would do, including a real (non-virtual) lab. One of the side effects of chosing UnetLab is that all development will have to be done on Ubuntu which is the OS pre-installed in the OVA.  
Here are the steps required to get the network environment setup:

1. [Download](http://www.unetlab.com/download/) and import OVA file into the hypervisor of your choice.  
2. Download and [import](http://www.unetlab.com/2014/11/adding-cisco-iouiol-images/) Cisco L3 IOU file. 
3. Create a simple 4-device network and connect it to the network of host machine.

## Dev environment setup
Ansible is written in Python and therefore has better support for modules written in the same language. 

1. Install Python and git packages
2. Install Ansible

{% codeblock lang:bash %}
$ sudo apt-get install software-properties-common
$ sudo apt-add-repository ppa:ansible/ansible
$ sudo apt-get update
$ sudo apt-get install ansible
{% endcodeblock  %}

3. Test connectivity from Ansible to a test network environment
4. Create a project directory and initialise git repo 

This completes the initial environment setup. I highly recommend at this stage, hypervisor permitting, to take a snapshot of a current state of a virtual machine to avoid having to rebuild it every time something goes pear-shaped.

[unetlab-link]: http://www.unetlab.com/