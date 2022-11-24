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

In the rest of this blog post I will cover some of the highlights of the above CUE workflow, while configuring an unnumbered BGP session between Arista cEOS and NVIDIA Cumulus Linux connected back-to-back. The goal is to show an example of how the data flows from its source all the way to its ultimate destination and how CUE can be used at every step of the way. The lab can be spun up with the `cue lab-up ./...` command. [TODO: rewrite]

> All code from this blog post can be found in the [cue-networking-II](https://github.com/networkop/cue-networking-II) Github repository

## Pulling Configuration Data from External Systems

For an external IPAM/DCIM system I'll be using the public demo instance of [Nautobot](https://github.com/nautobot/nautobot) located at [demo.nautbot.com](https://demo.nautobot.com/). Since this is a demo instance, it gets re-built periodically, so I need to pre-populate it with the required device data. This is done based on the static [inventory file](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/inventory/inventory.cue) and automated with the `cue apply ./...` command. The action of populating IPAM/DCIM systems with data is normally a day-0 excercise and is rarely included in network automation workflows, so I won't focus on it here. However, if you're interested in an advanced REST API workflow orchestrated by CUE, you can check out the [`seed_tool.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/seed_tool.cue) file for more details.

Once we have the right data in Nautobot, we can fetch it by orchestrating a number of REST API calls with CUE. However, since Nautobot supports graphQL, I'll cheat a little bit and get all the data in a single RPC. The [query itself](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/query.gql) is less important, as its unique to my specific requirements, so I'll focus only on CUE code. In the [`fetch_tool.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/fetch_tool.cue) file I define a sequence of tasks that will get executed concurrently for all devices from the [inventory](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/inventory/inventory.cue#L14):

1. Query the graphQL API enpoint of Nautobot and unmarshal the response into a CUE struct.
2. Import the received data as CUE and save it in a device-specific directory.

All of the above can be done with a single `cue fetch ./...` command and the following snippet shows how the first task is written in CUE:

```json
import (
	"text/template"
	"tool/http"
	"encoding/json"
)

command: fetch: {
 for _, dev in inventory.#devices {
  (dev.name): {
   gqlRequest: http.Post & {
    url:     inventory.ipam.url + "/graphql/"
    request: inventory.ipam.headers & {
     body: json.Marshal({
      query: template.Execute(gqlQuery.contents, {name: dev.name})
     })
    }
   }

   response: json.Unmarshal(gqlRequest.response.body)

   // save data in a file (omitted for brevity)
  }
 }
}
```
The above code snippet demonstrates how to make a single HTTP API call and parse the received payload using `tool/http` and `encoding/json` packages from the CUE's [standard library](https://pkg.go.dev/cuelang.org/go@v0.4.3/pkg). CUE scripting layer is smart enough to understand dependencies between tasks, as in this case `json.Unmarshal` will only be called once the `gqlRequest` has returned a response, while still trying to run tasks concurrently (all graphQL calls will be made at roughly the same time). This makes it highly effecient at almost no cost to the end user.

## Data Transformation

At this point, it would make sense to talk a little about how CUE evaluates files from an hierarchical directory structure. In Ansible, it's common to use group variables to manage settings common amongst multiple hosts. In CUE, you can use subdirectories to group related hosts and manage their common configuration values. Although my two-node test topology is not the best example for this, I still tried to group data base on the `device role` value extracted from Nautobot. This is how the `./config` directory structure looks like, as you can see host-specific CUE files are sitting in leaf/edge directories, while common data values and operations are defined in their parent directories:

![](/img/cue-dirs.png)

Whenever a CUE script needs to evaluate data from one of these subdirectories (for example `./...` tells CUE to evaluate all files recursively starting from the current directory), the values in the leaf subdirectories get merged with everything from their parents. So, for example, the [`lon-sw-01.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/config/lleaf/lon-sw-01/lon-sw-01.cue) values will get merged with [`./lleaf/groupvars.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/config/lleaf/groupvars.cue) but not with [`sspine/groupvars.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/config/sspine/groupvars.cue), which will get merged with [`lon-sw-02.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/config/sspine/lon-sw-02/lon-sw-02.cue). This is just an example of how to optimise configuration values to remove boilerplate, you can check out my earlier [cue-networking](https://github.com/networkop/cue-networking) repository for a more complete real-world example.

So now in the leaf CUE files we've got the data that was retrieved from Nautobot, saved in a `hostvars: [device name]: {}` struct. That means in the topmost [`hostvars.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/config/hostvars.cue) file I've got access to all of that data and can start adding a schema and even do some initial value computations. You can view the resulting host variables with the `cue try ./...` command.


```json
$ cue try ./...
-== hostvars[lon-sw-02] ==-
name: lon-sw-02
device_role:
  name: sspine
> snip <
```

