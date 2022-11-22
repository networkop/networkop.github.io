+++
title = "Network Automation with CUE - Advanced workflows"
date = 2022-11-22T00:00:00Z
categories = ["howto"]
tags = ["automation", "cue", "ansible"]
summary = "Using CUE for advanced network automation workflows"
description = "Using CUE for advanced network automation workflows"
images = ["/img/cue-networking.png"]
+++

What I've covered in the [previous blogpost](/post/2022-11-cue-ansible/) about CUE and Ansible were isolated use cases, disconnected islands in the sea of network automation. The idea behind that was to simplify the introduction of CUE into existing network automation workflows. However, this does not mean CUE is limited to those use cases, in fact, CUE is most powerful when it's used end-to-end --- both to generate device configurations and to orchestrate interactions with external systems. In this post, I'm going to demonstrate how to use CUE for advanced network automation workflows involving fetching of information from an external device inventory management system, using it to build complex hierarchical configuration values and, finally, generating and pushing the intended configuration to remote network devices.

## CUE vs CUE scripting

CUE was designed to be simple, scalable and robust configuration language. This is why it includes type checking, schema and constraints validation as first-class constructs. There are some [design decisions](https://cuelang.org/docs/usecases/configuration/), like the lack of inheritance or value overrides, that may take new users by surprise, however over time it becomes clear that they make the configuration simpler and more readable. One of the most interesting features of CUE, though, is that it is hermetic. What that means is that all configuration values must come from local CUE files and cannot be dynamically fetched or injected into the evaluation process.

However, as we all know, in real life, configuration values may come from many different places. In network automation context, we often use IP address and infrastructure management systems to store device-specific data, often referring to these systems as a "source of truth". I won't focus on the fact that most often these systems are managed imperatively (point and click), making them a very poor choice for this task (how do you roll back?), but their dominance and popularity in our industry is undeniable. So how can we make CUE work in such environments?

CUE has an optional scipting layer, that is complimentary to the core functionality of a configuration language. CUE scripting (or [tooling]((https://cuelang.org/docs/usecases/configuration/#tooling))) layer works by evaluating files (identified by the `_tool.cue` suffix) that contain a set of tasks and executing them concurrently. These files are still written in CUE and can access the values defined in the rest of the CUE module, however CUE tasks _are_ allowed to make local and remote I/O calls and can be strung together to form some pretty complex workflows. As you may have guessed, this is what allows us to interact with external databases and remote network devices.

## Advanced Network Automation Workflow

This time we focus on the advanced automation workflow, that was described in the [CUE introduction post](/post/2022-10-cue-intro/).

![](/img/cue-advanced.png)

* a few words about the lab
* a few words about the GH repo https://github.com/networkop/cue-networking-II

## Pulling Configuration Data from External Systems

## Data Transformation

## Config Generation

## Config Push

## Outro

* Completely replace Ansible
* CUE vs Ansible performance and repo https://github.com/networkop/cue-networking-II
* YANG to come next

