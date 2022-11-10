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

I've picked this example deliberately because it contains many places where we can make a mistake, but also because it can be very succinctly summarized by the following CUE schema:

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

Here we've created a [CUE definition](https://cuelang.org/docs/tutorials/tour/types/defs/) that describes the structure and type of values expected in the `bonds` variable. The last line "applies" the `#bonds` schema to any existing `bonds` variable. Assuming the above schema is saved in the `bonds.cue` file, we can check if the input variables conform to it with the following command:

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

You can experiment a bit more by changing the values in the input data, for example change `ports` to an empty list or left-shift the indentation of `access: 10` line.

Creating schemas for every input variable can be a tedious process. However, there's a shortcut you can take that can get you almost all the way there relatively easily.  It's a two-step process:

* Use one of the open-source code generators to produce (infer) a JSON Schema from a [YAML](https://www.npmjs.com/package/yaml-to-json-schema), [JSON](https://jsonschema.net/) or a [Jinja template](https://jinja2schema.readthedocs.io/en/latest/) document
* Convert JSON Schema to CUE using the `cue import` command.

To make it easier to follow, I've run through the original `bonds` variable through an [online converter](https://jsonformatter.org/yaml-to-jsonschema), saved the result in a `schema.json` file, and imported it using the `cue import -f -p schema schema.json` command. The resulting `schema.cue` file contained the following: 
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

Once you have your schemas developed, you can start adding them to an existing Ansible workflow. Here are some ideas of how this can be done, starting from the easiest one:

1. You can add an extra task to the top of your Ansible playbook that uses `shell` module to execute `cue vet` against input variables.
2. If you have an existing CI system, you can add the `cue vet` as a new step before the `ansible-playbook` command is executed.
3. Another option is to create a custom module that can be configured to run CUE schema validation for any schema or input variables.

The last option requires you to write an Ansible module in Go, but it allows you to have a native way of providing inputs and consuming outputs:

```yaml
- name: Validate input data model with CUE
  cue_validate:
    schema: "schemas/input.cue"
    input: "{{ hostvars[inventory_hostname] | string | b64encode }}"
  delegate_to: localhost
```

You can find a [reference implementation](https://github.com/networkop/cue-ansible/blob/main/validation/src/main.go) of this module with an example workflow in the [Validation](https://github.com/networkop/cue-ansible/tree/main/validation) page of my [cue-ansible repo](https://github.com/networkop/cue-ansible).

## Data Transformation

At this point, we've only used CUE for schema validation. The next logical step is to ingest all input values in CUE as start working with them as native CUE values. There are many benefits to using CUE for value management, and I'll cover some of them in the following blogposts, but for now let's focus on a very common task of data transformation.

For an example, I'll be using Arista's Validated Design ([AVD](https://github.com/aristanetworks/ansible-avd)) as its one of the most interesting examples of data transformation done in Ansible. AVD uses a combination of custom Python modules and Jinja templates to transform high-level input data and generate structured configs that have all the values required by devices. My goal would be demonstrate CUE's data transformation capabilities by removing parts of Ansible code and Jinja templates and replacing them with CUE code, while keeping the inputs and outputs unchanged.

![](/img/arista-avd.png)

Let's start by cloning the AVD repo and pinning the Ansible collection path to that directory.
```bash
git clone https://github.com/aristanetworks/ansible-avd.git && cd ansible-avd
export ANSIBLE_COLLECTIONS_PATH=$(pwd)
export OUT_DIR=intended/structured_configs
```

Using one of the example topologies, I can run through the build stage and generate the host variables that are used as the input to data transformation logic.

```bash
cd ansible_collections/arista/avd/examples/l2ls-fabric
ansible-playbook build.yml  --tags build,facts,debug
```

At this point, I've gone through the process shown in the diagram above, without using CUE. In the `./intended/structured_configs` directory I now have a set of structured device configs and input host variables. Next I'm going to do two things:

1. Import all input host variables to allow me to use them natively as CUE values. 
2. Save the generated structured device configuration of `LEAF1` switch as a baseline for future comparison (I'm running it through `cue eval --out=yaml` simply to fix the indentation).

```bash
cue import -p hostvars -f $OUT_DIR/LEAF1-debug-vars.yml
mv $OUT_DIR/LEAF1-debug-vars.cue leaf1.cue
cue eval $OUT_DIR/LEAF1.yml --out=yaml > $OUT_DIR/LEAF1.base.yml   
```

In order to keep the input values separate from the data transformation logic, I've moved them to the `hostvars` package using the `-p` flag in the command above. CUE's code organisation practices look very similar to Go (programming language) and allow me to group code into packages and group similar packages into modules. In order to import the `hostvars` package, I first need to create a CUE module:

```bash
cue mod init arista.avd
```

Now I can create a new file called `transform.cue` and import all input variables using the `arista.avd:hostvars` import statement. From then on, I can use a set of data manipulation techniques like the `for` loop, string interpolation, variable declarations and conditionals to expand the high-level data model into a structured configuration containing all device's port channel interfaces:

```bash
package avd

import (
	"arista.avd:hostvars"
	"strconv"
)

// Uplink port channels
port_channel_interfaces: {
	for link in hostvars.switch.uplinks if link.channel_group_id != _|_ {
		let groupID = strconv.Atoi(link.channel_group_id)

		"Port-Channel\(groupID)": {
			description: link.channel_description + "_Po\(groupID)"
			type:        "switched"
			shutdown:    false
			if link.vlans != _|_ {
				vlans: link.vlans
			}
			mode: "trunk"
			if hostvars.switch.mlag != _|_ {
				mlag: groupID
			}
		}
	}
}

// MLAG port channels
if hostvars.switch.mlag != _|_ {
    port_channel_interfaces: {
        let groupID = strconv.Atoi(hostvars.switch.mlag_port_channel_id)

        "Port-Channel\(groupID)": {
            description: "MLAG_PEER_" + hostvars.switch.mlag_peer + "_Po\(groupID)"
            type: "switched"
            shutdown: false,
            vlans: hostvars.switch.mlag_peer_link_allowed_vlans
            mode: "trunk",
            trunk_groups: ["MLAG"]
        }
    }
}
```

The `if value != _|_` expression in the above example is a check if a value is defined, where `_|_` is a special ["bottom" or error value](https://cuelang.org/docs/tutorials/tour/types/bottom/).

The example above contains enough data transformation logic to generate the required set of port channel interfaces which can be checked as follows:

```
cue eval transform.cue
```

Now let's remove the port channel generation logic from AVD's Python module and completely wipe out the corresponding Jinja template:

```
sed -i '/port_channel_interface_name: port_channel_interface,/d' ../../roles/eos_designs/python_modules/mlag/__init__.py
cat /dev/null > ../../roles/eos_designs/templates/underlay/interfaces/port-channel-interfaces.j2
```

I can re-run the playbook again to see what results I get after the above changes:

```bash
ansible-playbook build.yml  --tags build,facts,debug
cue eval $OUT_DIR/LEAF1.yml --out=yaml > $OUT_DIR/LEAF1.new.yml
```

The resulting structured config should contain no port channel configuration data, which we can verify by comparing with the baseline:

```diff
diff $OUT_DIR/LEAF1.new.yml $OUT_DIR//LEAF1.base.yml
67c67,82
< port_channel_interfaces: {}
---
> port_channel_interfaces:
>   Port-Channel47:
>     description: MLAG_PEER_LEAF2_Po47
>     type: switched
>     shutdown: false
>     vlans: "2-4094"
>     mode: trunk
>     trunk_groups:
>       - MLAG
>   Port-Channel1:
>     description: SPINES_Po1
>     type: switched
>     shutdown: false
>     vlans: 10,20
>     mode: trunk
>     mlag: 1
```

Since I already have the port channel data produced by the CUE code, I can merge it together with the latests intended config like this:

```bash
cue eval transform.cue $OUT_DIR/LEAF1.yml --out=yaml > $OUT_DIR/LEAF1.new.yml
```

Re-running the above diff command should show that the new intended device config looks exactly the same (with a minor exception of struct field re-ordering). This means we have generated the same exact output from the same set of inputs, bypassing Python and Jinja and baking all logic in CUE. We have consolidated and unified data transformation and made it easier to read and reason about.

Next up: Config Generation and orchestrating API interactions with remote devices



