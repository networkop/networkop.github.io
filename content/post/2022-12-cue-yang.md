+++
title = "Network Automation with CUE - Working with YANG-based APIs"
date = 2022-12-07T00:00:00Z
categories = ["howto"]
tags = ["automation", "cue", "ansible"]
summary = "Using CUE to automate YANG-based network APIs"
description = "Using CUE to automate YANG-based network APIs"
images = ["/img/cue-networking.png"]
+++

In the [previous post](/post/2022-11-cue-networking/), I mentioned that CUE can help you work with both "industry-standard" semi-structured APIs and fully structured APIs where data is modelled using OpenAPI or JSON schema. However, there was an elephant in the room that I conveniently ignored but without which no conversation about network automation would be complete. With this post, I plan to rectify my previous omission and explain how you can use CUE to work with YANG-based APIs. More specifically, I'll focus on OpenConfig and gNMI and show how CUE can be used to write YANG-based configuration data, validate it and send it to a remote device.

## Automating YANG-based APIs with CUE

Working with YANG-based APIs is not much different from what I've described in the two previous blog posts [[1]](/post/2022-11-cue-ansible/) and [[2]](/post/2022-11-cue-networking/). We're still dealing with structured data that gets assembled based on the rules defined in a set of YANG models and sent over the wire using one of the supported protocols (Netconf, Restconf or gNMI). One of the biggest differences, though, is that data generation gets done in one of the general-purpose programming languages (e.g. Python, Go), since doing it in Ansible is not feasible due to the sheer complexity of YANG schemas. What CUE can bring to the table is the data transformation and generation capabilities often found in general-purpose programming languages while still retaining the simplicity and readability of a DSL.

