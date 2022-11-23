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

For an external IPAM/DCIM system I'll be using the public demo instance of [Nautobot](https://github.com/nautobot/nautobot) located at [demo.nautbot.com](https://demo.nautobot.com/). Since this is a demo instance, it gets re-built periodically, so I need to make sure I pre-populate it with the required device data. This is done based on the static [inventory file](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/inventory/inventory.cue) and automated with the `cue apply ./...` command. The action of populating IPAM/DCIM systems with data is normally a day-0 excercise and is rarely included in network automation workflows, so I won't focus on it here. However, if you're interested in an advanced REST API workflow orchestrated by CUE, you can check out the [`seed_tool.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/seed_tool.cue) file for more details.

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

```tree
config
├── hostvars.cue
├── lleaf
│   ├── groupvars.cue
│   └── lon-sw-01
│       ├── lon-sw-01.cue
│       └── lon-sw-01.yml
├── sspine
│   ├── groupvars.cue
│   └── lon-sw-02
│       ├── lon-sw-02.cue
│       └── lon-sw-02.yml
└── transform.cue
```

Whenever a CUE script needs to evaluate data from one of these subdirectories (for example `./...` tells CUE to evaluate all files recursively starting from the current directory), the values in the leaf subdirectories get merged with everything from their parents. So, for example, the `lon-sw-01.cue` values will get merged with `./lleaf/groupvars.cue` but not with `sspine/groupvars.cue`, which will get merged with `lon-sw-02.cue`. This is just an example of how to optimise configuration values to remove boilerplate, you can check out my earlier [cue-networking](https://github.com/networkop/cue-networking) repository for a more complete real-world example.

In the leaf CUE files I've saved the data I retrieved from Nautobot in a `hostvars: [device name]: {}` struct. Now I can use one of the topmost files, [`hostvars.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/config/hostvars.cue) to define a set of constraints for this data as well as do some initial value computation:

```json
import (
  "net"
  "strings"
)

hostvars: [Name=_]: {
  name: Name
  device_role: name: string
  id: string
  device_type: manufacturer: name: string
  interfaces: [...{
    name: string
    ip_addresses: [...{
      address: string & net.IPCIDR
    }]
  }]
  local_context_data: bgp_asn: <=65535 & >=64512

  // computed values
  loopbackIP: string & net.IPCIDR
  for _, intf in interfaces {
    if intf.name == "loopback0" {
      if len(intf.ip_addresses) > 0 {
        loopbackIP: intf.ip_addresses[0].address
      }
    }
  }
  routerID: string & net.IP
  routerID: strings.Split(loopbackIP, "/")[0]
}
```

The above `hostvars: [Name=_]:` signature is what CUE calls a [template](https://cuelang.org/docs/tutorials/tour/types/templates/) and it allows you to define common defaults and constraints that would apply to all fields within a struct or, in our case, to all devices. I also use this place to extract and save some common values (loopback and router ID) that will be used in the next stage.

This is the result of running `cue try ./...` command, showing the computed `hostvars` for the `lon-sw-01` device:
```json
-== hostvars[lon-sw-01] ==-
name: lon-sw-01
device_role:
  name: lleaf
id: dbd9838d-9b0b-4eac-8553-ba5860fa8490
local_context_data:
  bgp_asn: 65000
  bgp_intfs:
    - swp1
device_type:
  manufacturer:
    name: NVIDIA1
interfaces:
  - name: loopback0
    ip_addresses:
      - address: 198.51.100.1/32
loopbackIP: 198.51.100.1/32
routerID: 198.51.100.1
groupvars: LLEAF-VALUE
```

The majority of the work is done in the [`transform.cue`](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/config/transform.cue) file, where `hostvars` get transformed into a complete structured device configuration. As I've already covered this in the [previous blogpost](/post/2022-11-cue-ansible/), I won't focus too much on it here, and invite you to walk through [the code](https://github.com/networkop/cue-networking-II/blob/64064138005dc55b9fb7a0e5c3b3f9a55eecfdd0/config/transform.cue) on your own. There a few things I do want to mention about the structure of this file before I move on:

1. The schema for structured device configuration is unique per vendor. 
  * In NVIDIA's case it follows the [OpenAPI definition](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-44/api/index.html) for NVUE. 
  * In Arista's case it is based on the data expected by the Ansible AVD's [Jinja templates](https://github.com/aristanetworks/ansible-avd/tree/devel/ansible_collections/arista/avd/roles/eos_cli_config_gen/templates/eos).
2. The github repo contains [instructions](https://github.com/networkop/cue-networking-II#creating-cue-schemas) for how to generate CUE schemas from Jinja and YAML documents.
3. Although schema validation is optional, I'd highly recommend everyone do that, as it would make working with config less error-prone and easier, especially once CUE gets its own languge server support.

You can view the generated structured device configurations by running `cue show ./...`.

```json
-== configs[lon-sw-01] ==-
interface:
 lo:
  ip:
   address:
    198.51.100.1/32: {}
  type: loopback
 swp1:
  type: swp
router:
 bgp:
  enable: "on"
vrf:
 default:
  router:
   bgp:
    address-family:
     ipv4-unicast:
      enable: "on"
      redistribute:
       connected:
        enable: "on"
    autonomous-system: 65000
    enable: "on"
    neighbor:
     swp1:
      remote-as: external
      type: unnumbered
    router-id: 198.51.100.1
```


## Config Generation

## Config Push

## Outro

* Completely replace Ansible
* CUE vs Ansible performance and repo https://github.com/networkop/cue-networking-II
* YANG to come next

