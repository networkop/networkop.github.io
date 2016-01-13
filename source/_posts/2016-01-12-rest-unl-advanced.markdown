---
layout: post
title: "REST for Network Engineers Part 3 - Advanced operations with UnetLab"
date: 2016-01-12
comments: true
sharing: true
footer: true
categories: [unetlab, rest]
description: Advanced operations with UNetlab
---

In this post we'll look at how to create arbitrary topologies and push configuration to Nodes in UNetlab via REST SDK. We'll conclude by writing a simple application to create and configure a 3-node topology to enable full connectivity.

<!--more-->

## Extracting Node's UUID

In the [previous post][rest-post-2] we have learned how to create a Node. To perform further actions on it we need to know it's UUID. According to HTTP specification `201 - Created` response SHOULD return a `Location` header with resource URI, which would contain resource UUID. However, UNetLab's implementation does not return a Location header so we need to extract that information ourselves. We'll use the previously defined `.get_nodes()` method inside a private `_get_node()` function.

``` python /rest-blog-unl-client/restunl/unetlab.py
class UnlNode(object):

    def __init__(self, lab, device):
    	...
        self.node = self._get_node()
        self.id = self.node['id']
        self.url = self.node['url']

    def _get_node(self):
        nodes = self.lab.get_nodes().json()['data']
        return get_obj_by_name(nodes, self.device.name)
```

 To extract the data from the payload we need to call `.json()` on the returned HTTP response and look for `data` object inside that payload. This object will contain all Node's attributes including the UUID of the Node and it's access URL which we'll use later. To help us find an ID matching a name we'll use a helper function defined below:

``` python /rest-blog-unl-client/restunl/helper.py
def get_obj_by_name(objects, name):
    for obj_id in objects:
        if objects[obj_id]["name"] == name:
            return objects[obj_id]
    return None
```

## Connecting Node to a network

Before we start connecting Nodes together we need to create networks. As per the [design][rest-post-2], UnlNet will be a class holding a pointer to the UnlLab object which created it. The structure of the class will be very similar to UnlNode. 

``` python /rest-blog-unl-client/restunl/unetlab.py
REST_SCHEMA = { 
				... ,
				'create_net': '/labs/{lab_name}/networks',
				'get_nets': '/labs/{lab_name}/networks'
			}

class UnlLab(object):
	...
	def create_net(self, name):
        return UnlNet(self, name)

    def get_nets(self):
        api_call = REST_SCHEMA['get_nets']
        api_url = api_call.format(api_call, lab_name=append_unl(self.name))
        resp = self.unl.get_object(api_url)
        return resp


class UnlNet(object):

    def __init__(self, lab, name):
        api_call = REST_SCHEMA['create_net']
        self.unl = lab.unl
        self.lab = lab
        self.name = name
        payload = {'type': 'bridge', 'name': self.name}
        api_url = api_call.format(api_call, lab_name=append_unl(self.lab.name))
        self.resp = self.unl.add_object(api_url, data=payload)
		self.net = self._get_node()
        self.id = self.net['id']

    def _get_net(self):
        nodes = self.lab.get_nets().json()['data']
        return get_obj_by_name(nets, self.name)
```

## Connecting Node to a network

Official [Unetlab API guide][unl-api] is still under development and doesn't specify how to connect a Node to a network. If you want to find out the syntax for this or any other unspecified API call one option is to do that in a Web GUI while capturing traffic with Wireshark. That is how I've discovered that to connect Node to a network we need to send an Update request with payload containing mapping between Node's interface ID and Network ID.  

``` python /rest-blog-unl-client/restunl/unetlab.py
REST_SCHEMA = { 
                ... ,
                'connect_interface': '/labs/{lab_name}/nodes/{node_id}/interfaces'
            }

class UnlNode(object):
    ...

    def connect_interface(self, intf_name, net):
        api_call = REST_SCHEMA['connect_interface']
        api_url = api_call.format(api_call, lab_name=append_unl(self.lab.name), node_id=self.id)
        payload = {get_intf_id(intf_name): net.id}
        resp = self.unl.update_object(api_url, data=payload)
        return resp
```

