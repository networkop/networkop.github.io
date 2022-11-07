+++
title = "Network Automation with CUE - Augmenting Ansible workflows"
date = 2022-11-01T00:00:00Z
categories = ["howto"]
tags = ["automation", "cue", "ansible"]
summary = "Augmenting Ansible workflows with CUE"
description = "Augmenting Ansible workflows with CUE"
images = ["/img/cue-networking.png"]
+++

Hardly any conversation about network automation that happens these days can avoid the topic of automation frameworks. Amongst the few that are still actively developed, Ansible is by far the most popular choice. Ansible's ecosystem has been growing rapidly in the last few years, with modules being contributed by both internal (Redhat) and external (community) developers. Having the backing of one of the largest open-source first companies has allowed Ansible to spread into all areas of infrastracture -- from server automation to cloud provisioning. By following  the principle of eating your own dogfood, Redhat used Ansible in a lot of its own open-source projects, which made it even more popular in the masses. Another important factor in Ansible's success is the ease of understanding. When it comes to network automation, Ansible's stateless and agentless architecture very closely follows a standard network operation experience -- SSH in, enter commands line-by-line, catch any errors, save and disconnect. But like many complex software projects, Ansible is not without its own challenges, and in this post we'll take a look at what they are and how we can use CUE to overcome them.

## Ansible Automation Workflow

Let's start with an overview of the intermediate Ansible automation workflow, that was described in the [previous post](/post/2022-10-cue-intro/), and try to see what areas are more prone to human errors or may require additional improvement. Here's a rough outline of how the configuration data travels through this workflow, where it gets mutated and how it is used:

1. User creates a playbook, a device inventory and a set of variables describing the desired state of the network.
2. Ansible runtime parses all input data and calculates a per-host set of variables.
3. This set of high-level variables gets transformed into a larger set of low-level variables.
4. The entire set of variables is now passed to a config generation module which combines them with one or more Jinja templates.
5. The resulting semi-structured text is applied to the running device configuration.

![](/img/cue-ansible.png)

