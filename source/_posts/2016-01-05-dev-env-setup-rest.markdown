---
layout: post
title: "REST for NetEng part 1 - Develepment Environment Setup"
date: 2016-01-01
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
At the time of writing UNL is distrubited and an image packaged in Open Virtualization Format. I'm using VMWare Workstation as a type-2 hypervisor to import and run this image. Check with the [UNL how-to page][unl-howtp] to see the list of currently supported hypervisors.
I'll be using Cisco IOU as a network device emulator in my topologies. Similarly you can find IOU installation instructions on [UNL website][unl-iou]. The rest of this post assumes you've got UNL up and running and you can successfully create, start and connect to an IOU device.

## Git setup
All our code will be stored on [Github][github-link] public repository. Follow prompts to create a new repository on Github. 

## Installing Python and Dependencies
For development purposes I'll be using [Python 2.7][python-install]. You'll need to install [pip][pip-install] to gain access to [requests][requests-install] library that we'll be using to talk HTTP to our REST server. To install `requests` or any other package using `pip` on a Windows machine, you can use the following command:
``` powershell
python -m pip install requests
```

## PyCharm Installation
There's plethora of [IDE](abbr:Intergrated Development Environment)s [available for Python][python-ide]. My personal choice is [PyCharm][pycharm-main] which is a free open-source IDE with built-in debugger and GIT integration. 

## Project Directory Setup



## Before you REST

## Using REST for the first time


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
