+++
title = "Network Automation with CUE - Working with YANG-based APIs"
date = 2022-12-05T00:00:00Z
categories = ["howto"]
tags = ["automation", "cue", "ansible"]
summary = "Using CUE to automate YANG-based network APIs"
description = "Using CUE to automate YANG-based network APIs"
images = ["/img/cue-networking.png"]
+++

In the [previous post](/post/2022-11-cue-networking/), I've mentioned that CUE can help you work with both "industry-standard" semi-structured APIs and fully structured APIs where data is modelled using OpenAPI or JSON schema. However, there is an elephant in the room that I conveniently ignored but without which no conversation about network automation would be complete. With this post I plan to rectify my previous omission and explain how you can use CUE to work with YANG-based APIs. More specifically, I'll focus on OpenConfig and gNMI and show how CUE can be used to write YANG-based configuration data, validate it and send it to a remote device.

## Automating YANG-based APIs with CUE

Working with YANG-based APIs is not much different from what I've described in the two previous blog posts [[1]](/post/2022-11-cue-ansible/) and [[2]](/post/2022-11-cue-networking/). We're still dealing with structured data that gets assembled based on the rules defined in a set of YANG models and sent over the wire using one of the supported protocols (Netconf, Restconf or gNMI). One of the biggest differences, though, is that data generation gets done in one of the general-purpose programming languages (e.g. Python, Go), since doing it in Ansible is not feasible due to the sheer complexity of YANG schemas. What CUE can bring to the table is the data transformation and generation capabilities often found in general purpose programming languages while still retaining the simplicity and readbility of a DSL.

If we want to use CUE the main problem that we need to solve is figuring out how to generate the YANG-based CUE definitions. Since YANG is not widely used outside of the physical networking space, CUE does not have a native language adaptor for YANG. However, CUE has integrations with a [number of](https://cuelang.org/docs/integrations/) structured data standards which allows us to use one of them as an intermediate step.

Once of the projects that can generate Go language bindings from a set of YANG models is [`openconfig/ygot`](https://github.com/openconfig/ygot). Fortunately, CUE understands Go and can generate its own definitions from Go types using the `cue get go [packages]` command. This makes the remainder of the network automation workflow relatively straight-forward. We combine CUE definitions with user-provided data, validating its structure and types of values. Using CUE scripting, we can serialise this data into JSON and orchestrate [`gnmic`](https://gnmic.kmrd.dev/) to performs a [`Set` RPC](https://github.com/openconfig/reference/blob/master/rpc/gnmi/gnmi-specification.md#341-the-setrequest-message) with the provided data in the payload.

![](/img/cue-yang.png)

Obviously, if things were that easy, you wouldn't be writing this article now. YANG is a complicated language that was designed before our industry converged on a much (relatively) simpler set of schema standards. In the rest of this blog post I will document what issues I hit when using the automatically-generated CUE definitions, how I worked around them and what challanges still lie ahead.

> All code from this blog post can be found in the [yang-to-cue](https://github.com/networkop/yang-to-cue) github repository

## Generating CUE definitions

One thing I wanted to get out of the gate is that if you want to use YANG-based APIs, most likely you would need to generate your language bindings or, in my case, CUE definitions automatically. There is absolutely no way you can (or should try to) create them manually. You can look at an [average YANG model](https://github.com/openconfig/public/blob/master/release/models/interfaces/openconfig-interfaces.yang) or a [size of the generated library](https://github.com/PacktPublishing/Network-Automation-with-Go/blob/main/ch08/json-rpc/pkg/srl/srl.go) to understand what level of complexity you area dealing with. 

With that in mind, the only way I could make it work is if I used the `cue get go` command, which means the first thing I had to do was generate Go types using the [`openconfig/ygot`](https://github.com/openconfig/ygot). I won't focus on how to do it here, you can see an example in steps 1-3 of the workflow described in the [yang-to-cue](https://github.com/networkop/yang-to-cue) repo or read about it in the [Go Network Automation book](https://www.packtpub.com/product/network-automation-with-go/9781800560925). Once you have those types defined, you can run the `cue get go` command and pull them into your CUE code, for example:

```bash
cue get go yang.to.cue/pkg/...
```

The above command would generate a `[package]_go_gen.cue` file per Go package containing everything that has been recognised and imported. Here's where I started seeing issues and below I'll explain what they are and how I fixed them, starting from the simplest to the hardest.

### Challenge 1 - Optional fields

When it comes to field optionality, CUE and YANG have opposite defaults. In YANG each node of a tree is optional by default, while in CUE all fields are mandatory, unless they are explicitly marked as optional. When CUE imports definition from Go types, it looks at the struct field type and marks it optional if it is a pointer type. This, however, marks some of the fields as required, which goes against the YANG defaults. 

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

This was the simplest wait to work around the problem. The downside is that we lose the ability to check if any field was marked mandatory by its YANG model. Fortunately, for this we first need to wait for `ygot` to implement [this functionality](https://github.com/openconfig/ygot/issues/514), by which time CUE's [mandatory field proposal](https://github.com/cue-lang/proposal/blob/main/designs/1951-required-fields-v2.md) may get implemented as well, making the solution for this problem a bit easier.
 
### Challenge 2 - ENUMs
### Challenge 3 - YANG lists


## Outro
CUE is pre 1.0 so some things may change, for example:
