+++
title = "Getting Started With NETCONF and YANG on Cisco IOS XE"
date = 2017-01-25T00:00:00Z
categories = ["Automation"]
url = "/blog/2017/01/25/netconf-intro/"
tags = ["YANG", "ansible-YANG"]
summary = "Everyone who has any interest in network automation inevitably comes across NETCONF and YANG. These technologies have mostly been implemented for and adopted by big telcos and service providers, while support in the enterprise/DC gear has been virtually non-existent. Things are starting to change now as NETCONF/YANG support has been introduced in the latest IOS XE software train. That's why I think it's high time I started another series of posts dedicated to YANG, NETCONF, RESTCONF and various open-source tools to interact with those interfaces"
+++


To kick things off I will show how to use [ncclient][ncclient] and [pyang][pyang] to configure interfaces on Cisco IOS XE device. In order to make sure everyone is on the same page and to provide some reference points for the remaining parts of the post, I would first need to cover some basic theory about NETCONF, XML and YANG.

# NETCONF primer
NETCONF is a network management protocol that runs over a secure transport (SSH, TLS etc.). It defines a set of commands ([RPCs](abbr:Remote Procedure Call)) to change the state of a network device, however it does not define the structure of the exchanged information. The only requirement is for the payload to be a well-formed XML document. Effectively NETCONF provides a way for a network device to expose its API and in that sense it is very similar to [REST][rest-for-neteng]. Here are some basic NETCONF operations that will be used later in this post:

* **hello** - messages exchanged when the NETCONF session is being established, used to advertise the list of supported capabilities.
* **get-config** - used by clients to retrieve the configuration from a network device.
* **edit-config** - used by clients to edit the configuration of a network device.
* **close-session** - used by clients to gracefully close the NETCONF session.

All of these standard NETCONF operations are implemented in [ncclient][ncclient] Python library which is what we're going to use to talk to CSR1k.

# XML primer
There are several ways to exchange structured data over the network. HTML, YAML, JSON and XML are all examples of structured data formats. XML encodes data elements in tags and nests them inside one another to create complex tree-like data structures. Thankfully we are not going to spend much time dealing with XML in this post, however there are a few basic concepts that might be useful for the overall understanding:

* **Root** - Every XML document has one root element containing one or more child elements.
* **Path** - is a way of addressing a particular element inside a tree.
* **Namespaces** - provide name isolation for potentially duplicate elements. As we'll see later, the resulting XML document may be built from several YANG models and namespaces are required to make sure there are no naming conflicts between elements.

The first two concepts are similar to paths in a Linux filesystem where all of the files are laid out in a tree-like structure with root partition at its top. Namespace is somewhat similar to a unique URL identifying a particular server on the network. Using namespaces you can address multiple unique `/etc/hosts` files by prepending the host address to the path.

As with other structured data formats, XML by itself does not define the structure of the document. We still need something to organise a set of XML tags, specify what is mandatory and what is optional and what are the value constraints for the elements. This is exactly what YANG is used for.

# YANG primer
YANG was conceived as a human-readable way to model the structure of an XML document. Similar to a programming language it has some primitive data types (integers, boolean, strings), several basic data structures (containers, lists, leafs) and allows users to define their own data types. The goal is to be able to formally model any network device configuration.  

Anyone who has ever used Ansible to [generate text network configuration files][ansible-net] is familiar with network modelling. Coming up with a naming conventions for variables, deciding how to split them into different files, creating data structures for variables representing different parts of configuration are all a part of network modelling. YANG is similar to that kind of modelling, only this time the models are already created for you. There are three main sources of YANG models today:

1. **Equipment Vendors** create their own "native" models to interact with their devices.
1. **Standards bodies** (e.g. IETF and IEEE) were supposed to be the driving force of model creation. However in reality they have managed to produce only a few models that cover basic functionality like interface configuration and routing. Half of these models are still in the "DRAFT" stage.
2. **OpenConfig** working group was formed by major telcos and SPs to fill the gap left by IETF. OpenConfig has produced the most number of models so far ranging from LLDP and VLAN to segment routing and BGP configurations. Unfortunately these models are only supported by high-end SP gear and we can only hope that they will find their way into the lower-end part of the market.

Be sure to check of these and many other YANG models on [YangModels][yang-models] Github repo.

# Environment setup
My test environment consists of a single instance of Cisco CSR1k running IOS XE 16.04.01. For the sake of simplicity I'm not using any network emulator and simply run it as a stand-alone VM inside VMWare Workstation. CSR1k has the following configuration applied:
```
username admin privilege 15 secret admin
!
interface GigabitEthernet1
  ip address 192.168.145.51 255.255.255.0
  no shutdown
!
netconf-yang
```

The last command is all what's required to enable NETCONF/YANG support.

On the same hypervisor I have my development CentOS7 VM, which is connected to the same network as the first interface of CSR1k. My VM is able to ping and ssh into the CSR1k. We will need the following additional packages installed:

```
yum install openssl-devel python-devel python-pip gcc
pip install ncclient pyang pyangbind ipython
```

# Device configuration workflow
The following workflow will be performed in both interactive Python shell (e.g. iPython) and Linux bash shell. The best way to follow along is to have two sessions opened, one with each of the shells. This will save you from having to rerun import statements every time you re-open a python shell.

## 1. Discovering device capabilities
The first thing you have to do with any NETCONF-capable device is discover its capabilities. We'll use ncclient's [manager][ncclient-manager] module to establish a session to CSR1k. Method `.connect()` of the manager object takes device IP, port and login credentials as input and returns a reference to a NETCONF session established with the device.

```python
from ncclient import manager

m = manager.connect(host='192.168.145.51', port=830, username='admin',
                    password='admin', device_params={'name': 'csr'})

print m.server_capabilities
```

When the session is established, server capabilities advertised in the **hello** message get saved in the `server_capabilities` variable. Last command should print a long list of all capabilities and supported YANG models.

## 2. Obtaining YANG models
The task we have set for ourselves is to configure an interface. CSR1k supports both native (Cisco-specific) and IETF-standard ways of doing it. In this post I'll show how to use the IETF models to do that. First we need to identify which model to use. Based on the discovered capabilities we can guess that **ietf-ip** could be used to configure IP addresses, so let's get this model first. One way to get a YANG model is to search for it on the Internet, and since its an IETF model, it most likely can be found in of the [RFCs][ietf-ip-rfc].
Another way to get it is to download it from the device itself. All devices supporting [RFC6022][rfc6022] must be able to send the requested model in response to the `get_schema` call. Let's see how we can download the **ietf-ip** YANG model:

```python
schema = m.get_schema('ietf-ip')
print schema
```

At this stage the model is embedded in the XML response and we still need to extract it and save it in a file. To do that we'll use python `lxml` library to parse the received XML document, pick the first child from the root of the tree (**data** element) and save it into a variable. A helper function [write_file][github-helper] simply saves the Python string contained in the `yang_text` variable in a file.

```python
import xml.etree.ElementTree as ET
root = ET.fromstring(schema.xml)
yang_text = list(root)[0].text
write_file('ietf-ip.yang', yang_text)
```

Back at the Linux shell we can now start using pyang. The most basic function of pyang is to convert the YANG model into one of the [many supported formats][pyang-formats]. For example, tree format can be very helpful for high-level understanding of the structure of a YANG model. It produces a tree-like representation of a YANG model and annotates element types and constraints using syntax described in [this RFC][yang-tree-rfc].

```
$ pyang -f tree ietf-ip.yang | head -
module: ietf-ip
  augment /if:interfaces/if:interface:
    +--rw ipv4!
    |  +--rw enabled?      boolean
    |  +--rw forwarding?   boolean
    |  +--rw mtu?          uint16
    |  +--rw address* [ip]
    |  |  +--rw ip               inet:ipv4-address-no-zone
    |  |  +--rw (subnet)
    |  |     +--:(prefix-length)
```

From the output above we can see the **ietf-ip** augments or extends the **interface** model. It adds new configurable (rw) containers with a list of IP prefixes to be assigned to an interface. Another thing we can see is that this model cannot be used on its own, since it doesn't specify the name of the interface it augments. This model can only be used together with `ietf-interfaces` YANG model which models the basic interface properties like MTU, state and description. In fact `ietf-ip` relies on a number of YANG models which are specified as imports at the beginning of the model definition.

```
module ietf-ip {
 namespace "urn:ietf:params:xml:ns:yang:ietf-ip";
 prefix ip;
 import ietf-interfaces {
   prefix if;
 }
 import ietf-inet-types {
   prefix inet;
 }
 import ietf-yang-types {
   prefix yang;
 }
```

Each import statement specifies the model and the prefix by which it will be referred later in the document. These prefixes create a clear separation between namespaces of different models.  

We would need to download all of these models and use them together with the **ietf-ip** throughout the rest of this post. Use the procedure described above to download the **ietf-interfaces**, **ietf-inet-types** and **ietf-yang-types** models.

## 3. Instantiating YANG models

Now we can use [pyangbind][pyangbind], an extension to pyang, to build a Python module based on the downloaded YANG models and start building interface configuration. Make sure your `$PYBINDPLUGIN` variable is set like its described [here][pyangbind].

```
pyang --plugindir $PYBINDPLUGIN -f pybind -o ietf_ip_binding.py ietf-ip.yang ietf-interfaces.yang ietf-inet-types.yang ietf-inet-types.yang
```

The resulting `ietf_ip_binding.py` is now ready for use inside the Python shell. Note that we import `ietf_interfaces` as this is the parent object for `ietf_ip`. The details about how to work with generated Python binding can be found on pyangbind's [Github page][pyangbind].

