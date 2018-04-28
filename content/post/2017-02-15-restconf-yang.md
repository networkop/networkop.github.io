+++
title = "Introduction to YANG Programming and RESTCONF on Cisco IOS XE"
date = 2017-02-15T00:00:00Z
categories = ["Automation"]
url = "/blog/2017/02/15/restconf-yang/"
tags = ["YANG", "ansible-YANG"]
summary = "The sheer size of some of the YANG models can scare away even the bravest of network engineers. However, as it is with any programming language, the complexity is built out of a finite set of simple concepts. In this post we'll learn some of these concepts by building our own YANG model to program static IP routes on Cisco IOS XE"
+++

In the [previous post][netconf-post] I have demonstrated how to make changes to interface configuration of Cisco IOS XE device using the standard **IETF** model. In this post I'll show how to use Cisco's **native** YANG model to modify static IP routes. To make things even more interesting I'll use RESTCONF, an HTTP-based sibling of NETCONF.

# RESTCONF primer
[RESTCONF][restconf-rfc] is a very close functional equivalent of NETCONF. Instead of SSH, RESTCONF relies on HTTP to interact with configuration data and operational state of the network device and encodes all exchanged data in either XML or JSON. RESTCONF borrows the idea of Create-Read-Update-Delete operations on resources from [REST][rest-post] and maps them to YANG models and datastores. There is a direct relationship between NETCONF operations and RESTCONF HTTP verbs:

| HTTP VERB | NETCONF OPERATION |
|---------- | ----------------- |
| POST      | create            |
| PUT       | replace           |
| PATCH     | merge             |
| DELETE    | delete            |
| GET       | get/get-config    |


Both RESTfullness and the ability to encode data as JSON make RESTCONF a very attractive choice for application developers. In this post, for the sake of simplicity, we'll use Python CLI and `curl` to interact with RESTCONF API. In the upcoming posts I'll show how to implement the same functionality inside a simple Python library.

# Environment setup
We'll pick up from where we left our environment in the [previous post][netconf-post] right after we've configured a network interface. The following IOS CLI command enables RESTCONF's root URL at `http://192.168.145.51/restconf/api/`

```
CSR1k(config)#restconf
```

You can start exploring the structure of RESTCONF interface starting at the root URL by specifying resource names separated by "/". For example, the following command will return all configuration from Cisco's native datastore.

```
curl -v -k admin:admin http://192.168.145.51/restconfi/api/config/native?deep
```

In order to get JSON instead of the default XML output the client should specify JSON media type `application/vnd.yang.datastore+json` and pass it in the `Accept` header.

# Writing a YANG model
[Normally][netconf-post], you would expect to download the YANG model from the device itself. However IOS XE's NETCONF and RESTCONF support is so new that not all of the models are available. Specifically, Cisco's native YANG model for static routing cannot be found in either [Yang Github Repo][yang-github] or the device itself (via `get_schema` RPC), which makes it a very good candidate for this post.  

> **Update 13-02-2017**: As it turned out, the model was right under my nose the whole time. It's called `ned` and encapsulates the whole of Cisco's native datastore. So think of everything that's to follow as a simple learning exercise, however the point I raise in the closing paragraph still stands.

The first thing we need to do is get an understanding of the structure and naming convention of the YANG model. The simplest way to do that would be to make a change on the CLI and observe the result via RESTCONF.

## Retrieving running configuration data

Let's start by adding the following static route to the IOS XE device:

```
ip route 2.2.2.2 255.255.255.255 GigabitEthernet2
```

Now we can view the configured static route via RESTCONF:

```
curl -v -k -u admin:admin -H "Accept: application/vnd.yang.data+json" \
 http://192.168.145.51/restconf/api/config/native/ip/route?deep
```

The returned output should look something like this:

```json
{ "ned:route": {
    "ip-route-interface-forwarding-list": [
      { "prefix": "2.2.2.2",
        "mask": "255.255.255.255",
        "fwd-list": [ { "fwd": "GigabitEthernet2" } ]
      }
    ]
  }
}
```

This JSON object gives us a good understanding of how the YANG model should look like. The root element `route` contains a list of IP prefixes, called `ip-route-interface-forwarding-list`. Each element of this list contains values for IP network and mask as well as the list of next-hops called `fwd-list`. Let's see how we can map this to YANG model concepts.

## Building a simple YANG model
YANG [RFC][yang-rfc] defines a number of data structures to model an XML tree. Let's first concentrate on the three most fundamental data structures that constitute the biggest part of any YANG model:

