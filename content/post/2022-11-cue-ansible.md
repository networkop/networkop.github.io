+++
title = "Network Automation with CUE - Augmenting Ansible workflows"
date = 2022-11-01T00:00:00Z
categories = ["howto"]
tags = ["automation", "cue", "ansible"]
summary = "Augmenting Ansible workflows with CUE"
description = "Augmenting Ansible workflows with CUE"
images = ["/img/cue-networking.png"]
+++

Hardly any conversation about network automation that happens these days can avoid the topic of automation frameworks. Amongst the few that are still actively developed, Ansible is by far the most popular choice. Ansible's ecosystem has been growing rapidly in the last few years, with modules being contributed by both internal (Redhat) developers and open-source community. Having the backing of one of the largest open-source first companies has allowed Ansible to spread into all areas of infrastracture -- from server automation to cloud provisioning. By following  the principle of eating your own dogfood, Redhat used Ansible in a lot of its own open-source projects, which made it even more popular in the masses. Another important factor in Ansible's success was the ease of understanding. When it comes to network automation, Ansible's stateless and agentless architecture very closely follows a standard network operation experience -- SSH in, enter commands line-by-line, catch any errors, save and disconnect. But just like any popular software in the world, Ansible is not without its own challenges, and in this post we'll take a look at what they are and how we can use CUE to augment existing Ansible workflows to overcome some of these limitations.

## Ansible Automation Workflow

Im

![](/img/cue-ansible.png)

While [other frameworks](https://docs.saltproject.io/en/latest/topics/network_automation/index.html) may offer better scalability or speed, these are very often not the [deciding factors](https://twitter.com/carmatrocity/status/1587751053772181505) and Ansible is continuously improving and closing the gap on its competitors. However, some architectural decisions and design invariants are not subject to change. 

## Input Data Validation

## Data Transformatino

## Config Generation


Next up: orchestrating API interactions with remote devices



