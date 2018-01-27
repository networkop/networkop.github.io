+++
title = "OpenStack SDN - OpenDaylight With BGP VPN"
date = 2017-12-15T00:00:00Z
categories = ["SDN"]
url = "/blog/2017/12/15/os-odl-netvirt/"
tags = ["OpenStack-SDN", "ODL"]
summary = "In this post I'll demonstrate how to build a simple OpenStack lab with OpenDaylight-managed virtual networking and integrate it with a Cisco IOS-XE data centre gateway using EVPN"
+++

For the last 5 years OpenStack has been the training ground for a lot of emerging DC SDN solutions. OpenStack integration use case was one of the most compelling and easiest to implement thanks to the limited and suboptimal implementation of the native networking stack. Today, in 2017, features like [L2 population][l2-pop-post], local [ARP responder][arp-post], [L2 gateway integration][l2gw-post], [distributed routing][dvr-post] and [service function chaining][sfc-post] have all become available in vanilla OpenStack and don't require a proprietary SDN controller anymore. Admittedly, some of the features are still not (and may never be) implemented in the most optimal way (e.g. DVR). This is where new opensource SDN controllers, the likes of [OVN][ovn-post] and [Dragonflow][dragonflow-start], step in to provide scalable, elegant and efficient implementation of these advanced networking features. However one major feature still remains outside of the scope of a lot of these new opensource SDN projects, and that is data centre gateway (DC-GW) integration. Let me start by explain why you would need this feature in the first place.


# Optimal forwarding of North-South traffic

OpenStack Neutron and VMware NSX, both being pure software solutions, rely on a special type of node to forward traffic between VMs and hosts outside of the data centre. This node acts as a L2/L3 gateway for all North-South traffic and is often implemented as either a VM or a network namespace. This kind of solution gives software developers greater independence from the underlying networking infrastructure which makes it easier for them to innovate and introduce new features.

![](/img/sdn-ns.png)

However, from the traffic forwarding point of view, having a gateway/network node is not a good solution at all. There is no technological reason for a packet to have to go through this node when after all it ends up on a DC-GW anyway. In fact, this solution introduces additional complexity which needs to be properly managed (e.g. designed, configured and troubleshooted) and a potential bottleneck for high-throughput traffic flows. 


It's clear that the most optimal way to forward traffic is directly from a compute node to a DC-GW. The only question is how can this optimal forwarding be achieved? SDN controller needs to be able to exchange reachability information with DC-GW using a common protocol understood by most of the existing routing stacks. One such protocol, becoming very common in DC environments, is BGP, which has two address families we can potentially use:

1. VPNv4/6 will allow routes to be exchanged and the dataplance to use MPLSoGRE encapsulation. This should be considered a "legacy" approach since for a very long time DC-GWs did not have the VXLAN ecap/decap capabilities.
2. EVPN with VXLAN-based overlays. EVPN makes it possible to exchange both L2 and L3 information under the same AF, which means we have the flexibility of doing not only a L3 WAN integration, but also a L2 data centre interconnect with just a single protocol. 
 
In OpenStack specifically, BGPVPN project was created to provide a pluggable driver framework for 3rd party BGP implementations. Apart from a reference BaGPipe driver (BaGPipe is an ExaBGP fork with lightweight implementation of BGP VPNs), which relies on a default `openvswitch` ML2 mechanism driver, only Nuage, OpenDaylight and OpenContrail have contributed their drivers to this project. In this post I will focus on OpenDaylight and show how to install containerised OpenStack with OpenDaylight and integrate it with Cisco CSR using EVPN.

# OpenDaylight integration with OpenStack

Historically, OpenDaylight has had multiple projects implementing custom OpenStack networking drivers:

* **VTN** (Virtual Tenant Networking) - spearheaded by NEC was the first project to provide OpenStack networking implementation
* **GBP** (Group Based Policy) - a project led by Cisco, one of the first (if not THE first) commercial implementation of Intent-based networking
* **NetVirt** - currently a default Neutron plugin from ODL, developed jointly by Brocade (RIP), RedHat, Ericsson, Intel and many others.