* **Container** is a node of a tree with a unique name which encloses a set of child elements. In JSON it is mapped to a name/object pair `'name': {...}`
* **Leaf** is a node which contains a value and does not contain any child elements. In JSON leaf is mapped to a single key/value pair `'name': 'value'`
* **List** can be thought of as a table that contains a set rows (list entries). Each list entry can contain Leafs, Containers and other elements and can be uniquely identified by at least one Leaf element called a `key`. In JSON lists are encoded as name/arrays pairs containing JSON objects `'name': [{...}, {...}]`

Now let's see how we can describe the received data in terms of the above data structures:  

* The value of the topmost `route` element is a JSON object, therefore it can only be mapped to a YANG container.
* The value of `ip-route-interface-forwarding-list` is an array of JSON objects, therefore it must be a list.
* The only entry of this list contains `prefix` and `mask` key/value pairs. Since they don't contain any child elements and their values are strings they can only be mapped to YANG leafs.
* The third element, `fwd-list`, is another YANG list and so far contains a single next-hop value inside a YANG leaf called `fwd`.
* Finally, since `fwd` is the only leaf in the `fwd-list` list, it must be that lists' key. The `ip-route-interface-forwarding-list` list will have both `prefix` and `mask` as its key values since their combination represents a unique IP destination.  

With all that in mind, this is how a skeleton of our YANG model will look like:

```json
module cisco-route-static {
  namespace "http://cisco.com/ns/yang/ned/ios";
  prefix ned;
  container route {
    list ip-route-interface-forwarding-list {
      key "prefix mask";
      leaf prefix { type string; }
      leaf mask { type string; }
      list fwd-list {
        key "fwd";
        leaf fwd { type string; }
      }
    }
  }
}
```

YANG's syntax is pretty light-weight and looks very similar to JSON. The topmost `module` defines the model's name and encloses all other elements. The first two statements are used to define XML namespace and prefix that I've described in my [previous post][netconf-post].

## Refactoring a YANG model
At this stage the model can already be instantiated by **pyang** and **pyangbind**, however there's a couple of very important changes and additions that I wanted to make to demonstrate some of the other features of YANG.  

The first of them is common IETF data types. So far in our model we've assumed that prefix and mask can take **any** value in string format. But what if we wanted to check that the values we use are, in fact, the correctly-formatted IPv4 addresses and netmasks before sending them to the device? That is where IETF common data types come to the rescue. All what we need to do is add an import statement to define which model to use and we can start referencing them in our type definitions:

```json
...
import ietf-yang-types { prefix "yang"; }
import ietf-inet-types { prefix "inet"; }
...
leaf prefix { type inet:ipv4-address; }
leaf mask { type yang:dotted-quad; }
```

This solves the problem for the prefix part of a static route but how about its next-hop? Next-hops can be defined as either strings (representing an interface name) or IPv4 addresses. To make sure we can use either of these two types in the `fwd` leaf node we can define its type as a `union`. This built-in type is literally a union, a logical OR, of all its member elements. This is how we can change the `fwd` leaf definition:

```json
...
typedef ip-next-hop {
  type union {
    type inet:ipv4-address;
    type string;
  }
}
...
leaf fwd { type ip-next-hop; }
```

So far we've been concentrating on the simplest form of a static route, which doesn't include any of the optional arguments. Let's add the leaf nodes for name, AD, tag, track and permanent options of the static route:

```json
...
leaf metric { type uint8; }
leaf name { type string; }
leaf tag { type uint8; }
leaf track { type uint8; }
leaf permanent { type empty; }
...
```

Since **track** and **permanent** options are mutually exclusive they should not appear in the configuration at the same time. To model that we can use the `choice` YANG statement. Let's remove the **track** and **permanent** leafs from the model and replace them with this:

```json
choice track-or-perm {
  leaf track { type uint8; }
  leaf permanent { type empty; }
}
```

And finally, we need to add an options for VRF. When VRF is defined the whole `ip-route-interface-forwarding-list` gets encapsulated inside a list called `vrf`. This list has just one more leaf element `name` which plays the role of this lists' key. In order to model this we can use another oft-used YANG concept called `grouping`. I like to think of it as a Python function, a reusable part of code that can be referenced multiple times by its name. Here are the final changes to our model to include the VRF support:

```json
grouping ip-route-list {
  list ip-route-interface-forwarding-list {
      ...
  }
}
grouping vrf-grouping {
  list vrf {
    key "name";
    leaf name { type string; }
    uses ip-route-list;
  }
}
container route {
  uses vrf-grouping;
  uses ip-route-list;
}
```

Each element in a YANG model is optional by default, which means that the `route` container can include any number of VRF and non-VRF routes. The full YANG model can be found [here][cisco-route-yang].

# Modifying static route configuration
Now let me demonstrate how to use our newly built YANG model to change the next-hop of an existing static route. Using [pyang][pyang] we need to generate a Python module based on the YANG model.

