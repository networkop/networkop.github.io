+++
title = "Building a Simple Network TDD Framework"
date = 2015-06-15T00:00:00Z
categories = ["automation"]
url = "/blog/2015/06/15/simple-tdd-framework/"
tags = ["network-TDD", "Ansible", "DevOps"]
summary = "In the following series of posts I will show how to build a simple Test-Driven Development framework for Cisco devices. This framework will allow a network engineer to define traffic patterns in a human-readable format and automatically check if those assumption hold. It will be built as a series of Ansible modules and playbooks. The idea is to show an example of how programming can be used by network engineers even now, before all devices acquire their own APIs as well as introduce some well-known programming paradigms and best practices to network engineers thereby making a small step towards networking nirvana a.k.a. SDN. The reader is assumed to have only a basic networking, linux and python programming skills"
draft = false
+++

# Before we begin (optional section)

Before we go on, I'd like to put a little disclaimer about terms being used in this post. [TDD](abbr:Test-Driven Development), and its counterpart [BDD](abbr:Behaviour-Driven Development),
are well-known and accepted practices in development world. Both rely on the assumption that tests will be written
before the code and will _drive_ code development. This seemingly unnatural approach became extremely popular with the advent of [Agile][agile-manifesto] and is still being widely used, specifically in web development. What I will be developing will look more like a BDD rather than TDD, since it will be testing overall system behaviour rather than small self-contained portions of configuration. However, I still prefer to use the term TDD, firstly, because it's easier to understand for people from a non-dev background, secondly, because it's very hard/impossible to test small portions of network configuration (like routing protocol configuration), and lastly, since my tests will rely heavily on traceroutes, TDD may as well stand for Traceroute-Driven Development. 

# How will it work?

Traffic flow patterns, a.k.a. traffic paths is one bit of information that even higher-level management is able to comprehend. With a nice network diagram it is easy to show how low-latency traffic from Network_A will flow to Network_B through private VPN link on Router_X, while an internet-bound traffic will traverse a low-cost, high-latency Internet link on Router_Y. The TDD framework will use the same idea but in a text format

```
1. Testing of Primary Link
  1. From Router1 to Router2 via Router4, Router5
  2. From Router2 to Router1 via Router5, Router4
2. Testing of Backup Link
  1. From Router4 to Router1 via Router3
  2. From Router4 to Router2 via Router7
```

This format can be understood by both network engineers and their clients and can be used as a basis for network acceptance and verification testing. At the same time it follows a strictly defined format which can be parsed, processed and actioned by a program. I'll show how to write an Ansible module that parses this text, runs a traceroute and checks if the test was successful.  
These tests can also be used during regression testing of the network each time network configuration changes. This kind of verification offers a much more reliable result compared to visual examination of traceroute results and routing tables.

# Step-by-step procedure  

This is how I see the whole development process now (before I started). Some section may get added/removed in the process. I'll try to write at least one post a week aiming to complete the series in under one month.

1. [Development environment setup][dev-env-setup-link]
2. [Getting started with Ansible for Cisco IOS][ansible-intro-link]
3. [Developing Ansible library to gather facts from Cisco devices][ansible-parse-link]
4. [Developing Ansible library to verify test scenarios][ansible-tdd-link]

A [quickstart guide][quickstart-link] for those interested to see the final product in action.

[agile-manifesto]: http://agilemanifesto.org/
[ansible-website]: http://docs.ansible.com/list_of_files_modules.html
[dev-env-setup-link]: /blog/2015/06/17/dev-env-setup/
[ansible-intro-link]: /blog/2015/06/24/ansible-intro/
[ansible-parse-link]: /blog/2015/07/03/parser-modules/
[ansible-tdd-link]: /blog/2015/07/10/test-verification/
[quickstart-link]: /blog/2015/07/17/tdd-quickstart/
 
