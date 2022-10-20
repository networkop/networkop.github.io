+++
title = "Network Automation with CUE - Introduction"
date = 2022-05-25T00:00:00Z
categories = ["howto"]
tags = ["automation", "cue", "ansible"]
summary = "Introducing CUE for network automation"
description = "Introducing CUE for network automation"
images = ["/img/cue-networking.svg"]
+++

In the past few years, network automation has made its way from a new and fancy way of configuring devices to a well-recognized industry practice. What started as a series of "hello world" examples has evolved into an entire discipline with books, professional certifications and dedicated career paths. It's safe to say that today, most large-scale networks (>100 devices) are at least deployed (day 0) and sometimes managed (day 1+) using an automated workflow. However, at the heart of these workflows are the same exact principles and tools that we used in the early days. Of course, these tools have evolved and matured but they still have the same scope and limitations. Very often, these limitations are only becoming obvious once we hit a certain scale or complexity, which makes it even more difficult to replace them. The easiest option is to accept and work around them, forcing the square peg down the round hole. In this post I'd like to propose an alternative approach to what I'd consider "traditional" network automation practices by shifting the focus from "driving the CLI" to management of data. 

## Evolution of Network Configuration Management

In order to understand why data management is important, we need to have a closer look at what constitutes a typical network automation workflow. The most basic process starts by combining a device data model, represented by an free-form data structure (e.g. YAML), with a text template (e.g. Jinja) to produce the desired device configuration. This configuration is then passed to a function that implements the underlying transport protocol (e.g. netmiko), which applies the desired changes. Some of these steps can be abstracted away by automation frameworks (e.g. Ansible) but largely the process still looks the same under the hood. This is what you can see on the left-hand side of the following diagram:

![](/img/cue-evolution.png)

While the basic workflow may work well for the initial network configuration, it is rarely suitable for ongoing operations due to its inherent verbosity. The natural reaction to that is to create another layer of abstraction that hides common design conventions, configuration defaults and computable attributes behind a terse high-level data model, as depicted by the "intermediate workflow" in the above diagram. This high-level data model simplifies the end-user experience of interacting with the automation workflow, but it comes at the expense of additional complexity hidden in the high-to-low level translation logic. 

Finally, some physical networks have decided to replicate the self-service cloud experience by allowing some part of their state to be managed dynamically. One simple example is to allow the compute team to manage the VLAN assignment on the downlink network ports. This meant that a single, flat-text data structure is no longer enough to store the high-level configuration intent, and we split it across multiple (preferably) non-overlapping sources of truth, visualized by the "advanced workflow" in the above diagram.

If you look at the above diagram, you might notice one theme that emerges and evolves together with the complexity of the automation workflows. It is the ever-increasing focus on data. Thanks to the growing number of templates, we started caring less about individual vendor configuration dialects and more about how to source, structure and combine input configuration values. I would argue that these input values have become the new API, since the old APIs ("industry-standard" CLI) were not built for automation and eventually got abstracted away by libraries like scrapli or netmiko and a ton of (mostly) Jinja templates.

The same argument can be applied to the YANG-based APIs, that _were_ design for machine-to-machine communication and are slowly but steadly getting more traction. Those APIs are often abstracted away by software platforms, like OpenDaylight or Tail-f NSO, or libraries, like [ygot](https://github.com/openconfig/ygot), and the operational tasks are, once again, reduced to the management of input data.


## Automation Tools

I want to frame the discussion of automation tools in the context of the [configuration complexity clock](http://mikehadlow.blogspot.com/2012/05/configuration-complexity-clock.html). The main premise of this theory is that the process of finding the right level of abstraction for configuration values is cyclical. Here's my free interpretation of the original story, translated into the network configuration management reality:

* **00:00**: We need to configure a network but don't have time for proper planning, so we have all configurable values hard-coded in flat-text configuration files and simply push them down to network devices.
* **03:00**: We realise that some parts of the network need to change, so we extract some of the hard-coded values, simplify them and make them configurable.
* **06:00**: The size of the configurable values continues to grow and we start building guardrails to prevent typical configuration mistakes and guarantee value uniqueness across the environment. We create a schema to validate input data and may even expose it via a GUI.
* **09:00**: At some point the guard rails, schemas and policy engines start being a hurdle and we decide to consolidate all of them in a single framework, driven by its own DSL. Quickly realising that the framework can not meet all our requirements, we start extending it with custom code.
* **12:00**: Now we have all our policies embedded in custom framework extensions and values hard-coded in the DSL, the network management process looks not much different from where we started. 

Looking outside of networking, at a wider infrastructure space, we can see similar trends playing out :


* Application configuration management went from static files to automation frameworks (Chef, Puppet) and finally settled on container images with static files mounted over volumes.  
* Cloud infrastracture management went from CLI-driven API calls to DSL frameworks (Terraform), back to general purpose programming (CDK, Pulumi).  

Coming back to network configuration management, we seem to see the industry settled on two extremes. I'll be very blunt:

  
* Everything is done with Ansible.  
* Everything is done with Python.  

The author of the configuration complexity clock article cautions us against rushing into DSL (especially from rolling your own DSL) and also suggests that at a low-enough scale simpler solutions may be the best option. I would agree with him. If you think that you get enough out of your current automation solution, you don't feel like you're swimming against the tide all the time and you're confident that when you move on the next person will be able to pick up and continue your work and without re-write everything from scratch, then you don't need to change. However, you should always remember that you could do better. You could create a solution that is faster, more robust to failures and easier to understand and extended. This is why I want to show an alternative 

## Introducing CUE

Compare and contrast infrastructure management before (logging into a box/server, changing the config, restarting the service) and today (send an API call and poll for status updates)

CUE was built to manage configuration data., which, as we've seen above, is one of the most critical parts of network automation workflows.

The two biggest selling points:

* Static typing of all data.
* Powerful data templating and generation capabilities.

---

My first blogposts about network automation date back to 2015. Back then I was talking about how to use Ansible for network configuration templating and how to hack Ansible to implement custom functionality via modules. In the 7 years that have passed, Ansible has gained a lot of popularity and is now considered one of the standard tools in many network automation workflows. At the same time, we had seen a number of proprietary network automation solutions, all fighting for the same piece of the pie with variable rate of success. 