```
pyang --plugindir $PYBINDPLUGIN -f pybind -o binding.py cisco-route-static.yang
```

From a Python shell, download the current static IP route configuration:

```python
import requests
url = "http://{h}:{p}/restconf/api/config/native/ip/route?deep".format(h='192.168.145.51', p='80')
headers = {'accept': 'application/vnd.yang.data+json'}
result = requests.get(url, auth=('admin', 'admin'), headers=headers)
current_json = result.text
```

Import the downloaded JSON into a YANG model instance:

```python
import binding
import pyangbind.lib.pybindJSON as pybindJSON
model = pybindJSON.loads_ietf(current_json, binding, "cisco_route_static")
```

Delete the old next-hop and replace it with **12.12.12.2**:

```python
route = model.route.ip_route_interface_forwarding_list["2.2.2.2 255.255.255.255"]
route.fwd_list.delete("GigabitEthernet2")
route.fwd_list.add("12.12.12.2")
```

Save the updated model in a JSON file with the help of a [write_file][github-helper] function:

```python
json_data = pybindJSON.dumps(model, mode='ietf')
write_file('new_conf.json', json_data)
```

# Updating running configuration

If we tried sending the `new_conf.json` file now, the device would have responded with an error:

```
missing element: prefix in /ios:native/ios:ip/ios:route/ios:ip-route-interface-forwarding-list
```

In our JSON file the order of elements inside a JSON object can be different from what was defined in the YANG model. This is expected since one of the fundamental principles of JSON is that an object is an **unordered** collection of name/value pairs. However it looks like behind the scenes IOS XE converts JSON to XML before processing and expects all elements to come in a strict, predefined order. Fortunately, this [bug][ios-json-bug] is already known and we can hope that Cisco will implement the fix for IOS XE soon. In the meantime, we're gonna have to resort to sending XML.  

Following the procedure described in my [previous post][netconf-post], we can use **json2xml** tool to convert our instance into an XML document. Here we hit another issue. Since **json2xml** was designed to produce a NETCONF-compliant XML, it wraps the payload inside a **data** or a **config** element. Thankfully, **json2xml** is a Python script and can be easily patched to produce a RESTCONF-compliant XML. The following is a diff between the original and the patched files

```
408c409
<     if args.target not in ["data", "config"]:
+++
>     if args.target not in ["data", "config", "restconf"]:
437c438,442
<     ET.ElementTree(root_el).write(outfile, encoding="utf-8", xml_declaration=True)
+++
>     if args.target != 'restconf':
>         ET.ElementTree(root_el).write(outfile, encoding="utf-8", xml_declaration=True)
>     else:
>         ET.ElementTree(list(root_el)[0]).write(outfile, encoding="utf-8", xml_declaration=True)
```

Instead of patching the original file, I've applied the above changes to a local copy of the file. Once patched, the following commands should produce the needed XML.

```
pyang -f jtox -o static-route.jtox cisco-route-static.yang
./json2xml -t restconf -o new_conf.xml static-route.jtox new_conf.json
```

The final step would be to send the generated XML to the IOS XE device. Since we are replacing the old static IP route configuration we're gonna have to use HTTP PUT to overwrite the old data.

```
curl -v -k -u admin:admin -H "Content-Type: application/vnd.yang.data+xml" \
 -X PUT http://192.168.145.51/restconf/api/config/native/ip/route/ -d @new_conf.xml
```

# Verification

Back at the IOS XE CLI we can see the new static IP route installed.
```
TEST#sh run | i ip route
ip route 2.2.2.2 255.255.255.255 12.12.12.2
```


# More examples

As always there are more examples available in my [YANG 101 repo][github-yang]

---
The exercise we've done in this post, though useful from a learning perspective, can come in very handy when dealing with vendors who forget or simply don't want to share their YANG models with their customers (I know of at least one vendor that would only publish tree representations of their YANG models). In the upcoming posts I'll show how to create a simple Python library to program static routes via RESTCONF and finally how to build an Ansible module to do that.


[netconf-post]: /blog/2017/01/25/netconf-intro/
[ios-json-bug]: https://github.com/CiscoDevNet/openconfig-getting-started/issues/4
[yang-rfc]: https://tools.ietf.org/html/rfc6020
[rest-post]: /blog/2016/01/01/rest-for-neteng/
[restconf-rfc]: https://www.rfc-editor.org/rfc/rfc8040.txt
[github-yang]: https://github.com/networkop/yang/tree/master/yang-101
[cisco-route-yang]: https://github.com/networkop/yang/blob/master/yang-101/cisco-route-static.yang
[pyang]: https://github.com/mbj4668/pyang
[github-helper]: https://github.com/networkop/yang/blob/master/yang-101/helpers.py
[yang-github]: https://github.com/YangModels
