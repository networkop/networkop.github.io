---
layout: post
title: "Network configuration automation"
date: 2015-08-07
comments: true
sharing: true
footer: true
categories: [network, automation]
description: Automating Network Configuration 
---

This post will give a brief overview of network configuration automation, describe its challenges and benefits and will set off a series of posts showing how to automate a configuration of a typical enterprise network. 

<!--more-->

## Automating Network Configuration

Automation and programmability steadily make their way into a networking domain. The idea was born in application development world where makefiles served a role of automated installation scripts. It later spread into application testing and deployment so now hardly anyone does these two things by hand. Next in line were the operating systems largely thanks to the raising popularity of [PaaS](abbr:Platform-as-a-Service) solutions. Until recently network configuration has been the prerogative of us, network engineers. However it's hard maintain this mindset when everything surrounding the network industry changes so rapidly. In fact, one of the reasons why idea of [SDN](abbr:Software-Defined Network) has become so popular was because it allowed faster deployment and configuration changes in a much more scalable manner. As usual, one of the first adopters of these new tools and paradigms were [ISPs](abbr:Internet Service Providers). This comes as no surprise since one of the major benefits automation gives is ability to manage large-scale systems. Another area where automation has been very successful is [DC](abbr:Data Centre) networking. Now what makes these two networking domains so suitable for automation? One of the main requirements for DC and ISP network is ability to scale to enormous proportions without any detrimental effect to services provided to end clients. And amongst other things making it possible is a use of **standard repeatable design patterns**. That is exactly where automation fits in.

1. Take a small part of the network (a DC pod or an ISP region)
2. Identify a pattern (a spine/route-reflector with two leafs/RR-clients)
3. Abstract it by taking out all variable parts (ip addresses, BGP AS numbers) until it looks exactly the same as in any other region/POD
4. Put this abstract pattern inside an automation system
5. All the information extracted during step #3 goes into environmental variables

Now all what needs to be done to configure another POD/region is simply create a new set of environmental variables (ip addresses, hostnames) and run them through the automation system.  
However remember that network configuration automation will not substitute a good design. In fact, it's a standards-based, scalable design that makes automation possible.

## Enterprise network automation

Everyone who has ever dealt with enterprise networks knows that repeatable standard design patterns have nothing to do with a typical enterprise network. In best case scenario there is a standard for IGP, EGP, STP flavour and a single set of WAN providers. Most of the times, however, enterprise network is a tight knot of semi-permanent solutions mixed with a number of ad-hoc workarounds resulted from fault troubleshooting. So is there a point in even *trying* to bring order into this mess? According to chaos theory, order is everywhere even though it is sometimes concealed behind a visual chaos. We only need to look closer to see recognisable patterns emerging:

* All network devices in the same administrative domain share some management configuration (syslog, snmp, AAA)
* Most of the access switches have similar switchport configuration (data/voice, management, video)
* QoS configuration including ACLs and class-maps normally remains the same on all devices

Cumulatively, these three configuration parts may constitute around 70% of total device configuration. And there are not too many things that need to be done do automate them. QoS configuration will only differ in interface reference bandwidth, switchport configuration will differ in VLAN number and management template will only have different source interface IP addresses for management protocols.  
Ok, so what happens to the remaining 30% you would ask. The answer is nothing. Automation is not all-or-nothing game. We can have big chunks of configuration stored as a collection of static text and not worry about it. It will even be possible to quantify the scaling property of a design as a ratio between automated and total (automated + non-standard) device configuration. Something like a test coverage in application development world. 

## Automating a typical enterprise network

In the upcoming series of posts I will show how to:

- Pull legacy network configuration into automation system
- Completely automate the build of a new branch office

I will use a cut-down version of a typical enterprise network I've used in my [previous posts][tdd-quickstart-link]. I'll once again use Ansible as automation system and specifically its' `template` module which uses [Jinja2][jinja-link] templating language.

[tdd-quickstart-link]: http://networkop.github.io/blog/2015/07/17/tdd-quickstart/ 
[jinja-link]: http://jinja.pocoo.org/docs/dev/