If we want to use CUE the main problem that we have to solve is figuring out how to generate the YANG-based CUE definitions. Since YANG is not widely used outside of the physical networking infrastructure space, CUE does not have a native language adaptor for YANG. However, CUE has integrations with a [number of](https://cuelang.org/docs/integrations/) structured data standards which allows us to use one of them as an intermediate step.

One of the projects that can generate Go language bindings from a set of YANG models is [`openconfig/ygot`](https://github.com/openconfig/ygot). Fortunately, CUE understands Go and can generate its own definitions from Go types using the `cue get go [packages]` command. This makes the remainder of the network automation workflow very similar to what I've described in the [previous post](/post/2022-11-cue-networking/). We combine CUE definitions with user-provided data, validating its structure and values. Using CUE scripting, we can serialise this data into JSON and orchestrate [`gnmic`](https://gnmic.kmrd.dev/) to perform a [`Set` RPC](https://github.com/openconfig/reference/blob/master/rpc/gnmi/gnmi-specification.md#341-the-setrequest-message) with the provided data in the payload.

![](/img/cue-yang.png)

Obviously, if things were that easy, I wouldn't be writing this blog post now. YANG is a complicated language that was designed before our industry converged on a much (relatively) simpler set of schema standards. In the rest of this article, I will document what issues I hit when using the automatically-generated CUE definitions, how I worked around them and what challenges still lie ahead.

> All code from this blog post can be found in the [yang-to-cue](https://github.com/networkop/yang-to-cue) github repository

## Generating CUE definitions

One thing I wanted to get out of the gate is that if you want to use YANG-based APIs, most likely you would need to generate your language bindings or, in my case, CUE definitions automatically. There is absolutely no way you can (or should try to) create them manually. You can look at an [average YANG model](https://github.com/openconfig/public/blob/master/release/models/interfaces/openconfig-interfaces.yang) or a [size of the generated library](https://github.com/PacktPublishing/Network-Automation-with-Go/blob/main/ch08/json-rpc/pkg/srl/srl.go) to understand what level of complexity you are dealing with. 

With that in mind, the only way I could make it work is if I used the `cue get go` command, which means the first thing I had to do was generate Go types using the [`openconfig/ygot`](https://github.com/openconfig/ygot). I won't focus on how to do it here, you can see an example in steps 1-3 of the workflow described in the [yang-to-cue](https://github.com/networkop/yang-to-cue) repo or read about it in the [Go Network Automation book](https://www.packtpub.com/product/network-automation-with-go/9781800560925). Once you have those types defined, you can run the `cue get go` command and pull them into your CUE code, for example:

```bash
cue get go yang.to.cue/pkg/...
```

The above command would generate a `[package]_go_gen.cue` file per Go package containing everything that has been recognised and imported. This is where I started seeing issues and below I'll explain what they are and how I fixed them.

### Challenge 1 - Optional fields

When it comes to field optionality, CUE and YANG have opposite defaults. In YANG each node of a tree is optional by default, while in CUE all fields are mandatory unless they are explicitly marked as optional. When CUE imports definitions from Go types, it looks at each struct field and marks it optional if it is a pointer type. This, however, marks some of the fields as required, which goes against the YANG defaults. 

The simplest solution is to walk through all of the fields defined in all of the structs and make them optional. CUE's Go API includes a convenient helper function that traverses all nodes in a parsed CUE file and allows you to modify their content. Below is a snippet from the [`post-import.go`](https://github.com/networkop/yang-to-cue/blob/00f5287a29cf98f1746806e89c5a93b6d2d2d61d/post-import.go) script that does that:

```go
case *ast.StructLit:
  for _, elt := range x.Elts {
    if field, ok := elt.(*ast.Field); ok {
      name, _, err := ast.LabelName(field.Label)
        if err != nil {
          log.Fatal(err)
        }
        if field.Optional == token.NoPos {
          log.Debugf("found mandadory field: %s", name)
          field.Optional = token.Blank.Pos()
        }
      }
    }
```

This was the simplest way to work around the problem. The downside is that we lose the ability to check if any field was marked mandatory by a YANG model. Fortunately, for this we first need to wait for `ygot` to implement [this functionality](https://github.com/openconfig/ygot/issues/514), by which time CUE's [mandatory field proposal](https://github.com/cue-lang/proposal/blob/main/designs/1951-required-fields-v2.md) may get implemented as well, making the future solution a bit easier.
 
### Challenge 2 - ENUMs

The second problem is caused by the way the [`openconfig/ygot`](https://github.com/openconfig/ygot) deals with YANG enum types. Most enum types I've seen are aliases to `int64` and each enum value is a constant (of enum type) that stores that [enum's value](https://www.rfc-editor.org/rfc/rfc7950#section-9.6.4.2). When emitting the JSON value, `ygot` uses the constant to perform a lookup in the `ΛEnum` dictionary storing the actual enum name. The following excerpt from [`yang-to-go/pkg/yang.go`](https://github.com/networkop/yang-to-cue/blob/00f5287a29cf98f1746806e89c5a93b6d2d2d61d/pkg/yang.go) file should make it a bit clearer:

```go
type E_AristaIntfAugments_AristaAddrType int64

const (
  AristaIntfAugments_AristaAddrType_UNSET E_AristaIntfAugments_AristaAddrType = 0
  ...
  AristaIntfAugments_AristaAddrType_IPV6 E_AristaIntfAugments_AristaAddrType = 3
)
var ΛEnum = map[string]map[int64]ygot.EnumDefinition{
  "E_AristaIntfAugments_AristaAddrType": {
    1: {Name: "PRIMARY"},
    2: {Name: "SECONDARY"},
    3: {Name: "IPV6"},
  },
)
```

By default, CUE would ingest all enum types and store them as integers and wouldn't know anything about the above map or its string values. So what I had to do was parse the auto-generated CUE file and patch the enum definitions by replacing integers (enum's value) with strings (enum's name) from the `ΛEnum` map. All this is done inside the same [`post-import.go`](https://github.com/networkop/yang-to-cue/blob/master/post-import.go#L208-L264) script and the resulting CUE code looks something like this:

```javascript
#enumE_AristaIntfAugments_AristaAddrType:
  #AristaIntfAugments_AristaAddrType_UNSET |
  #AristaIntfAugments_AristaAddrType_PRIMARY |
  #AristaIntfAugments_AristaAddrType_SECONDARY |
  #AristaIntfAugments_AristaAddrType_IPV6

#E_AristaIntfAugments_AristaAddrType: string

#AristaIntfAugments_AristaAddrType_UNSET: 
    { #E_AristaIntfAugments_AristaAddrType & "UNSET" }
#AristaIntfAugments_AristaAddrType_PRIMARY: 
    { #E_AristaIntfAugments_AristaAddrType & "PRIMARY" }
...
```

This definition would allow you to write values using concrete value strings, e.g. `"addr-type": "PRIMARY"` or simply refer to one of the globally defined constants, as in the following example from the [`yang-to-cue/values.cue`](https://github.com/networkop/yang-to-cue/blob/master/values.cue):

```javascript
config: {
  "addr-type": oc.#AristaIntfAugments_AristaAddrType_PRIMARY
  "prefix-length": 24
  ip: "192.0.2.1"
}
```

### Challenge 3 - YANG lists

This ended up being the biggest challenge I had to solve. For all intents and purposes, a YANG list is a map (or a dictionary) with values identified by unique keys. So [`openconfig/ygot`](https://github.com/openconfig/ygot) naturally stores YANG lists as Go maps. This makes it easier to ensure uniqueness and catch any duplicates. However, on the wire, a YANG list is represented as a list of objects (`[...{}]`), so when it's time to emit a payload, `ygot` [translates](https://github.com/openconfig/ygot/blob/master/ygot/render.go#L1281) maps to lists, producing a valid RFC7951 JSON.

This last bit is unique to `ygot`'s serialization logic and by default remains unknown to CUE. So I've taken the most straightforward approach and converted all maps to lists before running the `cue get go` command. This is described in the readme of the [yang-to-cue](https://github.com/networkop/yang-to-cue) repository and can be accomplished with a little bit of `sed` magic:

```
sed -i -E 's/map\[.*\]\*(\S+)/\[\]\*\1/' pkg/yang.go
```

While this solves the problem of helping CUE generate a valid RFC7951 JSON, this does not guarantee YANG list entry uniqueness, leaving room for error. Fortunately, it's possible to use CUE itself to introduce additional constraints and ensure all entries in a list are unique.

In the following example, I'm using a hidden field `_check` to store a set of YANG keys and compare its length to the length of the corresponding YANG list. As long as the list and a set of its keys have the same size, the validation passes and a payload is emitted by CUE.

```javascript
#OpenconfigInterfaces_Interfaces: {
  interface: [...null | #OpenconfigInterfaces_Interfaces_Interface]
  _check: {
    for intf in interface {
      let key = intf.name
      "\(key)": true
    }
  }
  if len(_check) != len(interface) {_|_}
}
```

The above code snippet is automatically injected into every YANG list definition in CUE when the [`post-import.go`](https://github.com/networkop/yang-to-cue/blob/00f5287a29cf98f1746806e89c5a93b6d2d2d61d/post-import.go) is run with the default `-yanglist=true` argument. The actual [injected code](https://github.com/networkop/yang-to-cue/blob/master/post-import.go#L189-L200) is slightly more complicated to account for the presence of composite keys (keys with more than one value) and includes a check that `entry.key` is always the same as `entry.config.key` as [required](https://www.openconfig.net/docs/guides/style_guide/#list) by the Openconfig styling guide.


## Outro

So where does all of the above leave us in relation to CUE and YANG? So far I was able to generate some pretty sizeable instances of YANG using  CUE and apply validation rules imported from `ygot` packages. This makes me pretty comfortable I've reached the 80% feature coverage target I was aiming for a [few months ago](https://twitter.com/networkop1/status/1550145828236443648). Here's an example from the [yang-to-cue](https://github.com/networkop/yang-to-cue) repo that you can successfully apply to any reachable Arista EOS device using the `cue apply` command.

```javascript
package main

import oc "yang.to.cue/pkg:yang"

config: oc.#Device & {
  interfaces: interface: [{
    config: {
      description: "loopback interface"
      mtu:         1500
      name:        "Loopback0"
    }
    name: "Loopback0"
    subinterfaces: {
      subinterface: [{
        config: {
          description: "default subinterface"
          index:       0
        }
        index: 0
        ipv4: {
          addresses: {
            address: [{
              ip: "192.0.2.1"
              config: {
                "addr-type":     oc.#AristaIntfAugments_AristaAddrType_PRIMARY
                "prefix-length": 24
                ip:              "192.0.2.1"
              }
            }]
          }
        }
      }]
    }
  }]
  "network-instances": "network-instance": [{
    config: name: "default"
    name: "default"
    protocols: protocol: [{
      bgp: {
        global: config: as: 65000
        neighbors: neighbor: [{
          "afi-safis": "afi-safi": [{
            "afi-safi-name": oc.#OpenconfigBgpTypes_AFI_SAFI_TYPE_IPV4_UNICAST
            config: "afi-safi-name": "IPV4_UNICAST"
          }]
          config: {
            "neighbor-address": "169.254.0.1"
            "peer-as":          65001
          }
          "neighbor-address": "169.254.0.1"
        }]
      }
      config: {
        identifier: "BGP"
        name:       "BGP"
      }
      identifier: "BGP"
      name:       "BGP"
    }]
  }]
}
```

You can use the approach described in this blog post to write and validate YANG-compliant data entirely in CUE and, once CUE gets its own [language server](https://github.com/cue-lang/cue/issues/142), writing this data would become even easier with IDE hints, autocompletion and error highlighting. Combine this with data generation and scripting capabilities described in the [previous post](/post/2022-11-cue-networking/) and this gives you a versatile and robust toolset to work with YANG-based APIs, something that has been missing for a very long time.


There are still a few areas for improvement where CUE does not yet do as good a job as it could. One of them is error reporting in the YANG list validation logic. There's no way to emit a custom error message, however, this may change once [this proposal](https://github.com/cue-lang/cue/issues/943) gets implemented. Another area for improvement could be extracting more metadata from Go types, but this seems to be unique to YANG/ygot so unlikely to get implemented in CUE natively. That being said, I hope that the approach that I've shown here -- importing Go types using CUE and changing them later with a Go script -- would work for most of the potential future improvements.

Since CUE is a pre-1.0 language, I would expect a few more things to change in the coming months. I doubt these changes would have any major negative impact on [what I've written about CUE](http://localhost:1313/tags/cue/) so far. If anything, they would improve the language, like the [query proposal](https://github.com/cue-lang/cue/issues/165) that would simplify CUE's data generation capabilities or the [function signatures proposal](https://github.com/cue-lang/cue/issues/2007) to allow external, user-provided code to be injected into the CUE evaluation process. So in my view now is the right time to start exploring CUE and injecting it into various parts of your network automation workflow. As you dig more into the details of the language, you'll discover more interesting patterns and applications and, hopefully, CUE (Configure, Unify, Execute) becomes that common language for configuration and data, unifying different parts of IT infrastructure.