The ID of an interface "Ethernet x/y” of an IOU device can be easily calculated based on the formula `id = x + (y * 16)` as described [here][evilrouter-iou]. This will be accomplish with yet another helper function:

``` python /rest-blog-unl-client/restunl/helper.py
def get_intf_id(intf_name):
    x, y = re.findall('\d+', intf_name)
    return int(x) + (int(y) * 16)
```

## Connecting Nodes to each other 

To create multi-access topologies we would need to maintain an internal mapping between Node's interface and the network it's attached to. However, if we assume that all inter-device links are point-to-point, we can not only simplify our implementation but also enable REST client to ignore the notion of a network all together.  We'll simply assume that when device A connects to B our implementation will create a network called `A_B` in the background and connect both devices to it. This method will perform two separate REST calls and therefore will return both responses in a tuple:

``` python /rest-blog-unl-client/restunl/unetlab.py
class UnlNode(object):
    ...

def connect_node(self, local_intf, (other_node, other_intf)):
    net = self.lab.create_net(name='_'.join([self.device.name, other_node.device.name]))
    resp1 = self.connect_interface(local_intf, net)
    resp2 = other_node.connect_interface(other_intf, net)
    return resp1, resp2
```

Assuming all links are point-to-point certainly decreases visibility of created networks and we would not be able to perform selective changes on them in the future. I'll leave till the next time to add a full support of all types of networks.

## Node Start, Stop and Delete

These simple actions can easily be coded using TDD. I will omit the actual implementation and simply provide unit tests for readers to exercise their TDD skills again. 

``` python /rest-blog-unl-client/tests/test_unl.py
class AdvancedUnlNodeTest(BasicUnlNodeTest):

    def setUp(self):
        super(AdvancedUnlNodeTest, self).setUp()
        self.device_one = Router('R1')
        self.device_two = Router('R2')
        self.node_one = self.lab.create_node(self.device_one)
        self.node_two = self.lab.create_node(self.device_two)

    def tearDown(self):
        super(AdvancedUnlNodeTest, self).tearDown()

    def test_start_nodes(self):
        self.lab.stop_all_nodes()
        resp = self.lab.start_all_nodes()
        self.assertEqual(200, resp.status_code)

    def test_stop_nodes(self):
        self.lab.start_all_nodes()
        resp = self.lab.stop_all_nodes()
        self.assertEqual(200, resp.status_code)

    def test_delete_nodes(self):
        resp = self.lab.delete_node(self.node_one.id)
        self.assertEqual(200, resp.status_code)
```

As always, link to full code is available at the end of this post.

## Pushing configuration to Nodes

At this point of time UnetLab does not support importing of Node's configuration from the client and we're stuck with the only access method available - telnet. To push configuration into the Node we're gonna have to establish a telnet session to Node's URI (which we extracted along with UUID) and write all config into that session. The biggest problem is that Nodes take some time to boot before we can access the CLI prompt. To overcome that I had to implement a dirty hack in a form of `__wait_vty()` method that simulates pressing the `Enter` button every 0.1 of a second until it sees a CLI prompt (either `>` or `#`). 

```python /rest-blog-unl-client/restunl/unetlab.py
class Router(Device):
    ...

    def __wait_vty(self, session):
        result = ' ' + session.read_very_eager()
        while not any(stop_char in result[-10:] for stop_char in ['>', '#']):
            session.write('\r\n')
            result += session.read_very_eager()
            time.sleep(0.1)
        return result

    def set_config(self, config):
        session = telnetlib.Telnet(self.url_ip, self.url_port)
        self.__wait_vty(session)
        session.write(config)
        result = self.__wait_vty(session)
        session.close()
        return result
```

Let's hope that UNL team will implement config import soon so that we can get rid of this kludgy workaround.

## Extending our sample app

At this stage we've got all the code to finish off our sample app. With all the heavy work done by the REST client, you can start to appreciate how easy it is to create and configure a simple triangle topology:

``` python
def app_1():
    ...
    lab.start_all_nodes()
```



## Source code




[unl]: http://www.unetlab.com/
[rest-post-2]: http://networkop.github.io/blog/2016/01/06/rest-basic-operations/
[evilrouter-iou]: http://evilrouters.net/2011/01/09/creating-a-netmap-file-for-iou/
