---
layout: post
title: "REST for Network Engineers Part 1 - Develepment Environment Setup"
date: 2016-01-03
comments: true
sharing: true
footer: true
categories: [rest, pycharm]
description: Working with UNL API with PyCharm
---

In this post I'll show how to setup environment for UnetLab REST SDK Development on Windows. I'll be running UNL inside a VM and using PyCharm as Python IDE on the host OS.

<!--more-->

## UnetLab Installation

Since UNL is a separate project with its own evolving documentation I won't try to reproduce it in my blog and I'll simply refer all my readers to [UnetLab web site][unl-main], [UNL download page][unl-download] and [UNL installation instructions][unl-howto].  
At the time of writing UNL is distrubited as an image packaged in Open Virtualization Format. I'm using VMWare Workstation as a type-2 hypervisor to import and run this image. Check with the [UNL how-to page][unl-howtp] to see the list of currently supported hypervisors.
I'll be using Cisco IOU as a network device emulator in my topologies. Similarly, you can find IOU installation instructions on [UNL website][unl-iou]. The rest of this post assumes you've got UNL up and running and you can successfully create, start and connect to an IOU device by navigating through native GUI interface.

## Installing Python and Dependencies
For development purposes I'll be using [Python 2.7][python-install]. You'll need to install [pip][pip-install] to gain access to [requests][requests-install] library that we'll be using to talk HTTP to our REST server. To install `requests` or any other package using `pip` on a Windows machine, you can use the following command:
``` powershell Installing python HTTP library
python -m pip install requests
```

## PyCharm and Github setup
There's plethora of [IDE](abbr:Intergrated Development Environment)s [available for Python][python-ide]. My personal choice is [PyCharm][pycharm-main] which is a very popular open-source IDE with built-in debugger, syntax checker, code completion and GIT integration.  
Create a new respository on [Github][github-link]. In PyCharm navigate to `VCS -> Checkout from Version Control -> Github`, paste in the link to a newly created repository and click `Clone`. This will create a clone of an empty code repository on your local machine.  
From now on you'll see two VCS buttons in a PyCharm toolbar to pull and push the code to Github. Every time you create a new file or directory you need to add those files to git by right-clicking on the file and selecting `Git -> Add`.  
To push the code to Github click the green VCS button, write your comment in `Commit message` window, enter your Github handle in `Author` field and select `Commit and Push`.  
If you're using multiple machines to push code make sure you pull the latest code before continuing your work by clicking on the blue VCS button.  
Just remember that your Github repository is your source of truth and that's why you need to push changes to it every time you finish work and pull code from it every time you restart it. It makes sense even if you work alone since it creates a good habit which will be very useful in the future.  
For additional information about git workflow and working with Github you can check out (no pun intended) [Github help][github-help] and [Github guides][github-guides].

## Project Directory Setup
Now that we've fully integrated with Github we can setup our basic directory structure. Within our project create 3 directories:

1. Directory to store all code implementing REST SDK logic called `restunl`
2. Directory to store sample applications called `samples`
3. Directory to store test cases for REST SDK

``` powershell Project Directory Structure
└───rest-client-unetlab
   ├───restunl
   │ ├───.gitignore
   │ └───__init__.py
   ├───samples
   │ ├───.gitignore
   │ └───__init__.py
   ├───tests
   │ ├───.gitignore
   │ └───__init__.py
   └─────.gitignore
```
Each directory should contain `.gitignore` file which tells git which files should not get version-controlled. At the very least include the `.pyc` files (compiled code) and other files you don't want to sync. I normally add `.git` and `.*` in main root directory ignore file.


## Before you REST
There's a few things you need to know before start working with REST:

1. IP address and Port (in my case it's 192.168.247.20:80)
2. Username and password for authentication ('admin/unl')
3. REST API documentation - [UnetLab API documentation][unl-api]


## Using REST for the first time
Create a `test.py` file in the root directory of our project. We'll try to query the status of UnetLab server. According UNL documentation the correct request should look like this:

``` bash Requesting UNL status with REST
curl -s -c /tmp/cookie -b /tmp/cookie -X GET -H 'Content-type: application/json' http://127.0.0.1/api/status
```

Let's see how we can issue the same request in Python. 

``` python RESTing with Python
import requests
import json

url = 'http://192.168.247.20/api/status'
method = 'GET'
response = requests.request(method, url)
payload = json.loads(response.content)
print payload['code']
```

This code calls `request` method of requests library and passes in the URL and a type of method. The value returned by this call would be an HTTP response. Since payload is encoded as JSON we need to parse the content of the HTTP response. Once parsed we can access any part of JSON payload same way as dictionary. If you did everything right the result of the last print should be `200`. Feel free to experiment and print, for example, the current version of UNL. Refer to API documentation for the exact structure of the payload.


## Conclusion
Now that we've setup our development environment we'll move on to the actual REST SDK development in the next post. Don't forget to add all your newly created files and directories to git and push them to Github.

[unl-main]: http://www.unetlab.com/
[unl-download]: http://www.unetlab.com/download/index.html
[unl-howto]: http://www.unetlab.com/documentation/index.html
[unl-iou]: http://www.unetlab.com/2014/11/adding-cisco-iouiol-images/
[python-ide]: https://wiki.python.org/moin/IntegratedDevelopmentEnvironments
[pycharm-main]: https://www.jetbrains.com/pycharm/
[github-link]: https://github.com
[python-install]: https://www.python.org/downloads/release/python-2711/
[pip-install]: https://pip.pypa.io/en/latest/installing/
[requests-install]: http://docs.python-requests.org/en/latest/user/install/
[github-help]: https://help.github.com/categories/bootcamp/
[github-guides]: https://guides.github.com/
[unl-api]: http://www.unetlab.com/2015/09/using-unetlab-apis/

