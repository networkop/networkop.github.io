---
layout: post
title: "Openstack on UNetlab"
date: 2016-04-11
comments: true
sharing: true
footer: true
categories: [openstack, unetlab]
description: Running a single-node Openstack instance inside UNetLab
---

In this post I'm going to show how to get a running instance of Openstack inside a UNetLab virtual machine.

<!--more-->

{% img center /images/unl-os.png %}  

## What the hell am I trying to do?

I admit that running Openstack on anything other than baremetal is nonsense. So why would anyone want to run it with two layers of virtualisation underneath? My goal is to explore some of the new SDN/NFV technologies without leaving the confines on my home area network and/or racking up a triple-digit electricity bill. I also wanted to be able to swap underlay networks without spending hours trying to plumb together virtualized switches and servers from multiple vendors. That's why I've decided to use UNetLab VM as a host for my Openstack lab. This would allow me to easily assemble any type of underlay, WAN or DCI network and with hardware virtualisation support I can afford to run Openstack double-nested inside Workstation and Qemu on my dual-core i7 without too much of a performance penalty. After all, [some companies][ravello-link] even managed to turn similar things into a commercial product.

My interest in Openstack is strictly limited by networking, that's why a lot of the things you'll see in this and following posts will not be applicable to a real-life production environment. However, as far as networking is concerned, I'll try to stick as close to the official Openstack [network design][os-arch] as possible. I'll be using [RDO][rdo-home] to deploy Openstack. The specific method will be Packstack which is a collection of Puppet modules used to deploy Openstack components.

Why have I not went the OpenDaylight/Mininet way if I wanted to play with SDN/NFV? Because I wanted something more realistic to play with, that wouldn't feel like vendor's powerpoint presentation. Plus there's plenty of resources on the 'net about it anyway.

So, without further ado, let's get cracking.

## Setting the scene

On my Windows 8 laptop I've got a UNL virtual machine running inside a VMWare Workstation.. I've [downloaded][unl-download] and [upgraded][unl-upgrade] a pre-built UNL VM image. I've also downloaded a copy of the [Centos 7 minimal ISO image][centos-minimal] and copied it over to my UNL VM's home directory.  

For network access I'll be using VMWware Workstation's NAT interface. It's currently configured with `192.168.91.0/24` subnet with DHCP range of `.128-.254`. Therefore I'll be using `.10-.126` to allocate IPs to my Openstack servers.

## Creating a custom node type in UNL

Every node type inside UNL has its own unique settings. Some settings, like amount of RAM, CPU or number of network interfaces, can be changed during node instantiation, while some of them remain "baked in". Say, for example, the default "Linux" template creates nodes with default **Qemu Virtual CPU** which doesn't support the hardware virtualisation (**VT-X/AMD-V**) [required][os-kvm-req] by Openstack. In order to change that you can either edit the existing node template or follow these steps to create a new one:

1. Add Openstack node definition to initialization file `/opt/unetlab/html/includes/init.php`.

    {% codeblock lang:php   %}
    'linux'                 =>      'Linux',
    'openstack'             =>      'Openstack',
    'mikrotik'              =>      'MikroTik RouterOS',
    {% endcodeblock  %}

2. Create a new Openstack node template based on existing linux node template.

   {% codeblock lang:bash   %}
   $ cp /opt/unetlab/html/templates/linux.php /opt/unetlab/html/templates/openstack.php
   {% endcodeblock  %}

3. Edit the template file replacing all occurences of 'Linux' with 'Openstack'

   {% codeblock lang:bash   %}
   $ sed -i 's/Linux/Openstack/g; s/linux/openstack/g' /opt/unetlab/html/templates/openstack.php
   {% endcodeblock  %}

4. Edit the template file to double the RAM and CPU and pass all host's CPU instructions to Openstack nodes

   {% codeblock lang:bash   %}
   $ sed -i 's/2048/4096/; s/\(cpu.*\) = 1/\1 = 2/; s/\(order=\)dc/\1cd -cpu host/' /opt/unetlab/html/templates/openstack.php
   {% endcodeblock  %}

At this point you should be able to navigate to UNL's web interface and find a new node of type Openstack. However you won't be able to create it until you have at least one image, which is what we're going to build next.

## Building a Linux VM inside UNetLab

Now we need to create a CentOS image inside a UNL. One way to do it is build it inside a VMWare Workstation, copy it to UNL and convert the **.vmdk** to **.qcow2**. However, when I tried doing this I ran into a problem with CentOS not finding the correct disk partitions during bootup. The workaround was to boot into rescue mode and rebuild the initramfs. For those feeling adventurous, I would recommend checking out the following links [[1][initram-rebuild-1], [2][initram-rebuild-2], [3][initram-rebuild-3]] before trying this option.  
The other option is to build CentOS inside UNL from scratch. This is how you can do it:

