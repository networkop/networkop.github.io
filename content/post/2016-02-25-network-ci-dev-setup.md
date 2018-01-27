+++
title = "Network-CI Part 1 - Automatically Building a VM With UNetLab and Jenkins"
date = 2016-02-25T00:00:00Z
categories = ["automation"]
url = "/blog/2016/02/25/network-ci-dev-setup/"
tags = ["network-ci", "DevOps"]
summary = "Traditionally, the first post in the series describes how to setup a development environment. This time I'll do it DevOps-style. I'll show how to use Packer to automatically create and configure a VM with UNetLab and Jenkins pre-installed."
draft = false
+++

![Packer-UNL-Jenkins](/img/packer-unl-jenkins.png)

# Packer intro

[Packer][packer-website] is a tool that can automatically create virtual machines for different hypervisors and cloud platforms. The goal is to produce identically configured VMs for either VirtualBox, VMWare, Amazon or Google clouds based on a single template file. If you're familiar with [Vagrant][vagrant-site], then you can also use Packer to create custom Vagrant boxes. In our case, however, we're only concerned about VMWare since it's the only [type-2 hypervisor][hypervisor-wiki] that supports nested hardware virtualisation (e.g. Intel VT-x), a feature required by UNetLab to run some of the emulated images.  

Packer builds VMs using a special template file. At the very least, this file describes how to:

* Build a VM

* Provision and configure apps on a VM

These two actions correspond to the `builders` and `provisioners` sections of the template file.  

The `builders` section contains a set of instructions for a particular hypervisor or platform on how to build a VM. For example, it might contain the amount of  RAM, CPU and disk sizes, number and type of interfaces, OS boot instructions and so on.  

The `provisioners` section contains a set of instructions to configure a VM. This section may be as simple as a list of shell scripts or may include a reference to Ansible playbook which will be executed after the VM is built.  

You can find my Packer templates along with Ubuntu preseed and provisioner scripts in my [Gihub repository][packer-github]. For those looking for deeper insights about how to build a packer template I can recommend an official Packer [introduction docs][packer-intro].

# Building a VM with Packer

As I've mentioned previously, I'm using Windows as my primary development environment and VMWare Workstation as my hypervisor. Before you begin you also need to have [Packer][packer-install] and [git][git-install] installed. After that the first step is to clone my git repository: 

```
git clone https://github.com/networkop/packer-unl-jenkins
cd packer-unl-jenkins
```
And start the build process:

```
packer build vmware.json
```

With a bit of luck, approximately 30 minutes later you should have a fully configured VM inside your VMWare Workstation waiting to be powered on. These are some of the features of this new VM:

* 4 GB of RAM, 20GB of disk space, 2 dual-core vCPUs
* 1 Host-only and 1 NAT ethernet interfaces both using DHCP
* Jenkins and UNetLab installed
* Git and Python PIP packages installed
* Username/password are `unl/admin`

Once powered on, you should be able to navigate to UNetLab's home page at `http://vm_ip:80` and Jenkins' home page and `http://vm_ip:8080`, where `vm_ip` is the IP of your new VM.

# IOU images

Unfortunately IOU images are not publicly available so you're gonna have to find them yourself, which shouldn't be too hard. You'll also need to generate a license file for these images which, again, I'm not going to discuss in this blog, but I can guarantee that you won't have to look farther than the 1st page of Google search to find all your answers. These are the remaining steps that you need to do:

1. Obtain L2 and L3 IOU images
2. Generate a license file
3. Follow [these instructions][unl-iol] to install those images on the UNetLab server


# non-DevOps way

In case you're struggling with Packer here are the list of steps to setup a similar VM manually:

1. [Download][ubuntu-download] your favourite Ubuntu Server image. Recommended release at the time of writing is 14.04.4.
2. Create a VM with at least 4GB of RAM, VT-x support and boot it off the Ubuntu ISO image.
3. Following instructions [install Ubuntu and UNetLab][unl-install].
4. Install Jenkins as described in [their wiki website][jenkins-install]
5. Install additional packages like git and pip. Refer to my Packer [packages script][packages-script] for commands.

# Coming up

In the next post I'll show how to setup Jenkins to do automatic network testing and verification.

[ubuntu-download]: http://www.ubuntu.com/download/server
[unl-install]: http://www.unetlab.com/2015/08/installing-unetlab-on-a-physical-server/
[jenkins-install]: https://wiki.jenkins-ci.org/display/JENKINS/Installing+Jenkins+on+Ubuntu
[packages-script]: https://github.com/networkop/packer-unl-jenkins/blob/master/scripts/packages.sh
[packer-website]: https://www.packer.io/
[hypervisor-wiki]: https://en.wikipedia.org/wiki/Hypervisor
[packer-intro]: https://www.packer.io/intro/index.html
[packer-install]: https://www.packer.io/intro/getting-started/setup.html
[git-install]: https://git-scm.com/download/win
[unl-iol]: http://www.unetlab.com/2014/11/adding-cisco-iouiol-images/
[packer-github]: https://github.com/networkop/packer-unl-jenkins
[vagrant-site]: https://www.vagrantup.com/docs/