```python
from ietf_ip_binding import ietf_interfaces
model = ietf_interfaces()
model.get()
{'interfaces': {'interface': {}}, 'interfaces-state': {'interface': {}}}
```

To setup an IP address, we first need to create a model of an interface we're planning to manipulate. We can then use `.get()` on the model's instance to see the list of all configurable parameters and their defaults.

```python
new_interface = model.interfaces.interface.add('GigabitEthernet2')
new_interface.get()
{'description': u'',
 'enabled': True,
 'ipv4': {'address': {},
  'enabled': True,
  'forwarding': False,
  'mtu': 0,
  'neighbor': {}},
 'ipv6': {'address': {},
  'autoconf': {'create-global-addresses': True,
   'create-temporary-addresses': False,
   'temporary-preferred-lifetime': 86400L,
   'temporary-valid-lifetime': 604800L},
  'dup-addr-detect-transmits': 1L,
  'enabled': True,
  'forwarding': False,
  'mtu': 0L,
  'neighbor': {}},
 'link-up-down-trap-enable': u'',
 'name': u'GigabitEthernet2',
 'type': u''}
```

The simples thing we can do is modify the interface description.

```python
new_interface.description = 'NETCONF-CONFIGURED PORT'
new_interface.get()['description']
```

New objects are added by calling `.add()` on the parent object and passing unique key as an argument.

```python
ipv4_addr = new_interface.ipv4.address.add('12.12.12.2')
ipv4_addr.get()
{'ip': u'12.12.12.2', 'netmask': u'', 'prefix-length': 0}
ipv4_addr.netmask = '255.255.255.0'
```

At the time of writing pyangbind only supported serialisation into JSON format which means we have to do a couple of extra steps to get the required XML. For now let's dump the contents of our interface model instance into a file.

```python
import pyangbind.lib.pybindJSON as pybindJSON
json_data = pybindJSON.dumps(model, mode='ietf')
write_file('new_interface.json',json_data)
print json_data
```

## 4. Applying configuration changes

Even though pyanbind does not support XML, it is possible to use [other pyang plugins][pyang-json-xml] to generate XML from JSON.

```
pyang -f jtox -o interface.jtox ietf-ip.yang ietf-interfaces.yang ietf-inet-types.yang ietf-yang-types.yang
json2xml -t config -o interface.xml interface.jtox interface.json
```

The resulting `interface.xml` file contains the XML document ready to be sent to the device. I'll use [read_file][github-helper] helper function to read its contents and save it into a variable. We should still have a NETCONF session opened from one of the previous steps and we'll use the [edit-config][NETCONF-edit] RPC call to apply our changes to the running configuration of CSR1k.

```
xml = read_file('interface.xml')
reply = m.edit_config(target='running', config=xml)
print("Success? {}".format(reply.ok))
m.close_session()
```

If the change was applied successfully `reply.ok` should return `True` and we can close the session to the device.

## Verifying changes

Going back to the CSR1k's CLI we should see our changes reflected in the running configuration:

```
Router#sh run int gi 2
Building configuration...

Current configuration : 126 bytes
!
interface GigabitEthernet2
 description NETCONF-CONFIGURED PORT
 ip address 12.12.12.2 255.255.255.0
 negotiation auto
end
```

## All-in-one scripts

Checkout [this][github-yang] Github page for Python scripts that implement the above workflow in a more organised way.

---

In this post I have merely scratched the surface of YANG modelling and network device programming. In the following posts I am planning to take a closer look at the RESTCONF interface, internal structure of a YANG model, Ansible integration and other YANG-related topics until I run out of interest. So until that happens... stay tuned.

[ietf-ip-rfc]: https://tools.ietf.org/html/rfc7277
[rfc6022]: https://tools.ietf.org/html/rfc6022
[github-helper]: https://github.com/networkop/yang/blob/master/helpers.py
[yang-tree-rfc]: https://tools.ietf.org/html/rfc7277#section-1.2
[pyangbind]: https://github.com/robshakir/pyangbind
[pyang-json-xml]: https://github.com/mbj4668/pyang/wiki/XmlJson
[NETCONF-edit]: https://tools.ietf.org/html/rfc6241#section-7.2
[NETCONF-before]: http://packetpushers.net/using-NETCONF-yang-to-configure-network-devices-and-why-it-does-not-replace-snmp/
[rest-for-neteng]: /blog/2016/01/01/rest-for-neteng/
[github-yang]: https://github.com/networkop/yang
[ncclient]: http://ncclient.readthedocs.io/en/latest/
[pyang]: https://github.com/mbj4668/pyang
[ansible-net]: http://networkop.co.uk/blog/2015/08/26/automating-network-build-p1/
[ncclient-manager]: http://ncclient.readthedocs.io/en/latest/manager.html
[yang-models]: https://github.com/YangModels/yang
[pyang-formats]: https://github.com/mbj4668/pyang#features