One of the first places where we can make a mistake is the input data. Specifically, a set of input variables is essentially a free-form YAML data structure with values sourced from up to [22 different places](https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#understanding-variable-precedence). There's no way to verify that the shape of the input data structure is correct and the only way to validate the type of the values is by using filters. However, even with filters you can never be sure the returned value has the right type, as filters are built to "fail safe". For example, the `ansible.utils.ipaddr` filter will return the input value (as a string) if it's a valid IP address, but will return a boolean `False` if it isn't, conflating the returned value and an error in a single variable. There's no way to abort Ansible execution or signal to the user that the input value was incorrect unless you use `assert` statements, which become pretty ineffective event with relatively small volumes of data. 

The next place where things can go wrong is the data transformation stage. This can be anything from a simple `builtin.set_fact` module with a bunch of filters to what I describe as "Jinja programming" -- manipulating data structures using Jinja's expression statements (e.g. `set` and `do` tags) or even building a structured document (YAML, JSON) using string interpolation. In any case, the likelihood of making a mistake gets even higher since both the input data and the transformation logic itself are dynamically-typed and Jinja is notorious for becoming [incomprehensible very quickly](https://news.ycombinator.com/item?id=14777697).

Now we're at the config generation phase where, once again, the input variables are passed without validation which means you can easily get tripped by one of the [YAML idiosyncrasies](https://docs.saltproject.io/en/latest/topics/troubleshooting/yaml_idiosyncrasies.html) and troubleshooting Jinja templating errors is particularly painful as errors are often reported with a vauge "undefined variable" message. 

Finally, one of the unlikely places that can benefit from CUE is the API interactions with remote devices. CUE's [scripting capabilities](https://cuelang.org/docs/usecases/scripting/) can orchestrate interaction with multiple HTTP-based APIs and, if possible, would do this concurrently. This not only accelerates execution but also reduces the resource utilisation thanks to the CUE's (Go's) light-weight concurrency model compared to the Ansible's more expensive `os.fork()` approach.

If we go back and look at the first two areas we've identified above, we can see that they can easily by done by an external tool and integrated into any existing Ansible workflow without making any serious changes to how the config is generated or delivered. These will be the two things we're going to cover in this post. 

The final two areas are more disruptive but may allow you to replace Ansible completely for pretty much any non-SSH API automation, i.e. JSON-RPC or REST APIs. I'll cover them in the following article.

## Input Data Validation

If you're thinking about giving CUE a try and now sure where to start, input data validation could be your best option. Creating a schema for input data is a good excercise to test and explore the language while having no negative impact on your automation workflow. The benefits, however, are worth it, as the schema will improve your automation workflow by:

* Validating the structural shape of input variables to catch any indentation errors
* Making sure all variables have the right type and catch any typos before you run the playbook

This could also be a good place to introduce additional constraints for values, for example to verify that BGP ASN is within a valid range or IP addresses are valid. In general, once you've started with a simple schema, you can continue mixing in more policies to tighten the range of allowed values and improve the overall data integrity. 

TODO: DELETE? In its ultimate state, a schema may include a list of required features that need to be enabled for a network protocol,preferred range of network identifiers (VLANs, VNIs, RD/RTs, etc.), becoming an up-to-date network design document.

Let's see a concrete example of how to develop a CUE schema to validate input variables for Cumulus's `golden turtle` [Ansible modules](https://gitlab.com/cumulus-consulting/goldenturtle/cumulus_ansible_modules.git). Get yourself a copy of this repository:

```bash
git clone https://gitlab.com/cumulus-consulting/goldenturtle/cumulus_ansible_modules.git && cd cumulus_ansible_modules
```

You'll find several validated network topologies inside of the `inventories/` directory together with a set of input variables spread across standard Ansible group and host variable diretories. To make this example a bit simpler, I'll focus on the bonds (link aggregation) configuration, and the following example shows a snippet of the `bonds` variable from the [`group_vars/leaf/common.yml`](https://gitlab.com/cumulus-consulting/goldenturtle/cumulus_ansible_modules/-/blob/master/inventories/evpn_symmetric/group_vars/leaf/common.yml#L20) file:

```yaml
bonds:
  - name: bond1
    ports: [swp1]
    clag_id: 1
    bridge:
      access: 10
    options:
      mtu: 9000
      extras:
        - bond-lacp-bypass-allow yes
        - mstpctl-bpduguard yes
        - mstpctl-portadminedge yes
```

I've picked this example deliberately because it contains many places where we can make a mistake. Also, it can be very succinctly summarized by the following CUE schema:

```json
#bonds: [...{
    name: string
    ports: [...string] 
    clag_id: int
    bridge: access: int
    options: {
        mtu: int & <9999
        extras: [...string]
    }
}]

bonds: #bonds
```

Here we've created a [CUE definition](https://cuelang.org/docs/tutorials/tour/types/defs/) that describes the structure and type of values expected in the `bonds` variable. The last line "applies" the `#bonds` schema to any existing `bonds` variable. Assuming the above schema is saved in the `bonds.cue` file, we can validate that the input variables conform to it with the following command:

```bash
$ cue vet bonds.cue inventories/evpn_symmetric/group_vars/leaf/common.yml
```

Now let's introduce a mistake by changing the value of MTU in the input variable. The resulting error message tells us exactly where the error is and why it's not valid.

```bash
$ sed -i 's/mtu: 9000/mtu: 90000/' inventories/evpn_symmetric/group_vars/leaf/common.yml
$ cue vet bonds.cue inventories/evpn_symmetric/group_vars/leaf/common.yml
bonds.0.options.mtu: invalid value 900000 (out of bound <9999):
    ./bonds.cue:8:20
    ./inventories/evpn_symmetric/group_vars/leaf/common.yml:27:13
```

You can experiment a bit more by changing the values in the input data, for example change `ports` to an empty list or shift left the indentation of `access: 10` line.

Creating schemas for every input variable can be a tedious process. However, there's a shortcut you can take that can get you almost all the way there relatively easily.  It's a two-step process:

* Use one of the open-source code generators to produce (infer) a JSON Schema document based on a [YAML](https://www.npmjs.com/package/yaml-to-json-schema) or a [Jinja template](https://jinja2schema.readthedocs.io/en/latest/)
* Use CUE's Go API to convert that JSON Schema into a CUE schema (see [`convert.go`](https://github.com/networkop/cue-ansible/blob/main/jinja/convert.go) for an example)

To make it easier to follow, I've run through the original `bonds` variable through an [online converter](https://jsonformatter.org/yaml-to-jsonschema), saved the result in a `schema.json` file,  downloaded the `convert.go` script and ran `go run convert.go schema.cue`. The resulting `schema.cue` file contained the following: 
```json
bonds: [...#Bond]

#Bond: {
        name: string
        ports: [...string]
        clag_id: int
        bridge:  #Bridge
        options: #Options
}

#Bridge: access: int

#Options: {
        mtu: int
        extras: [...string]
}
```

Althought it's a slightly different (more verbose) version of my hand-written CUE schema, most of the values are exactly the same. The only bits that are missing are the constraints and policies, which are optional and can be added at a later stage. You can find another example of the above process in the [Jinja to CUE](https://github.com/networkop/cue-ansible/tree/main/jinja) page of my [cue-ansible repo](https://github.com/networkop/cue-ansible).

## Data Transformation




Next up: Config Generation and orchestrating API interactions with remote devices