NetVirt provides several common Neutron services including L2 and L3 forwarding, ACL and NAT, as well as advanced services like L2 gateway, QoS and SFC. To do that it assumes full control over an OVS switch inside each compute node and implements the above services inside a single `br-int` OVS bridge. L2/L3 forwarding tables are built based on tenant IP/MAC addresses that have been allocated by Neutron and the current network topology. For high-level overview of NetVirt's forwarding pipeline you can refer to [this document][netvirt-pipeline].

It helps to think of an ODL-managed OpenStack as a big chassis switch. NetVirt plays the role of a supervisor by managing control plane and compiling RIB based on the information received from Neutron. Each compute node running an OVS is a linecard with VMs connected to its ports. Unlike the distributed architecture of [OVN][ovn-post] and Dragonflow, compute nodes do not contain any control plane elements and each OVS gets its FIB programmed directly by the supervisor. DC underlay is a backplane, interconnecting all linecards and a supervisor.

![](/img/odl-netvirt-chassis.png)

# OpenDaylight BGP VPN service architecture

In order to provide BGP VPN functionality, NetVirt employs the use of three service components:

* **FIB service** - maintains L2/L3 forwarding tables and reacts to topology changes
* **BGP manager** - provides a translation of information sent to and received from an external BGP stack (Quagga BGP)
* **VPN Manager** - ties together the above two components, creates VRFs and keeps track of RD/RT values 

In order to exchange BGP updates with external DC-GW, NetVirt requires a BGP stack with EVPN and VPNV4/6 capabilities. Ideally, internal ODL BGP stack could have been used for that, however it didn't meet all the performance requirements (injecting/withdrawing thousand of prefixes at the same time). Instead, an external [Quagga fork][6wind-quagga] with EVPN add-ons is connected to BGP manager via a high-speed Apache Thrift interface. This interface defines the [format][thift-def] of data to be exchanged between Quagga (a.k.a QBGP) and NetVirt's BGP Manager in order to do two things:

1. Configure BGP settings like ASN and BGP neighbors
2. Read/Write RIB entries inside QBGP

BGP session is established between QBGP and external DC-GW, however next-hop values installed by NetVirt and advertised by QBGP have IPs of the respective compute nodes, so that traffic is sent directly via the most optimal path. 

![](/img/odl-netvirt.png)

# Demo

Enough of the theory, let's have a look at how to configure a L3VPN between QBGP (advertising ODL's distributed router subnets) and IOS-XE DC-GW using EVPN route type 5 or, more specifically, [Interface-less IP-VRF-to-IP-VRF model][evpn-rt5]:

![](/img/odl-evpn-topo.png )

## Installation

My lab environment is still based on a pair of nested VMs running containerised Kolla OpenStack I've described in my [earlier post][kolla-post]. A few months ago OpenDaylight role has been added to kolla-ansible so now it is possible to install OpenDaylight-intergrated OpenStack automatically. However, there is no option to install QBGP so I had to augment the default [Kolla][kolla-github] and [Kolla-ansible][kolla-ansible-github] repositories to include the QBGP [Dockerfile template][qbgp-dockerfile] and QBGP [ansible role][qbgp-ansible]. So the first step is to download my latest automated installer and make sure `enable_opendaylight` global variable is set to `yes`:

```
git clone https://github.com/networkop/kolla-odl-bgpvpn.git && cd kolla-odl-bgpvpn
mkdir group_vars
echo "enable_opendaylight: \"yes\"" >> group_vars/all.yaml
```

At the time of writing I was relying on a couple of latest bug fixes inside OpenDaylight, so I had to modify the default ODL role to install the latest master-branch ODL build. Make sure the link below is pointing to the latest `zip` file in `0.8.0-SNAPSHOT` directory.

```
cat << EOF >> group_vars/all.yaml
odl_latest_enabled: true
odl_latest_url: https://nexus.opendaylight.org/content/repositories/opendaylight.snapshot/org/opendaylight/integration/netvirt/karaf/0.8.0-SNAPSHOT/karaf-0.8.0-20171106.102232-1767.zip
EOF
```


