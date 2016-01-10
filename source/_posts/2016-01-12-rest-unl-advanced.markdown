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

Before we can connect anything to a network, we need to create it. As per the [design][rest-post-2], UnlNet will be a class holding a pointer to the UnlLab object which created it. The structure of the class will follow the pattern similar to UnlNode.

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



## Connecting Nodes to each other

## Pushing configuration to Nodes

## Extending our sample app



[unl]: http://www.unetlab.com/
[rest-post-2]: http://networkop.github.io/blog/2016/01/06/rest-basic-operations/
