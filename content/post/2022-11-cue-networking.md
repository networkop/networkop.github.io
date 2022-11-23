+++
title = "Network Automation with CUE - Advanced workflows"
date = 2022-11-22T00:00:00Z
categories = ["howto"]
tags = ["automation", "cue", "ansible"]
summary = "Using CUE for advanced network automation workflows"
description = "Using CUE for advanced network automation workflows"
images = ["/img/cue-networking.png"]
+++

What I've covered in the [previous blogpost](/post/2022-11-cue-ansible/) about CUE and Ansible were isolated use cases, disconnected islands in the sea of network automation. The idea behind that was to simplify the introduction of CUE into existing network automation workflows. However, this does not mean CUE is limited to those use cases and, in fact, CUE is most powerful when it's used end-to-end --- both to generate device configurations and to orchestrate interactions with external systems. In this post, I'm going to demonstrate how to use CUE for advanced network automation workflows involving fetching of information from an external device inventory management system, using it to build complex hierarchical configuration values and, finally, generating and pushing the intended configuration to remote network devices.

## CUE vs CUE scripting

CUE was designed to be simple, scalable and robust configuration language. This is why it includes type checking, schema and constraints validation as first-class constructs. There are some [design decisions](https://cuelang.org/docs/usecases/configuration/), like the lack of inheritance or value overrides, that may take new users by surprise, however over time it becomes clear that they make the language simpler and more readable. One of the most interesting features of CUE, though, is that all code is hermetic. What that means is all configuration values must come from local CUE files and cannot be dynamically fetched or injected into the evaluation process, so that no matter how many times or in which environment you run your CUE code, it always produces the same result.

However, as we all know, in real life, configuration values may come from many different places. In network automation context, we often use IP address and infrastructure management systems (IPAM/DCIM) to store device-specific data, often referring to these systems as a "source of truth". I won't focus on the fact that most often these systems are managed imperatively (point and click), making them a very poor choice for this task (how do you roll back?), but their dominance and popularity in our industry is undeniable. So how can we make CUE work in such environments?

CUE has an optional scipting layer, that is complimentary to the core functionality of a configuration language. CUE scripting (or [tooling]((https://cuelang.org/docs/usecases/configuration/#tooling))) layer works by evaluating files (identified by the `_tool.cue` suffix) that contain a set of tasks and executing them concurrently. These files are still written in CUE and can access the values defined in the rest of the CUE module, however CUE tasks _are_ allowed to make local and remote I/O calls and can be strung together to form some pretty complex workflows (). As you may have guessed, this is what allows us to interact with external databases and remote network devices.

## Advanced Network Automation Workflow

Let's revisit the advanced network automation workflow, that was described in the [CUE introduction post](/post/2022-10-cue-intro/). What makes it different from the intermediate workflow is that  host variables are sourced from multiple different places. In most common workflows, these places can be described as:

1. Local static variables, defined in host and group variables.
2. Variables injected by the environment, which often include sensitive information like secrets and passwords.
3. Externally-sourced data, fetched and evaluated during runtime.

Once this data is collected and evaluated, the remainder of the process looks very similar to what I've described in the [previous blog post](/post/2022-11-cue-ansible/), i.e. this data is modified and expanded to generate a complete per-device set of variables which are then used to produce the final device configuration. The top part of the following diagrams is a visual representation of this workflow.

![](/img/cue-advanced.png)

The bottom part shows how the same data sources are consumed in the equivalent CUE workflow. External data from IPAM/DCIM systems is ingested using CUE scripting layer and saved next to the rest of the CUE values. CUE runtime now takes the latest snapshot of external data, combines it with other local CUE values and generates per-device configurations. At this point we can either apply the device configuration as is, or combine it with a Jinja template to generate a semi-structured text before sending it to the remote device. 

In the rest of this blog post I will walk you through the above CUE workflow, while configuring an unnumbered BGP session between Arista cEOS and NVIDIA Cumulus Linux connected back-to-back. The goal is to show an example of how the data flows from its source all the way to its ultimate destination and how CUE can be used at every step of the way.

> All code from this blog post can be found in the [cue-networking-II](https://github.com/networkop/cue-networking-II) GH repository

## Pulling Configuration Data from External Systems

For an example of an external IPAM/DCIM system I'll be using the public demo instance of [Nautobot](https://github.com/nautobot/nautobot) located at [demo.nautbot.com](https://demo.nautobot.com/).

```json
```

## Data Transformation

## Config Generation

## Config Push

## Outro

* Completely replace Ansible
* CUE vs Ansible performance and repo https://github.com/networkop/cue-networking-II
* YANG to come next