Majority of the work is done in the [`transform.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/config/transform.cue) file, where `hostvars` get transformed into a complete structured device configuration. As I've already covered data transformation in the [previous blog post](/post/2022-11-cue-ansible/), I won't focus too much on it here, and invite you to walk through [the code](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/config/transform.cue) on your own. However, before moving on, I want to discuss the use of schemas in the data transformation logic, e.g. `nvidia.#set` in the below code snippet from the [`transform.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/config/transform.cue) file:

```json
nvidiaX: {
  _input: {}
  nvidia.#set & {
    interface: {
      for _, intf in _input.interfaces {
        if strings.HasPrefix(intf.name, "loopback") {
          lo: {
            ip: address: (intf.ip_addresses[0].address): {}
            type: "loopback"
// omitted for brevity
```

Although schemas are optional, they can give you additional assurance that what you're doing is right and catch errors before you try to use the generated data. Moreover, once CUE gets its own [language server](https://github.com/cue-lang/cue/issues/142), writing the code would become a lot easier with IDE's help. Similar to Go, you would get features like struct templates, autocompletion and error highlighting. 

The biggest problem with using a schema is generating it in the first place. I've briefly touched upon this subject in the [previous blog post](http://localhost:1313/post/2022-11-cue-ansible/#input-data-validation) but want to expand a bit on it here. No matter if you interact with a [model-compliant API](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-44/api/index.html) (OpenAPI or YANG) or with [templates]((https://github.com/aristanetworks/ansible-avd/tree/devel/ansible_collections/arista/avd/roles/eos_cli_config_gen/templates/eos)) that generate semi-structured set of CLI commands, you can always describe their input with a data model. CUE understands a few common schema languages and can import and generate its own definitions from them. So now all what we need to do is generate that data model somehow.

In some cases, you may be in luck if your vendor already publishes these models, however, this time I'll focus on how to generate them manually. The detailed step-by-step process is [documented](https://github.com/networkop/cue-networking-II#creating-cue-schemas) in the Github repository, but here I want to summarise some of the key points:

* If your device stores configuration as structured data (the case of NVIDIA Cumulus Linux), you can generate a JSON schema from an existing configuration instance. For example, I've worked out the exact set of values I need to configure first, saved it in a YAML file and ran it through YAML to JSON schema [converter](https://jsonformatter.org/yaml-to-jsonschema). 
* If you have to use text templates to produce the device config (the case of Arisa EOS), you can infer a JSON schema from a Jinja template (see [this script](https://github.com/networkop/cue-networking-II/blob/main/schemas/jinja-to-json-schema.py) for an example).
* CUE can correctly recognise the JSON schema format and import it as native definitions using the `cue import` command.
* Following the initial (double) conversion, some of the type information may get lost or distorted, so most likely you would need to massage the automatically generated CUE schema before you can use it. This, however, only needs to be done once, since you can discard the intermediate schema files and carry on working exclusively with CUE files from now on.

You can vew the generated structured device configurations, produced by the data transformation logic, by running the  `cue show ./...` command.

## Configuration Push

This is the final stage of the CUE workflow where, once again, I use CUE scripting to interact with Arista's JSON RPC and NVIDIA's REST APIs. All that is done as a part of a custom `cue push ./...` command that executes multiple vendor-dependent workflows in per-device coroutines. You can find the complete implementation in the [`main_tool.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/main_tool.cue) file, and here I'd like to zoom in on a couple of interesting concepts. 

First one is authentication and secret management. As I've mentioned before, one of the common ways of injecting secrets is via environment variables, e.g. if you running a workflow inside a CI/CD system. While CUE does not support them natively, you can achieve the same result using the `@tag` keyword. A common pattern is to define default values that can be overridden with a user-provided command line tag, like in the following snippet from the [`inventory.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/inventory/inventory.cue) file:

```json
-- inventory/inventory.cue --
package inventory
auth: {
	nvidia: {
		user:     *"cumulus" | string @tag(nvidia_user)
		password: *"cumulus" | string @tag(nvidia_pwd)
	}
	arista: {
		user:     *"admin" | string @tag(arista_user)
		password: *"admin" | string @tag(arista_pwd)
	}
}
#devices: [{
	name:     "lon-sw-01"
	user:     auth.nvidia.user
	password: auth.nvidia.password
}, {
	name:     "lon-sw-02"
	user:     auth.arista.user
	password: auth.arista.password
}]
```

When calling any CUE script, you can now pass an additional `-t tag_name=tag_value` flag that will get injected into the CUE code. For example, this is how I would change the default password for Arista:

```
export ARISTA_PWD=foo
cue push -t arista_pwd=$ARISTA_PWD ./...
```

Another concept is the CUE's [function pattern](https://cuetorials.com/patterns/functions/). It's an ability to abstract a re-usable piece of CUE code in a dedicated struct that can be evaluated when needed by multiple different callers. I've used this pattern multiple times in most of the tool files, but below I'll cover its simplest form. Before we can send the generated configuration to Arista eAPI endpoint, we need to wrap it inside of a few special keywords (`enable`, `configure` and `write`). 

```json
eapi_wrapper: {
  input: [...string]
  output: ["enable", "configure"] + input + ["write"]
}

command: push: {
  for _, dev in inventory.#devices {
    // snip
    (dev.name): {
      // snip
      wrapped_commands: eapi_wrapper & {input: split_commands}
      // snip
    }
  }
}
```

## Outro

* Completely replace Ansible
* CUE vs Ansible performance and repo https://github.com/networkop/cue-networking-II
* YANG to come next

