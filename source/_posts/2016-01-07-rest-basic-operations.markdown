---
layout: post
title: "REST for Network Engineers Part 2 - Basic Operations with UnetLab"
date: 2016-01-07
comments: true
sharing: true
footer: true
categories: [rest, unetlab]
description: Making first steps with UNetLab REST API
---

In this post I'll show how to build REST SDK to authenticate, create labs and nodes in [UnetLab][unl-main]. I'll briefly cover the difference between composition and inheritance design patterns and demonstrate how to use test-driven development.

<!--more-->

## REST SDK Design

As it is with networks, design is a very crucial part of programming. I won't pretend to be an expert in that field and merely present the way I've built REST SDK. Fortunately, a lot of design will mimic the objects and their relationship on the server side. I'll slightly enhance it to improve code re-use and portability. Here are the basic objects and their relationships:

1. RestServer - implements basic HTTP CRUD logic, strives to be application-agnostic
2. UnlServer - is a RestServer with specific authentication method (cookie-based) and several additional methods
3. Device - an instance of a network device with specific attributes like type, image name, number of CPUs
4. UnlLab - a lab instance existing inside a UnlServer
5. UnlNode - a node instance existing inside a UnlLab
6. UnlNet - a network instance also existing inside a UnlLab object

All these objects are depicted on this simplified [UML](abbr:Unified Modeling Language) diagram:

{% img centre /images/rest-oop-design.png REST SDK UML Diagram %} 

Here I've used inheritance to *extend* RestServer functionality to make a UnlServer. This makes sense because UnlServer object will re-use a lot of the methods from the RestServer. I could have combined them all in one object but I've decided to split the vendor-agnostic bit into a separate component to allow it to be re-used by other RESTful clients.  

The other objects are aggregated and interact through code composition, where Lab holds a pointer to the UnlServer where it was created, Nodes and Nets point to the Lab in which they live. Composition creates loose coupling between objects, while still allowing for method delegation and code re-use.  

Composition vs Inheritance is a much discussed topic. For additional information look [here][comp-v-inh-1], [here][comp-v-inh-1] and [here][comp-v-inh-1].

> Throughout this post I'll be omitting a lot of the non-important code. For full working code there's a link at the end of this post

## RestServer implementation
RestServer object should be able to issue all 4 standard CRUD HTTP requests and return their respective responses. When instantiated, it needs to know the IP address of the server which is used to construct a `base_url`, a common portion of all API calls. There's going to be 4 methods each corresponding to a particular CRUD action. To allow for better code re-use, I've added a `_send_request` method which is the only one that's going to be calling requests library (the leading underscore denotes that this method is only supposed to be used from within that class).


``` python /rest-blog-unl-client/test.py
class RestServer(object):

    def __init__(self, address):
        self.cookies = None
        self.base_url = '/'.join(['http:/', address, 'api'])

    def _send_request(self, method, path, data=None):
        response = None
        url = self.base_url + path
        try:
            response = requests.request(method, url,  json=data, cookies=self.cookies)
        except requests.exceptions.RequestException as e:
            print('*** Error calling %s: %s', url, e.message)
        return response

    def set_cookies(self, cookie):
        self.cookies = cookie

    def get_object(self, api_call, data=None):
        resp = self._send_request('GET', api_call, data)
        return resp

    def add_object(self, api_call, data=None):
        resp = self._send_request('POST', api_call, data)
        return resp

    def update_object(self, api_call, data=None):
        resp = self._send_request('PUT', api_call, data)
        return resp

    def del_object(self, api_call, data=None):
        resp = self._send_request('DELETE', api_call, data)
        return resp
```




## Source code
All code from this post can be found in my [public repository on Github][post-github-commit]


[unl-main]: http://www.unetlab.com/
[uml-link]: http://www.codeproject.com/Articles/618/OOP-and-UML
[comp-v-inh-1]: http://learnpythonthehardway.org/book/ex44.html
[comp-v-inh-2]: http://lgiordani.com/blog/2014/08/20/python-3-oop-part-3-delegation-composition-and-inheritance/
[comp-v-inh-3]: http://python-textbok.readthedocs.org/en/latest/Object_Oriented_Programming.html#avoiding-inheritance
[post-github-commit]: 