1. Create a new directory for Openstack image

    {% codeblock lang:bash   %}
    $ mkdir -p /opt/unetlab/addons/qemu/openstack-1
    {% endcodeblock  %}

2. Create a link to CentOS ISO boot image from our new directory

   {% codeblock lang:bash   %}
   $ ln -s ~/CentOS-7-x86_64-Minimal-1511.iso /opt/unetlab/addons/qemu/openstack-1/cdrom.iso
   {% endcodeblock  %}

3. Create a blank 6Gb disk image

   {% codeblock lang:bash   %}
   $ /opt/qemu/bin/qemu-img create -f qcow2 -o preallocation=metadata /opt/unetlab/addons/qemu/openstack-1/virtioa.qcow2 6G
   {% endcodeblock  %} 

   If you want to create **snapshots** at any stage of the process you'd need to use a copy of this file under /opt/unetlab/tmp/pod_id/lab_uuid/node_id/ directory

Now you should be able to successfully create an Openstack node and connect it to Internet. Create a new network that would have Internet connectivity (in my case it's **pnet0**) and connect it to Openstack's **eth0**.  At this stage we have everything ready to start installing Openstack, but before we move on let me take a quick detour to tell you about my ordeals with VNC integration.

## Optional: Integrating TightVNC with UNL

For some unknown reason UltraVNC does not work well on my laptop. My sessions would often crash or start minimised with the only option to close the window. That's not the only thing not working properly on my laptop thanks to the corporate policies with half of the sh\*t locked down for *security* reasons.  
So instead of mucking around with **Ultra** I decided to give me old pal **Tight**VNC a go. The setup process is very similar to the [official VNC integration guide][unl-vnc] with the following exceptions:

1. The wrapper file simply strips the leading 'vnc://' and trailing '/' off the passed argument

   {% codeblock lang:winbatch   %}
   SET arg=%1
   SET arg=%arg:~6%
   SET arg=%arg:~0,-1%
   start "" "c:\Program Files\TightVNC\tvnviewer.exe" %arg%
   {% endcodeblock  %}

2. The registry entry now points to the TightVNC wrapper

   {% codeblock lang:registry   %}
   [HKEY_CLASSES_ROOT\vnc\shell\open\command]
   @="\\"c:\\Program Files\\TightVNC\\wrapper.bat\\" %1"
   {% endcodeblock  %}

## Installing CentOS and Openstack

Finally, we've got all our ducks lined up in a row and we're ready to shoot. Fire up the Openstack node inside UNL and click on it to open a vnc session. Proceed to install CentOS with default options. You need to confirm which **hard disk** to use and setup the **hostname** and the **root password** during installation process. 
As I mentioned earlier, we'll be using RDO's Packstack to deploy all the necessary Openstack components. The whole installation process will be quite simple and can be found on the RDO's [quickstart page][rdo-quickstart]. Here is my slightly modified version of installation process:

1. Disable Network Manager and SELinux.

    {% codeblock lang:bash   %}
    $ service NetworkManager stop
    $ systemctl disable NetworkManager.service
    $ setenforce 0
    $ sed -i 's/enforcing/permissive/' /etc/selinux/config
    {% endcodeblock  %}

2. Configure static IP address `192.168.91.10` on the network interface.   
    Assuming your interface name is `eth0` make sure you /etc/sysconfig/network-scripts/ifcfg-eth0 looks something like this:

    {% codeblock lang:bash   %}
    TYPE="Ethernet"
    BOOTPROTO="static"
    IPADDR=192.168.91.10
    PREFIX=24
    GATEWAY=192.168.91.2
    DNS1=192.168.91.2
    NAME="eth0"
    DEVICE="eth0"
    ONBOOT="yes"  
    {% endcodeblock  %}

    Issue a `service network restart` and reconnect to the new static IP address. Make sure that you still have access to Internet after making this change.

4. Setup RDO repositories

    {% codeblock lang:bash   %}
    $ sudo yum install -y https://rdoproject.org/repos/rdo-release.rpm
    {% endcodeblock  %}

5. Update your current packages

    {% codeblock lang:bash   %}
    $ sudo yum update -y
    {% endcodeblock  %}

6. Install Packstack

    {% codeblock lang:bash   %}
    $ sudo yum install -y openstack-packstack
    {% endcodeblock  %}

    That's where it'd make sense to take a snapshot with `qemu-img snapshot -c pre-install virtioa.qcow2` command

7. Deploy a single-node Openstack environment
    
    {% codeblock lang:bash   %}
    $ packstack \--allinone \
    \--os-cinder-install=n \
    \--os-ceilometer-install=n \
    \--os-trove-install=n \
    \--os-ironic-install=n \
    \--nagios-install=n \
    \--os-swift-install=n \
    \--os-neutron-ovs-bridge-mappings=extnet:br-ex \
    \--os-neutron-ovs-bridge-interfaces=br-ex:eth0 \
    \--os-neutron-ml2-type-drivers=vxlan,flat \
    \--provision-demo=n
    {% endcodeblock  %}

    Here we're overriding some of the default Packstack options. We're not installing some of the components we're not going to use and setting up a name (**extnet**) for our external physical segment, which we'll use in the next section.


At the end of these 4 steps you should be able to navigate to Horizon (Openstack's dashboard) by typing `http://192.168.91.10` in your browser. You can find login credentials in the `~/keystonerc_admin` file.

## Configuring Openstack networking

At this stage we need to setup virtual networking infrastructure inside Openstack. This will be almost the same as described in RDO's external network [setup guide][rdo-ext-net]. The only exceptions will be the [floating IP range][os-float-range], which will match our existing environment, and the fact that we're no going to setup any additional tenants yet. This is how our topology will look like:

{% img center /images/os-net-1.png %}  

1. Switch to Openstack's `admin` user
    {% codeblock lang:bash   %}
    $ source ~/keystonerc_admin
    {% endcodeblock  %}

1. Create external network
    {% codeblock lang:bash   %}
    neutron net-create external_network \--provider:network_type flat \
    \--provider:physical_network extnet  \
    \--router:external \
    \--shared
    {% endcodeblock  %}

3. Create a public subnet 

    {% codeblock lang:bash   %}
    neutron subnet-create \--name public_subnet \
    \--enable_dhcp=False \
    \--allocation-pool=start=192.168.91.90,end=192.168.91.126 \
    \--gateway=192.168.91.2 external_network 192.168.91.0/24
    {% endcodeblock  %}

    Default gateway is VMware's NAT IP address 

4. Create a private network and subnet

    {% codeblock lang:bash   %}
    neutron net-create private_network
    neutron subnet-create \--name private_subnet private_network 10.0.0.0/24 \
    \--dns-nameserver 8.8.8.8
    {% endcodeblock  %}

     This network is not routable outside of Openstack and is used for inter-VM communication

5. Create a virtual router and attach it to both networks

    {% codeblock lang:bash   %}
    neutron router-create router
    neutron router-gateway-set router external_network
    neutron router-interface-add router private_subnet
    {% endcodeblock  %}

Make sure to check out the visualisation of our newly created network topology in Horizon, it's amazing.

## Spinning up a VM

There's no point in installing Openstack just for the sake of it. Our final step would be to create a working virtual machine that would be able to connect to Internet. 

1. Download a test linux image

    {% codeblock lang:bash   %}
    curl http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img | glance \
    image-create \--name='cirros image' \
    \--visibility=public \
    \--container-format=bare \
    \--disk-format=qcow2
    {% endcodeblock  %}

2. From Horizon's home page navigate to Project -> Compute -> Images. 

3. Click on `Launch Instance` and give the new VM a name. 

4. Make sure it's attached to `private_network` under the Networking tab. 

5. Less then a minute later the status should change to `Active` and you can navigate to VM's console by clicking on its name and going to `Console` tab. 

6. Login using the default credentials (**cirros/cubswin:)**) and verify Internet access by pinging google.com.

Congratulations, we have successfully created a VM running inside a KVM inside a KVM inside a VMWare Workstation inside Windows!

## What to expect next

Unlike my other post series, I don't have a clear goal at this stage so I guess I'll continue playing around with different underlays for multi-node Openstack and then move on to various SDN solutions available like OpenDayLight and OpenContrail. Unless I lose interest half way through, which happened in the past. But until that happens, stay tuned for more. 

[rdo-home]: https://www.rdoproject.org
[rdo-quickstart]: https://www.rdoproject.org/install/quickstart/
[unl-vnc]: http://www.unetlab.com/2015/03/url-telnet-ssh-vnc-integration-on-windows/
[os-kvm-req]: http://docs.openstack.org/liberty/config-reference/content/kvm.html
[unl-upgrade]: http://www.unetlab.com/2014/11/upgrade-unetlab-installation/
[unl-download]: http://www.unetlab.com/download/
[centos-minimal]: http://isoredirect.centos.org/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-1511.iso
[initram-rebuild-1]: https://wiki.centos.org/TipsAndTricks/CreateNewInitrd
[initram-rebuild-3]: http://forums.fedoraforum.org/showthread.php?t=288020
[initram-rebuild-2]: http://advancelinux.blogspot.com.au/2013/06/how-to-rebuild-initrd-or-initramfs-in.html
[ravello-link]: https://www.ravellosystems.com/technology/hvx
[os-arch]: http://docs.openstack.org/openstack-ops/content/example_architecture.html
[os-float-range]: https://www.rdoproject.org/networking/difference-between-floating-ip-and-private-ip/
[rdo-ext-net]: https://www.rdoproject.org/networking/neutron-with-existing-external-network/