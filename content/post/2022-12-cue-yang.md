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

Obviously, if things were that easy, you wouldn't be reading this 10 minute article. YANG is a complicated language that was designed before our industry converged on a much (relatively) simpler set of schema standards. In the rest of this blog post I will document what issues I hit when using the automatically-generated CUE definitions, how I worked around them and what challanges still lie ahead.

> All code from this blog post can be found in the [yang-to-cue](https://github.com/networkop/yang-to-cue) github repository

## Generating CUE definitions

One thing to get out of the gate is that if you want to use YANG-based APIs, most likely you would need to generate your language bindings or, in my case, CUE definitions automatically. There is absolutely no way you can (or should try to) create them manually. You can look at an [average YANG model](https://github.com/openconfig/public/blob/master/release/models/interfaces/openconfig-interfaces.yang) or a [size of the generated library](https://github.com/PacktPublishing/Network-Automation-with-Go/blob/main/ch08/json-rpc/pkg/srl/srl.go) to understand what level of complexity you area dealing with. 


```bash
cue get go yang.to.cue/pkg/...
```

### Challenge 1 - ENUMs
### Challenge 2 - YANG lists
### Challenge 3 - Optional fields

When it comes to field optionality, CUE and YANG have opposite defaults. In YANG each node of a tree is optional by default, while in CUE all fields are mandatory, unless they are explicitly marked as optional. When CUE imports definition from Go types, it looks at the struct field type and marks it optional if this is a pointer type. This, however, leaves some of the fields as required, which goes against the YANG defaults. So the simplest solution would be to walk all fields in all structs and make sure they all are marked as default.

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
 



## Outro
CUE is pre 1.0 so some things may change, for example:
https://github.com/cue-lang/proposal/blob/main/designs/1951-required-fields-v2.md