The next few steps are similar to what I've described in my [Kolla lab post][kolla-post], will create a pair of VMs, build all Kolla containers, push them to a local Docker repo and finally deploy OpenStack using Kolla-ansible playbooks:

```
./1-create.sh do
./2-bootstrap.sh do
./3-build.sh do 
./4-deploy.sh do
```

The final `4-deploy.sh` script will also create a simple `init.sh` script inside the controller VM that can be used to setup a test topology with a single VM connected to a `10.0.0.0/24` subnet:

```
ssh kolla-controller
source /etc/kolla/admin-openrc.sh
./init.sh
```

> Of course, another option to build a lab is to follow the official [Kolla documentation](https://docs.openstack.org/kolla-ansible/latest/user/quickstart.html) to create your own custom test environment.

## Configuration

Assuming the test topology was setup with no issues and a test VM can ping its default gateway `10.0.0.1`, we can start configuring BGP VPNs. Unfortunately, we won't be able to use OpenStack BGPVPN API/CLI, since ODL requires an extra parameter (L3 VNI for symmetric IRB) which is not available in OpenStack BGPVPN API, but we still can configure everything directly through ODL's API. My interface of choice is always REST, since it's easier to build it into a fully programmatic plugin, so even though all of the below steps can be accomplished through karaf console CLI, I'll be using cURL to send and retrieve data from ODL's REST API.

### 1. Source admin credentials and setup ODL's REST variables

```
source /etc/kolla/admin-openrc.sh
export ODL_URL='http://192.168.133.100:8181/restconf'
export CT_JSON="Content-Type: application/json"
```

### 2. Configure local BGP settings and BGP peering with DC-GW

```
cat << EOF > ./bgp-full.json
{
    "bgp": {
        "as-id": {
            "announce-fbit": false,
            "local-as": 100,
            "router-id": "192.168.133.100",
            "stalepath-time": 0
        },
        "logging": {
            "file": "/var/log/bgp_debug.log",
            "level": "errors"
        },
        "neighbors": [
            {
                "address": "192.168.133.50",
                "remote-as": 100,
                "address-families": [
                   {
                     "ebgp:afi": "3",
                     "ebgp:peer-ip": "192.168.133.50",
                     "ebgp:safi": "6"
                   }
                ]
            }
        ]
    }
}
EOF

curl -X PUT -u admin:admin -k -v -H "$CT_JSON"  \
     $ODL_URL/config/ebgp:bgp -d @bgp-full.json
```

### 3. Define L3VPN instance and associate it with OpenStack `admin` tenant

```
TENANT_UUID=$(openstack project show admin -f value -c id | \
            sed 's/\(........\)\(....\)\(....\)\(....\)\(.*\)/\1-\2-\3-\4-\5/')

cat << EOF > ./l3vpn-full.json
{
   "input": {
      "l3vpn":[
         {
            "id":"f503fcb0-3fd9-4dee-8c3a-5034cf707fd9",
            "name":"L3EVPN",
            "route-distinguisher": ["100:100"],
            "export-RT": ["100:100"],
            "import-RT": ["100:100"],
            "l3vni": "5000",
            "tenant-id":"${TENANT_UUID}"
         }
      ]
   }
}
EOF

curl -X POST -u admin:admin -k -v -H "$CT_JSON"  \
      $ODL_URL/operations/neutronvpn:createL3VPN -d @l3vpn-full.json
```

### 4. Inject prefixes into L3VPN by associating the previously created L3VPN with a `demo-router`

```
ROUTER_UUID=$(openstack router show demo-router -f value -c id)

cat << EOF > ./l3vpn-assoc.json
{
  "input":{
     "vpn-id":"f503fcb0-3fd9-4dee-8c3a-5034cf707fd9",
     "router-id":[ "${ROUTER_UUID}" ]
   }
}
EOF

curl -X POST -u admin:admin -k -v -H "$CT_JSON"  \
     $ODL_URL/operations/neutronvpn:associateRouter -d @l3vpn-assoc.json
```

### 5. Configure DC-GW VTEP IP

ODL cannot automatically extract VTEP IP from updates received from DC-GW, so we need to explicitly configure it:

```
cat << EOF > ./tep.json
{
  "input": {
    "destination-ip": "1.1.1.1",
    "tunnel-type": "odl-interface:tunnel-type-vxlan"
  }
}
EOF
curl -X POST -u admin:admin -k -v -H "$CT_JSON"  \
     $ODL_URL/operations/itm-rpc:add-external-tunnel-endpoint -d @tep.json
```

### 6. DC-GW configuration

That is all what needs to be configured on ODL. Although I would consider this to be outside of the scope of the current post, for the sake of completeness I'm including the relevant configuration from the DC-GW:

```
!
vrf definition ODL
 rd 100:100
 route-target export 100:100
 route-target import 100:100
 !        
 address-family ipv4
  route-target export 100:100 stitching
  route-target import 100:100 stitching
 exit-address-family
!
bridge-domain 5000 
 member vni 5000
!
interface Loopback0
 ip address 1.1.1.1 255.255.255.255
!
interface GigabitEthernet1
 ip address 192.168.133.50 255.255.255.0
!
interface nve1
 no ip address
 source-interface Loopback0
 host-reachability protocol bgp
 member vni 5000 vrf ODL
!
interface BDI5000
 vrf forwarding ODL
 ip address 8.8.8.8 255.255.255.0
 encapsulation dot1Q 500
!
router bgp 100
 bgp log-neighbor-changes
 no bgp default ipv4-unicast
 neighbor 192.168.133.100 remote-as 100
 !
 address-family l2vpn evpn
  import vpnv4 unicast
  neighbor 192.168.133.100 activate
 exit-address-family
 !
 address-family ipv4 vrf ODL
  advertise l2vpn evpn
  redistribute connected
 exit-address-family
!
```

For detailed explanation of how EVPN RT5 is configured on Cisco CSR refer to the [following guide][csr-evpn].

## Verification

There are several things that can be checked to verify that the DC-GW integration is working. One of the first steps would be to check if BGP session with CSR is up.
This can be done from the CSR side, however it's also possible to check this from the QBGP side. First we need to get into the QBGP's interactive shell from the controller node:

```
[centos@controller-1 ~]$ sudo docker exec -it quagga /opt/quagga/bin/vtysh
```

From here, we can check that the BGP session has been established:

```
controller-1# sh bgp neighbors 192.168.133.50     
BGP neighbor is 192.168.133.50, remote AS 100, local AS 100, internal link
  BGP version 4, remote router ID 1.1.1.1
  BGP state = Established, up for 00:03:05
<snip>
```

We can also check the contents of EVPN RIB compiled by QBGP

```
controller-1# sh bgp evpn rd 100:100
BGP table version is 0, local router ID is 192.168.133.100
Status codes: s suppressed, d damped, h history, * valid, > best, i - internal
Origin codes: i - IGP, e - EGP, ? - incomplete

   Network          Next Hop            Metric LocPrf Weight Path
Route Distinguisher: as2 100:100
*> [0][fa:16:3e:37:42:d8/48][10.0.0.2/32]
                    192.168.133.100         0          32768 i
*> [0][fa:16:3e:dc:77:65/48][10.0.0.3/32]
                    192.168.133.101         0          32768 i
*>i8.8.8.0/24       1.1.1.1         0     100       0 ?
*> 10.0.0.0/24      192.168.133.100         0          32768 i
```

Finally, we can verify that the prefix `8.8.8.0/24` advertised from DC-GW is being passed by QBGP and accepted by NetVirt's FIB Manager:

```
$ curl -u admin:admin -k -v  $ODL_URL/config/odl-fib:fibEntries/\
  vrfTables/100%3A100/vrfEntry/8.8.8.0%2F24 | python -m json.tool
{
    "vrfEntry": [
        {
            "destPrefix": "8.8.8.0/24",
            "encap-type": "vxlan",
            "gateway_mac_address": "00:1e:49:69:24:bf",
            "l3vni": 5000,
            "origin": "b",
            "route-paths": [
                {
                    "nexthop-address": "1.1.1.1"
                }
            ]
        }
    ]
}
```

The last output confirms that the prefix is being received and accepted by ODL. To do a similar check on CSR side we can run the following command:

```
CSR1k#show bgp l2vpn evpn 
<snip>
     Network          Next Hop            Metric LocPrf Weight Path
Route Distinguisher: 100:100 (default for vrf ODL)
 *>i  [2][100:100][0][48][FA163E3742D8][32][10.0.0.2]/24
                      192.168.133.100          0    100      0 i
 *>i  [2][100:100][0][48][FA163EDC7765][32][10.0.0.3]/24
                      192.168.133.101          0    100      0 i
 *>   [5][100:100][0][24][8.8.8.0]/17
                      0.0.0.0                  0         32768 ?
 *>i  [5][100:100][0][24][10.0.0.0]/17
                      192.168.133.100          0    100      0 i
```

This confirms that the control plane information has been successfully exchanged between NetVirt and Cisco CSR.

> At the time of writing, there was an [open bug](https://git.opendaylight.org/gerrit/#/c/63324/) in ODL master branch that prevented the forwarding entries from being installed in OVS datapath. Once the bug is fixed I will update this post with the dataplance verification, a.k.a ping

# Conclusion

OpenDaylight is a pretty advanced OpenStack SDN platform. Its functionality includes clustering, site-to-site federation (without EVPN) and L2/L3 EVPN DC-GW integration for both IPv4 and IPv6. It is yet another example of how an open-source platform can match even the most advanced proprietary SDN solutions from incumbent vendors. This is all thanks to the companies involved in OpenDaylight development. I also want to say special thanks to Vyshakh Krishnan, Kiran N Upadhyaya and Dayavanti Gopal Kamath from Ericsson for helping me clear up some of the questions I posted on netvirt-dev mailing list.


[sfc-post]: /blog/2017/09/15/os-sfc-skydive/
[kolla-post]: /blog/2017/09/08/os-lab-docker/
[l2-pop-post]: /blog/2016/05/06/neutron-l2pop/
[arp-post]:  /blog/2016/05/06/neutron-l2pop/
[dvr-post]: /blog/2016/10/13/os-dvr/
[ovn-post]: /blog/2016/12/10/ovn-part2/
[dragonflow-start]: https://docs.openstack.org/developer/dragonflow/distributed_dragonflow.html
[bgpvpn]: https://docs.openstack.org/networking-bgpvpn/latest/
[l2gw-post]:/blog/2016/05/21/neutron-l2gw/
[6wind-quagga]: https://github.com/6WIND/quagga/tree/qthrift_mpbgp_evpn
[thift-def]: https://github.com/6WIND/quagga/blob/qthrift_mpbgp_evpn/qthriftd/vpnservice.thrift
[evpn-rt5]: https://tools.ietf.org/html/draft-ietf-bess-evpn-prefix-advertisement-09#section-4.4.1
[kolla-github]: https://github.com/openstack/kolla
[kolla-ansible-github]: https://github.com/openstack/kolla-ansible
[qbgp-dockerfile]: https://github.com/networkop/kolla-odl-bgpvpn/blob/master/roles/kolla_build/templates/quagga-Dockerfile.j2
[qbgp-ansible]: https://github.com/networkop/kolla-odl-bgpvpn/blob/master/roles/kolla_deploy/tasks/create.yml#L90-L120
[csr-evpn]: https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/cether/configuration/xe-16/ce-xe-16-book/evpn-vxlan-l3.html
[netvirt-pipeline]: https://docs.google.com/presentation/d/15h4ZjPxblI5Pz9VWIYnzfyRcQrXYxA1uUoqJsgA53KM/edit#slide=id.g1c73ae9953_2_0
