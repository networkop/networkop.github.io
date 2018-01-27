+++
title = "Windows-Linux File Synchronisation"
date = 2015-06-22T00:00:00Z
categories = ["automation"]
url = "/blog/2015/06/22/dev-file-sync/"
tags = ["DevOps"]
summary = "Synchorinizing files between Windows and Linux"
draft = false
+++

My development environment usually consists of a host machine running Windows and a development Linux "headless" virtual machine. I create and edit 
files in a [Notepad++](https://notepad-plus-plus.org/) text editor and then transfer them over to the Linux VM. Until recently I've been using a hypervisor-enabled "shared" folder. However, Windows file system emulators in Linux do not support symbolic links
and therefore breaks a lot of applications that rely on them. This prompted me to start looking for a new way to sync my files. That's how I came across this new amazing
file syncing app called [Syncthing](https://syncthing.net/). Why is it amazing?

* It uses peer-to-peer architecture. User traffic is not uploaded to a centralised server and is transferred directly between peers.
* It is open-source. It doesn't use any proprietary syncing protocols like BTSync.
* As the result of open-source nature it has big community support with clients, wrappers and extension available for any major platform.
* It is secure. All transfers are TLS-encrypted.
* It's simple to use. Windows version installs like any other Windows app, Linux version, like any other Linux app, will take a little tinkering.
* It's written in Golang, an extremely popular language amongst professional programmers and surely these guys can't be mistaken.


# Windows installation

Windows installation is extremely easy. I use a package called [SyncTrayzor](https://github.com/canton7/SyncTrayzor/releases) which contains the application itself, serves as a tray utility wrapper and also implements "inotify" which allows for file on-change synchronisation (BGP ip next-hop tracking anyone?)

# Ubuntu installation

Ubuntu package installation is an easy 4-step process

1 - Syncthing installation:

``` bash
# Add the release PGP keys:
$ curl -s https://syncthing.net/release-key.txt | sudo apt-key add -

# Add the "release" channel to your APT sources:
$ echo deb http://apt.syncthing.net/ Syncthing release | sudo tee /etc/apt/sources.list.d/syncthing-release.list

# Update and install syncthing:
$ sudo apt-get update
$ sudo apt-get install syncthing
```

2 - Inotify installation:

``` bash 
# Choose the latest release for your platform
$ wget https://github.com/syncthing/syncthing-inotify/releases/download/v0.6.5/syncthing-inotify-linux-amd64-v0.6.5.tar.gz

# Unpack and copy inotify to the same directory as the main app
$ tar xvf syncthing-inotify-linux-amd64-v0.6.5.tar.gz
$ which syncthing
/usr/bin/syncthing
$ mv syncthing-inotify /usr/bin/
```

3 - Configure upstart script to control Syncthing 

``` bash
# Create a file for main service
$ echo "start on starting network-services
stop on stopping network-services
env STNORESTART=yes
respawn
env HOME=/root
exec /usr/bin/syncthing" >> /etc/init/syncthing.conf

# Do the same for inotify
$ echo "start on starting syncthing
stop on stopping syncthing
env STNORESTART=yes
respawn
env HOME=/root
exec /usr/bin/syncthing-inotify" >> /etc/init/syncthing-inotify.conf

# start both services 
$ service syncthing start && service syncthing-inotify start
```

4 - Update Syncthing configuration file 

``` bash
# Update the default Sync directory to match your dev environment
# using the correct device IDs
$ head -n 10 ~/.config/syncthing/config.xml
<configuration version="10">
    <folder id="ansible-blog" path="/root/tdd_ansible" ro="false" rescanIntervalS="60" ignorePerms="false" autoNormalize="false">
        <device id="MY-DEVICE-ID"></device>
        <device id="PEER-DEVICE-ID"></device>
        <versioning></versioning>
        <copiers>0</copiers>
        <pullers>0</pullers>
        <hashers>0</hashers>
        <order>random</order>
    </folder>

# Add peer device's ID to the same file
$ cat ~/.config/syncthing/config.xml
...
    <device id="PEER-DEVICE-ID" name="NETOP-DESKTOP" compression="metadata" introducer="false">
        <address>dynamic</address>
    </device>
...

# restart both syncthing services
$ service syncthing restart && service syncthing-inotify restart
```

Finally, Windows service can be configured similarly via Syncthing Tray. End result is that files are replicated between the two folders with a delay of just a few seconds
``` bash
$ touch /root/tdd_ansible/testfile
$ tail -n 3 /var/log/upstart/syncthing*
==> /var/log/upstart/syncthing-inotify.log <==
[OK] 01:45:04 Watching ansible-blog: /root/tdd_ansible
[OK] 01:45:04 Syncthing is indexing change in ansible-blog: [.stfolder]
[OK] 01:46:16 Syncthing is indexing change in ansible-blog: [testfile]

==> /var/log/upstart/syncthing.log <==
[TLARX] 01:41:25 INFO: Established secure connection to DEVICE-ID at 192.168.X.Y:22000-192.168.X.Z:53007
[TLARX] 01:41:25 INFO: Device DEVICE-ID client is "syncthing v0.11.10"
[TLARX] 01:41:25 INFO: Device DEVICE-ID name is "NETOP-DESKTOP"
```

* * *

How can you not love open-source after that?
