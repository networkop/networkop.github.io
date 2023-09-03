+++
title = "Linux Networking - Source IP address selection"
date = 2023-09-02T00:00:00Z
categories = ["howto"]
tags = ["linux", "networking"]
summary = "Brief notes about Linux source IP selection and RTA_PREFSRC"
description = "Source IP selection and RTA_PREFSRC"
+++

Any network device, be it a transit router or a host, usually has multiple IP addresses assigned to its interfaces. One of the first things we learn as network engineers is how to determine which IP address is used for the locally-sourced traffic. However, the default scenario can be changed in a couple of different ways and this post is a brief documentation of the available options.

## The Default Scenario

Whenever a local application decides to connect to a remote network endpoint, it creates a network socket, providing a minimal amount of details required to build and send a network packet. Most often, this information includes a destination IP and port number as you can see from the following abbreviated output:

```
$ strace -e trace=network curl http://example.com
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 6
setsockopt(6, SOL_TCP, TCP_NODELAY, [1], 4) = 0
setsockopt(6, SOL_SOCKET, SO_KEEPALIVE, [1], 4) = 0
setsockopt(6, SOL_TCP, TCP_KEEPIDLE, [60], 4) = 0
setsockopt(6, SOL_TCP, TCP_KEEPINTVL, [60], 4) = 0
connect(6, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("93.184.216.34")}, 16)
```

While this output does not show the DNS resolution part (due to [`getaddrinfo()`](https://man7.org/linux/man-pages/man3/getaddrinfo.3.html) not being a syscall), we can see that the only user-specific input information provided by an application (`curl`) in the [`connect()`](https://beej.us/guide/bgnet/html/#connect) syscall are the remote socket port `sin_port` and IP address `sin_adddr`. 

What happens next is what we all learned to expect from any operating system, not just Linux:

1. Destination IP is looked up in the local routing table.
2. The resulting route is used to determine the egress interface.
3. The IP of that interface is assigned as the source address for the TCP socket.

This is a sane default that picks an IP address that is most likely to reach the destination, since it's assigned to an egress interface.


## User-provided IP

In some scenarios, when multiple local IPs are reachable outside of the host, users may want to override the default behaviour. A very common use case is to specify an IP address (or interface name) as the traffic source. The following `strace` output looks exactly the same as above, with one notable exception: 


```
$ strace -e trace=network curl --interface lo http://example.com
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 5
setsockopt(5, SOL_TCP, TCP_NODELAY, [1], 4) = 0
setsockopt(5, SOL_SOCKET, SO_KEEPALIVE, [1], 4) = 0
setsockopt(5, SOL_TCP, TCP_KEEPIDLE, [60], 4) = 0
setsockopt(5, SOL_TCP, TCP_KEEPINTVL, [60], 4) = 0
setsockopt(5, SOL_SOCKET, SO_BINDTODEVICE, "lo\0", 3) = 0
connect(5, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("93.184.216.34")}, 16)
```

The [`setsockopt()`](https://linux.die.net/man/2/setsockopt) syscall allows clients to bind to a specific interface name using the `SO_BINDTODEVICE` option. 

Another alternative would be [`bind()`](https://beej.us/guide/bgnet/html/#bind) the client socket to a specific IP address (`192.0.2.2` is one of the IPs on `lo` interface), which is what `curl` does in the following case:

```
$ strace -e trace=network curl --interface 192.0.2.2 http://example.com
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 5
setsockopt(5, SOL_TCP, TCP_NODELAY, [1], 4) = 0
setsockopt(5, SOL_SOCKET, SO_KEEPALIVE, [1], 4) = 0
setsockopt(5, SOL_TCP, TCP_KEEPIDLE, [60], 4) = 0
setsockopt(5, SOL_TCP, TCP_KEEPINTVL, [60], 4) = 0
setsockopt(5, SOL_SOCKET, SO_BINDTODEVICE, "192.0.2.2\0", 10) = -1 ENODEV (No such device)
bind(5, {sa_family=AF_INET, sin_port=htons(0), sin_addr=inet_addr("192.0.2.2")}, 16) = 0
connect(5, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("93.184.216.34")}, 16)
```

The problem with the above options is that they are application-specific and, thus, require explicit user configuration. While this may work for a small number of applications, in some scenarios it may be easier to have a global setting that would influence this behaviour.

## Netlink Route Source IP

Another available option, that is frequently used on L3 multi-homed network hosts, is the rtnetlink's `src` option or [`RTA_PREFSRC`](https://man7.org/linux/man-pages/man7/rtnetlink.7.html). Continuing from the previous example, let's add a static route for the `example.com` and specify the `src` option with the loopback IP:

```
$ ip route add 93.184.216.34 via 172.20.20.1 src 192.0.2.2
$ ip route get 93.184.216.34
93.184.216.34 via 172.20.20.1 dev eth0 src 192.0.2.2 uid 0
```

Now we can re-run the original `curl` command without specifying the source IP:

```
$ tcpdump -enni eth0 host 93.184.216.34 &
$ strace -e trace=network curl http://example.com
...
connect(6, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("93.184.216.34")}, 16)
14:19:00.970631 IP 192.0.2.2.33068 > 93.184.216.34.80: Flags [S]
```

The resulting packet source IP has been changed by the kernel to the IP specified in the `ip route add` command above. This option can also be configured by an IP routing daemon, for example, FRR's route-map [`set src`](https://docs.frrouting.org/en/stable-9.0/zebra.html#clicmd-set-src-ADDRESS) command or Bird's [`krt_prefsrc`](https://bird.network.cz/?get_doc&v=20&f=bird-6.html) configuration option.

