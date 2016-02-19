---
layout: post
title: "Network Continuous Integration and Delivery"
date: 2016-02-19
comments: true
sharing: true
footer: true
categories: [network, automation, devops]
description: Application of CI/CD methodologies to traditional networks
---

In this series of posts I'll introduce the tools I've been using for continuous network development and how they can be used with  automation servers like Jenkins for network continuous integration and delivery.

<!--more-->

## CI/CD vs ITIL

How do you implement changes in your network? In today's world there's 95% chance that you have to write up an [RFC](abbr: Request For Change), submit it at least a week before the planned implementation date, go through at least one [CAB](abbr: Change Admission Board) meeting and only then, assuming it got approved, can you implement it. But the most important question is 'how do you test'? Do you simply content yourself with a few pings or do you make sure all main routes are in place? And how often do you get a call the next morning from a very nervous client asking you to 'please have a look at the network perfomance issues'?  

Software developers have solved most of the these problems for themselves. DevOps movement has brought forth ideas of Continuous Intergration and Delivery (CI/CD) to streamline the change process and 'embrace' the change rather than protect against it. But how applicable are those ideas to the networks of today? Can we simply rip and replace our CAB meetings with a Jenkins server and live happily ever after?  As always, things are getting difficult as you move down from Layer 7.

## Problem #1 - How to test

Ever since the dawn of networking, the only tools that engineers could use for testing were traceroutes and pings. It's not necessarily bad since, after all, networks are supposed to be a simple packet transports and shouldn't be endowed with application-layer knowledge. Note that I'm talking about traditional or, in SDN-era terms, 'underlay' networks. The biggest problem with network testability is not the lack of test tools but rather lack of automation. For every ping and every traceroute we had to login a device, carefully craft the command including source interface names, VRFs and other various options and then interpret the output.  
I have already explored the idea of automated network testing in my previous blog posts - [Building Network TDD framework][simple-tdd-build] and [Network TDD quickstart][tdd-quickstart]. I even got lucky enough to get invited to one of the [greatest networking podcasts][ipspace-tdd] hosted by Ivan Pepelnjak.  

## Problem #2 - Where to test

Another big problem is the lack of testable network software. We've only had IOU, vSRX and vEOS for the past 3-4 years and even now a lot of the real-world functionality remains unvirtualizable. However having those images is a lot better than not, even though some of them tend to crash and behave unreliably from time to time.

## Network CI

Here I've come to the actual gist of my post. I want to demonstrate the tools that I've built and how I use them to automate a lot of the repetitive tasks to prepare for network deployments and upgrades. This is what these tools can do:

* Create a replica of almost any real-world network topology inside a network emulation environment
* Apply configuration to all built devices
* Verify real-time connectivity between nodes
* Verify traffic flows under various failure conditions against pre-defined set rules
* Shutdown and delete the network topology

All these steps can be done automatically without making a single click in a GUI or entering a single command in a CLI. This is a sneak peak of what to expect later in the series:

{% youtube jiZs0969RWI %}

Please don't judge me too harshly, this is my first experience with screencasts.

## Coming up

In the following posts I'll show how to setup a continuous delivery environment with Jenkins and UNetLab, create test cases and work with configuration files in git version control system to enable automatic testing by Jenkins server. If that sounds interesting to you - stay tuned.


[simple-tdd-build]: http://networkop.github.io/blog/2015/06/15/simple-tdd-framework/
[tdd-quickstart]: http://networkop.github.io/blog/2015/07/17/tdd-quickstart/
[ipspace-tdd]: http://blog.ipspace.net/2015/11/test-driven-network-development-with.html

