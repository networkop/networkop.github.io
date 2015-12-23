---
layout: post
title: "REST API for Network Engineers"
date: 2015-12-24
comments: true
sharing: true
footer: true
categories: [network, automation, rest]
description: Introduction into REST API to configure network devices
---

This is the first, introductory, post in a series dedicated to REST APIs for Network Engineers. In this post we'll learn what REST API is, what are the most common tools and ways to consume it. Later in the series I'll show how to build a REST client to control [UnetLab][unl], a very popular network emulation environment.

<!--more-->

## Management interface evolution

Since the early dawn of networking devices have been configured via [VTY](abbr:Virtual Terminal User Interface)s. The transport has evolved from telnet to ssh but the underlying rule still maintained that network is configured manually, device-by-device by a human administrator.  
It's obvious that this approach does not scale and is prone to human error.   
The first attempt to tackle these issues have been made in 1988 with the introduction of SNMP. The basic idea was to monitor and manage network devices using a strictly-defined data structures called [MIB](abbr:Management Information Base)s. Vendor's implementation of this idea was far from stellar and SNMP ended up being used mainly for basic monitoring tasks.  
The idea of programmatic management of network devices later resulted in the creation of NETCONF protocol. This protocol is not widely used due to limited vendor support, however things may improve as the [YANG](abbr:Yet Another Next Generation)-based network configuration gain greater adoption.  
Finally, with the advent of SDN, REST has become a new de-facto standard for network provisioning. It is supported by most of the latest products of all the major vendors.

##  REpresentational State Transfer overview
Technically speaking, REST is not a protocol but a [software architectural style][rest-wiki]. To put it in simple words, it describes **a way** to exchange information rather than the structure of that information. Think of it as another transport (like telnet or ssh for VTY) with payload of any format. This rather *weak* definition opens up huge opportunities for potential use cases:

1. The most basic use case is a Web application with client retrieving and updating information on a server. A good example in networking world would be the native interfaces of Cisco ACI or VMWare NSX. Each time you need to create an object (a network or a tenant), your client needs to send a RESTful request to a server.

2. The more advanced use case is for communication between distributed software components over a network environment. This is how all management and control plane communications are designed inside OpenStack. 

## REST under the hood
REST is an API that allows client to perform read/write operations on data stored on the server. REST uses HTTP to perform a set of actions commonly known as **CRUD**:

* Create
* Read
* Update
* Delete

Assuming we want to manipulate a 'device' object on a server we can send a `HTTP GET` request to `/api/devices` and get a response with a payload containing a full list of known devices.  
If we want to add a new device, we need to construct a payload with device attributes (e.g. IP address, Hostname) and send it attached to a  `HTTP POST` request.  
To update a device we need to send the full updated payload with `HTTP PUT` method and, finally, `HTTP DELETE` without any payload deletes the device.

{% img centre /images/rest-crud.png Basic REST actions %} 

Note that both Update and Delete refer to a specific number in url `/api/devices/{ID}`; that ID is a unique identifier that server assigns to every new object.  
One of the most important properties of all RESTful interfaces is their stateless nature. That means that no cookie or session information should be stored on the server. Every request is treated independently from every other request. The implication here is that all state needs to be maintained on the client and information needs to be cachable in order to improve interface responsiveness. It's worth noting that an API can still be considered RESTful even if a server *does* store a session cookie, however all requests must still be treated independently. The last point means there's no *configuration modes* like we've seen in traditional CLIs where all commands applied in "interface configuration mode" will be applied to that specific interface. With RESTful API each request from a client must reference a full path to an object including its unique identifier within the system.

## Before you *REST*
Before you start using REST you need to know a few things about your managed device:

1. Protocol, IP address and port (e.g. https://sdn-controller.org:8181)
2. Base URL - often times used to encode API version (e.g. /api in the figure above) 
3. Authentication information - traditional username and password to authenticate a user
4. REST API documentation - a list of all possible commands and their descriptions (similar to CLI command reference).

## Using REST
A few most common ways to consume REST API are:

1. cURL - Linux command-line tool. Very simple to get started but too cumbersome for routine operations
2. Browser plugins - Postman, RESTClient are amongst the most popular ones.
3. [SDK](abbr:Software Development Kit) - an equivalent of REST API written in any particular programming language

## UNetLab REST SDK
In the upcoming posts I'll show how to develop a REST SDK to control UnetLab. My final goal would be to be able to create an arbitrary network topology with predefined configuration. The whole series will be broken up into several posts going over:

1. UnetLab SDK development environment setup. In this post I'll show how to setup PyCharm to work with UNL running in a hypervisor on a Windows machine.
2. First steps with REST API for UNetLab. In this post I'll show how to work with HTTP and perform basic operations like login/logoff and object creation in UNL.
3. Advanced actions with UNetLab SDK. The final post will demonstrate how to push configuration to devices inside UNL. To wrap up I'll write a sample app to spin up and provision a two-node topology without making a single GUI click.


[unl]: http://www.unetlab.com/
[rest-wiki]: https://en.wikipedia.org/wiki/Representational_state_transfer
