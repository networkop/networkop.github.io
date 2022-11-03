+++
title = "Network Automation with CUE - Augmenting Ansible workflows"
date = 2022-11-01T00:00:00Z
categories = ["howto"]
tags = ["automation", "cue", "ansible"]
summary = "Augmenting Ansible workflows with CUE"
description = "Augmenting Ansible workflows with CUE"
images = ["/img/cue-networking.png"]
+++

Hardly any conversation about network automation that happens these days can avoid the topic of automation frameworks. Amongst the few that are still actively developed, Ansible is by far the most popular choice. Ansible's ecosystem has been growing rapidly in the last few years, with modules being contributed by both internal (Redhat) developers and open-source community. Having the backing of one of the largest open-source first companies has allowed Ansible to spread into all areas of infrastracture -- from server automation to cloud provisioning. By following  the principle of eating your own dogfood, Redhat used Ansible in a lot of its own open-source projects, which made it even more popular in the masses. Another important factor in Ansible's success was the ease of understanding. When it comes to network automation, Ansible's stateless and agentless architecture very closely follows a standard network operation experience -- SSH in, enter commands line-by-line, catch any errors, save and disconnect. But just like many complex software projects, Ansible is not without its own challenges, and in this post we'll take a look at what they are and how we can use CUE to overcome them.

## Ansible Automation Workflow

Let's start with an overview of the intermediate Ansible automation workflow, that was described in the [previous post](/post/2022-10-cue-intro/), and try to see what areas are more prone to human errors or may require additional improvement. Here's a rough outline of the main components and phases of this automation workflow:

1. A user creates a playbook, a device inventory and a set of variables describing the desired state of the network.
2. An Ansible runtime parses all input data and creates a per-host set of variables.
3. This set of high-level variables gets transformed into a larger set of low-level variables.
4. The entire set of variables is now passed to a config generation module, combining them with one or more Jinja templates.
5. The resulting semi-structured text is applied to the running device configuration.

![](/img/cue-ansible.png)

One of the first places where we can make a mistake is the input data. Specifically, a set of input variables is essentially a free-form YAML data structure with values sourced from, potentially, [22 different places](https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#understanding-variable-precedence). This makes an already difficult task of Ansible troubleshooting, even harder.

The next place where things can go wrong is data transformation stage. This stage can be anything from a simple `builtin.set_fact` module with a bunch of filters to what I describe as "Jinja programming" -- manipulating data structures using Jinja's expression statements (e.g. `set` and `do` tags).  In any case, the likelihood of making a mistake gets even higher since both the input data and the transformation logic itself are dynamically-typed and described in a way that's very hard to parse visually.

Now we're at the config generation phase where, once again, the input variables are passed without validation which means you can easily get tripped by one of the [YAML idiosyncrasies](https://docs.saltproject.io/en/latest/topics/troubleshooting/yaml_idiosyncrasies.html) and troubleshooting Jinja templating errors is particularly painful as the error is often reported as vauge "undefined variable". Even worse the default "fail safe" behaviour of Jinja and Ansible filters means that you may end up with an empty string in place of a mandatory value. TODO: add an example?

Finally, one of the unlikely places that can benefit from CUE is the API interactions with the remote device. CUE's scripting capabilities can orchestrate interaction with multiple HTTP-based APIs and by default, would do this concurrently. This not only accelerates execution but also reduces resource utilisation thanks to the CUE's (Go's) light-weight concurrency model compared to the Ansible's more expensive `os.fork()` approach.

The first two areas we've identified above, can be easily integrated into any existing Ansible workflow, without making any serious changes to how the config is generated or delivered. These are the two things we're going to cover in this post. The final two areas are more disruptive but may allow you to replace Ansible completely for pretty much any non-SSH API, i.e. JSON-RPC or REST APIs. We'll leave them for the following article.

## Input Data Validation

## Data Transformatino



Next up: Config Generation and orchestrating API interactions with remote devices



