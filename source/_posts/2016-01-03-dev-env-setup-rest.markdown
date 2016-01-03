---
layout: post
title: "REST for Network Engineers Part 1 - Development Environment Setup"
date: 2016-01-03
comments: true
sharing: true
footer: true
categories: [rest, git, pycharm]
description: Working with UNL API with PyCharm
---

In this post I'll show how to setup environment for [UnetLab][unl-main] REST SDK development on Windows. I'll be running UNL inside a VM and using PyCharm as Python IDE on the host OS.

<!--more-->

## UnetLab Installation

Since UNL is a separate project with its own evolving documentation I won't try to reproduce it in my blog and I'll simply refer all my readers to [UNL download page][unl-download], [UNL installation instructions][unl-howto] and [UNL first boot configuration][unl-first-boot].  
At the time of writing UNL is distributed as an image packaged in Open Virtualization Format. I'm using VMWare Workstation as a type-2 hypervisor to import and run this image. Check with the [UNL how-to page][unl-howto] for the list of currently supported hypervisors.  
I'll be using Cisco IOU as a network device emulator in my topologies. Similarly, you can find IOU installation instructions on [UNL website][unl-iou]. The rest of this post assumes you've got UNL up and running and you can successfully create, start and connect to an IOU device by navigating through native GUI interface.

## Installing Python and Dependencies
For development purposes I'll be using [Python 2.7][python-install]. You'll need to install a package management system [pip][pip-install] to gain access to [requests][requests-install] library that we'll be using to talk HTTP to our REST server. To install **requests** or any other package using **pip** on a Windows machine, you can use the following command:
``` powershell Installing Python HTTP library
python -m pip install requests
```

## PyCharm and Github integration
There's a plethora of [IDE](abbr:Intergrated Development Environment)s [available for Python][python-ide]. My personal choice is [PyCharm][pycharm-main] - an open-source IDE with built-in debugger, syntax checker, code completion and GIT integration. Here is how you setup PyCharm to work with Github:

1. **Create** a new repository on [Github][github-link]. 
2. In PyCharm navigate to `VCS -> Checkout from Version Control -> Github`, paste in the link to a newly created repository and click `Clone`. This will **create a clone** of an empty code repository on your local machine. From now on you'll see two VCS buttons in PyCharm toolbar to pull and push code to Github.
3. **Add** newly created files and directories to git by right-clicking on them and selecting `Git -> Add`
4. At the end of your work **push** the code to Github by clicking the green VCS button, write your comment in `Commit message` window, enter your Github username in `Author` field and select `Commit and Push`.  
5. To get the latest version of code from Github click the blue VCS button to **pull** changes to local directory.

Just remember that your Github repository is your source of truth and you need to push changes to it every time you finish work and pull code from it every time you restart it. It makes sense even if you work alone since it creates a good habit which may come very useful in the future.    
For additional information about git workflow and working with Github you can check out (no pun intended) [Github help][github-help] and [Github guides][github-guides].

## Project Skeleton
Now that we've fully integrated with Github we can setup our basic directory structure. In project Navigation Bar under the project's main directory create 3 subdirectories:

* `restunl` - to store all code implementing REST SDK logic
* `samples` - to store sample applications
* `tests` - to store test cases for REST SDK

Next we need to tell git which files we DON'T want to track. To do that add filename patterns to `.gitignore` file and put this file into every directory. Rule of thumb is to only track your code and not your auxiliary files like compiled python code (.pyc), PyCharm settings (.idea) or local git files (.git). 

``` bash /rest-blog-unl-client/.gitignore
.idea
.git
*.pyc
```

Finally, in order to be able to import code between different directories within the project, we need to add an empty `__init__.py` file to each non-root directory which tells Python to treat that directory as [a package][python-package-docs]. The final version of skeleton will look like this:

{% img centre /images/restunl-skeleton.png Project Skeleton %} 


## Before you REST
Here are a few things you need to know about the REST server before you start working with it:

1. IP address and Port - the same IP address you use to access UNL from your web browser (in my case it's 192.168.247.20:80)
2. Username and password for authentication - default UNL credentials (admin/unl)
3. REST API documentation - in our case it'll be [UnetLab API documentation][unl-api]


## Using REST for the first time
Let's try to query the status of our UnetLab server. According [UNL documentation][unl-api] the correct request should look like this:

``` bash UNL status API call
curl -s -c /tmp/cookie -b /tmp/cookie -X GET -H 'Content-type: application/json' http://127.0.0.1/api/status
```

Take note of the HTTP method (GET) and URL (http://ip_address/api/status), we'll use these values in our test program. Disregard the cookies and Content-type headers for now, we'll get back to them in the future posts. In our project's root directory create a `test.py` file with the following code:

``` python /rest-blog-unl-client/test.py
import requests
import json

url = 'http://192.168.247.20/api/status'
method = 'GET'
response = requests.request(method, url)
payload = json.loads(response.content)
print payload['code']
```

This code calls `.request` method of requests library and passes in an HTTP method type and the URL. The value returned by this call would be an HTTP response. Since payload is encoded as JSON we need to parse the content of the HTTP response (`response.content`) by calling a `.loads` method of json library. Once parsed, we can work with any part of JSON payload same way we would with a Python dictionary. If you've done everything right, the result of the last print statement should be `200`. Feel free to experiment and print, for example, the current version of UNL. Refer to [API documentation][unl-api] for the exact structure of the payload.


## Conclusion
Now that we've setup our development environment we'll move on to the actual REST SDK development in the next post. Don't forget to add all your newly created files and directories to git and push them to Github.  

All code from this post can be found in my [public repository on Github][post-github-commit]


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
[python-package-docs]: https://docs.python.org/2/tutorial/modules.html#packages
[post-github-commit]: https://github.com/networkop/rest-blog-unl-client/tree/63d8d13e48e61e896185eb7afee3759c1f2cd5a9
[unl-first-boot]: http://www.unetlab.com/2014/11/first-unetlab-boot-configuration/

