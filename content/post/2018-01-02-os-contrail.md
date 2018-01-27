+++
title = "OpenStack SDN - OpenContrail With BGP VPN"
date = 2018-01-02T00:00:00Z
categories = ["SDN"]
url = "/blog/2018/01/02/os-contrail/"
tags = ["OpenStack-SDN", "Contrail"]
summary = "In this post I'll show how to build a dockerized OpenStack and OpenContrail lab, integrate it with Juniper MX80 DC-GW and demonstrate one of Contrail's most interesting and unique features called BGP-as-a-Service"
+++


Continuing on the trend started in my [previous post about OpenDaylight][odl-post], I'll move on to the next open-source product that uses BGP VPNs for optimal North-South traffic forwarding. OpenContrail is one of the most popular SDN solutions for OpenStack. It was one of the first hybrid SDN solutions, offering both pure overlay and overlay/underlay integration. It is the default SDN platform of choice for Mirantis Cloud Platform, it has multiple large-scale deployments in companies like Workday and AT&T. I, personally, don't have any production experience with OpenContrail, however my impression, based on what I've heard and seen in the last 2-3 years that I've been following Telco SDN space, is that OpenContrail is the most mature SDN platform for Telco NFVs not least because of its unique feature set.

During the time of production deployment at AT&T, Contrail has added a lot of features required by Telco NFVs like QoS, VLAN trunking and BGP-as-a-service. My first acquaintance with BGPaaS took place when I started working on Telco DCs and I remember being genuinely shocked when I first saw the requirement for dynamic routing exchange with VNFs. To me this seemed to break one of the main rules of cloud networking - a VM is not to have any knowledge or interaction with the underlay. I gradually went though all stages of grief, all the way to acceptance and although it still feels "wrong" now, I can at least understand why it's needed and what are the pros/cons of different BGPaaS solutions. 

# BGP-as-a-Service

There's a certain range of VNFs that may require to advertise a set of IP addresses into the existing VPNs inside Telco network. The most notable example is PGW inside EPC. I won't pretend to be an expert in this field, but based on my limited understanding PGW needs to advertise IP networks into various customer VPNs, for example to connect private APNs to existing customer L3VPNs. Obviously, when this kind of network function gets virtualised, it still retains this requirement which now needs to be fulfilled by DC SDN. 

This requirement catches a lot of big SDN vendors off guard and the best they come up with is connecting those VNFs, through VLANs, directly to underlay TOR switches. Although this solution is easy to implement, it has an incredible amount of drawbacks since a single VNF can now affect the stability of the whole POD or even the whole DC network. Some VNFs vendors also require BFD to monitor liveliness of those BGP sessions which, in case a L3 boundary is higher than the TOR, may create even a bigger number of issues on a POD spine. 

There's a small range of SDN platforms that run a full routing stack on each compute node (e.g. Cumulus, Calico). These solutions are the best fit for this kind of scenarios since they allow BGP sessions to be established over a single hop (VNF <-> virtual switch). However they represent a small fraction of total SDN solutions space with majority of vendors implementing a much simpler OpenFlow or XMPP-based flow push model. 

OpenContrail, as far as I know, is the only SDN controller that doesn't run a full routing stack on compute nodes but still fulfills this requirement in a very elegant way. When [BGPaaS][bgpaas] is enabled for a particular VM's interface, controller programs vRouter to proxy BGP TCP connections coming to virtual network's default gateway IP and forward them to the controller. This way VNF thinks it peers with a next hop IP, however all BGP state and path computations still happen on the controller.

The diagram below depicts a sample implementation of BGPaaS using OpenContrail. VNF is connected to a vRouter using a dot1Q trunk interface (to allow multiple VRFs over a single vEth link). Each VRF has its own BGPaaS session setup to advertise network ranges (NET1-3) into customer VPNs. These BGP sessions get proxied to the controller which injects those prefixes into their respective VPNs. These updates are then sent to DC gateways using either a VPNv4/6 or EVPN and the traffic is forwarded through DC underlay with VPN segregation preserved by either an MPLS tag (for MPLSoGRE or MPLSoUDL encapsulation) or a VXLAN VNI.

![](/img/contrail-bgpaas.png)

Now let me briefly go over the lab that I've built to showcase the BGPaaS and DC-GW integration features.

# Lab setup overview

OpenContrail follows a familiar pattern of DC SDN architecture with central controller orchestrating the work of multiple virtual switches. In case of OpenContrail, these switches are called vRouters and they communicate with controller using XMPP-based extension of BGP as described in [this RFC draft][bgp-xmpp]. A very detailed description of its internal architecture is available on [OpenContrail's website][contrail-arch] so it would be pointless to repeat all of this information here. That's why I'll concentrate on how to get things done rather then on the architectural aspects. However to get things started, I always like to have a clear picture of what I'm trying to achieve. The below diagram depicts a high-level architecture of my lab setup. Although OpenContrail supports BGP VPNv4/6 with multiple dataplane encapsulations, in this post I'll use EVPN as the only control plane protocol to communicate with MX80 and use VXLAN encapsulation in the dataplane.

![](/img/contrail-lab.png)

EVPN as a DC-GW integration protocol is relatively new to OpenContrail and comes with a few limitations. One of them is the absence of EVPN type-5 routes, which means I can't use it in the same way I did in [OpenDaylight's case][odl-post]. Instead I'll demonstrate a DC-GW IRB scenario, which extends the existing virtual network to a DC-GW and makes IRB/SVI interface on that DC-GW act as a default gateway for this network. This is a very common scenario for L2 DCI and active-active DC deployment models. To demonstrate this scenario I'm going to setup a single OpenStack virtual network with a couple of VMs whose gateway will reside on MX80. Since I only have a single OpenStack instance and a single MX80, I'll setup one half of L2 DCI and setup a mutual redistribution to make our overlay network reachable from MX80's global routing table. 

![](/img/contrail-overlay.png)


# All-in-one VM setup

Physically, my lab will consist of a single hypervisor running an all-in-one VM with [kolla-openstack][kolla-openstack] and [kolla-contrail][kolla-contrail] and a physical Juniper MX80 playing the role of a DC-GW. 

![](/img/contrail-setup.png)

OpenContrail's [kolla github page][kolla-contrail] contains a set of instructions to setup the environment. As usual, I have automated all of these steps which can be setup from a hypervisor with the following commands:

```
git clone https://github.com/networkop/kolla-odl-bgpvpn && cd kolla-odl-bgpvpn
./1-create.sh do 
./2-contrail.sh do
```

# OpenStack setup

Once installation is complete and all docker containers are up and running, we can setup the OpenStack side of our test environment. The script below will do the following:

1. Download cirros and CumulusVX images and upload them to Glance
2. Create a virtual network
3. Update security rules to allow inbound ICMP and SSH connections
4. Create a pair of VMs - one based on cirros and one based on CumulusVX image

```
curl -L -o ./cirros http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img
curl -L -o ./cumulusVX http://cumulusfiles.s3.amazonaws.com/cumulus-linux-3.5.0-vx-amd64.qcow2

openstack image create --disk-format qcow2 --container-format bare --public \
--property os_type=linux --file ./cirros cirros
rm ./cirros

openstack image create --disk-format qcow2 --container-format bare --public \
--property os_type=linux --file ./cumulusVX cumulus
rm ./cumulusVX

openstack network create --provider-network-type vxlan irb-net

openstack subnet create --subnet-range 10.0.100.160/27 --network irb-net \
      --host-route destination=0.0.0.0/0,gateway=10.0.100.190 \
      --gateway 10.0.100.161 --dns-nameserver 8.8.8.8 irb-subnet

openstack flavor create --id 1 --ram 256 --disk 1 --vcpus 1 m1.nano
openstack flavor create --id 2 --ram 512 --disk 10 --vcpus 1 m1.tiny

ADMIN_PROJECT_ID=$(openstack project show 'admin' -f value -c id)
ADMIN_SEC_GROUP=$(openstack security group list --project ${ADMIN_PROJECT_ID} | awk '/ default / {print $2}')
openstack security group rule create --ingress --ethertype IPv4 \
    --protocol icmp ${ADMIN_SEC_GROUP}
openstack security group rule create --ingress --ethertype IPv4 \
    --protocol tcp --dst-port 22 ${ADMIN_SEC_GROUP}

openstack server create --image cirros --flavor m1.nano --net irb-net VM1
openstack server create --image cumulus --flavor m1.tiny --net irb-net VR1
```

The only thing worth noting in the above script is that a default gateway `10.0.100.161` gets overridden by a default host route pointing to `10.0.100.190`. Normally, to demonstrate DC-GW IRB scenario, I would have setup a gateway-less L2 only subnet, however in that case I wouldn't have been able to demonstrate BGPaaS on the same network, since this feature relies on having a gateway IP setup (which later acts as a BGP session termination endpoint). So instead of setting up two separate networks I've decided to implement this hack to minimise the required configuration.

# EVPN integration with MX80

DC-GW integration procedure is very simple and requires only a few simple steps:

1. Make sure VXLAN VNI is matched on both ends
2. Configure import/export route targets
3. Setup BGP peering with DC-GW

All of these steps can be done very easily through OpenContrail's GUI. However as I've mentioned before, I always prefer to use API when I have a chance and in this case I even have a python library for OpenContrail's REST API available on Juniper's [github page](https://github.com/Juniper/contrail-python-api), which I'm going to use below to implement the above three steps.


## Configuration

Before we can begin working with OpenContrail's API, we need to authenticate with the controller and get a REST API connection handler.

```python
import pycontrail.client as client
CONTRAIL_API = 'http://10.0.100.140:8082'
AUTH_URL = 'http://10.0.100.140:5000/v2.0'
AUTH_PARAMS = {
    'type': 'keystone',
    'username': 'admin',
    'password': 'mypassword',
    'tenant_name': 'admin',
    'auth_url': AUTH_URL
}
conn = client.Client(url=CONTRAIL_API,auth_params=AUTH_PARAMS)
```

The first thing I'm going to do is override the default VNI setup by OpenContrail for `irb-net` to a pre-defined value of `5001`. To do that I first need to get a handler for `irb-net` object and extract the `virtual_network_properties` object containing a `vxlan_network_identifier` property. Once it's overridden, I just need to update the parent `irb-net` object to apply the change to the running configuration on the controller.

```python
irb_net = conn.virtual_network_read(fq_name = [ 'default-domain', 'admin' ,'irb-net'] )
vni_props=irb_net.get_virtual_network_properties()
vni_props.set_vxlan_network_identifier(5001)
irb_net.set_virtual_network_properties(vni_props)
conn.virtual_network_update(irb_net)
```

The next thing I need to do is explicitly set the import/export route-target properties for the `irb-net` object. This will require a new `RouteTargetList` object which then gets referenced by a `route_target_list` property of the `irb-net` object.

```python
from pycontrail import types as t
new_rtl = t.RouteTargetList(['target:200:200'])
irb_net.set_route_target_list(new_rtl)
conn.virtual_network_update(irb_net)
```

The final step is setting up a peering with MX80. The main object that needs to be created is `BgpRouter`, which contains a pointer to BGP session parameters object with session-specific values like ASN and remote peer IP. BGP router is defined in a global context (default domain and default project) which will make it available to all configured virtual networks.

```python
from pycontrail import types as t
ctx = ['default-domain', 'default-project', 'ip-fabric', '__default__']
af = t.AddressFamilies(family=['inet-vpn', 'e-vpn'])
bgp_params = t.BgpRouterParams(vendor='Juniper', \
                               autonomous_system=65411, \
                               address='10.0.101.15', \
                               address_families=af)
vrf = conn.routing_instance_read(fq_name = ctx)
bgp_router = t.BgpRouter(name='MX80', display_name='MX80', \
                         bgp_router_parameters=bgp_params,
                         parent_obj=vrf)
contrail = conn.bgp_router_read(fq_name = ctx + ['controller-1'])
bgp_router.set_bgp_router(contrail,t.BgpPeeringAttributes())
conn.bgp_router_create(bgp_router)
```

For the sake of brevity, I will not cover MX80's configuration in details and simply include it here for reference with some minor explanatory comments. 

```
# Interface and global settings configuration
set interfaces irb unit 5001 family inet address 10.0.100.190/27
set interfaces lo0 unit 0 family inet address 10.0.101.15/32
set routing-options router-id 10.0.101.15
set routing-options autonomous-system 65411

# Setup BGP peering with OpenContrail
set protocols bgp group CONTRAIL multihop
set protocols bgp group CONTRAIL local-address 10.0.101.15
set protocols bgp group CONTRAIL family inet-vpn unicast
set protocols bgp group CONTRAIL family evpn signaling
set protocols bgp group CONTRAIL peer-as 64512
set protocols bgp group CONTRAIL neighbor 10.0.100.140

# Setup EVPN instance type with IRB interface and matching RT and VNI
set routing-instances EVPN-L2-IRB vtep-source-interface lo0.0
set routing-instances EVPN-L2-IRB instance-type evpn
set routing-instances EVPN-L2-IRB vlan-id 501
set routing-instances EVPN-L2-IRB routing-interface irb.5001
set routing-instances EVPN-L2-IRB vxlan vni 5001
set routing-instances EVPN-L2-IRB route-distinguisher 200:200
set routing-instances EVPN-L2-IRB vrf-target target:200:200
set routing-instances EVPN-L2-IRB protocols evpn encapsulation vxlan

# Setup VRF instance with IRB interface
set routing-instances EVPN-L3-IRB instance-type vrf
set routing-instances EVPN-L3-IRB interface irb.5001
set routing-instances EVPN-L3-IRB route-distinguisher 201:200
set routing-instances EVPN-L3-IRB vrf-target target:200:200

# Setup route redistribution between EVPN and Global VRFs
set routing-options rib-groups CONTRAIL-TO-GLOBAL import-rib EVPN-L3-IRB.inet.0
set routing-options rib-groups CONTRAIL-TO-GLOBAL import-rib inet.0
set routing-options rib-groups GLOBAL-TO-CONTRAIL import-rib inet.0
set routing-options rib-groups GLOBAL-TO-CONTRAIL import-rib EVPN-L3-IRB.inet.0
set routing-options interface-routes rib-group inet CONTRAIL-TO-GLOBAL
set routing-instances EVPN-L3-IRB routing-options interface-routes rib-group inet CONTRAIL-TO-GLOBAL
set protocols bgp group EXTERNAL-BGP family inet unicast rib-group GLOBAL-TO-CONTRAIL
```


## Verification

The easiest way to verify that BGP peering has been established is to query OpenContrail's introspection API:

```
$ curl  -s http://10.0.100.140:8083/Snh_BgpNeighborReq?ip_address=10.0.101.15 | \
  xmllint --xpath '/BgpNeighborListResp/neighbors[1]/list/BgpNeighborResp/state' -
<state type="string" identifier="8">Established</state>
```

Datapath verification can be done from either side, in this case I'm showing a ping from MX80's global VRF towards one of the OpenStack VMs:

```
admin@MX80> ping 10.0.100.164 count 2 
PING 10.0.100.164 (10.0.100.164): 56 data bytes
64 bytes from 10.0.100.164: icmp_seq=0 ttl=64 time=3.836 ms
64 bytes from 10.0.100.164: icmp_seq=1 ttl=64 time=3.907 ms

--- 10.0.100.164 ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max/stddev = 3.836/3.872/3.907/0.035 ms
```

# BGP-as-a-Service 

To keep things simple I will not use multiple dot1Q interfaces and setup a BGP peering with CumulusVX over a normal, non-trunk interface. From CumulusVX I will inject a loopback IP `1.1.1.1/32` into the `irb-net` network. Since REST API python library I've used above is two major releases behind the current version of OpenContrail, it cannot be used to setup BGPaaS feature. Instead I will demonstrate how to use REST API directly from the command line of all-in-one VM using cURL.

## Configuration

In order to start working with OpenContrail's API, I first need to obtain an authentication token from OpenStack's keystone. With that token I can now query the list of IPs assigned to all OpenStack instances and pick the one assigned to CumulusVX. I need the UUID of that particular IP address in order to extract the ID of the VM interface this IP is assigned to.

```
source /etc/kolla/admin-openrc.sh 
TOKEN=$(openstack token issue -f value -c id)
CONTRAIL_AUTH="X-AUTH-TOKEN: $TOKEN"
CTYPE="Content-Type: application/json; charset=UTF-8"
curl -H "$CONTRAIL_AUTH" http://10.0.100.140:8082/instance-ips | jq
VMI_ID=$(curl -H "$CONTRAIL_AUTH" http://10.0.100.140:8082/instance-ip/2e7987be-3f53-4296-905a-0c64793307a9 | \
         jq '.["instance-ip"] .virtual_machine_interface_refs[0].uuid')
```

With VM interface ID saved in a `VMI_ID` variable I can create a BGPaaS service and link it to that particular VM interface.

```
cat << EOF > ./bgpaas.json
{
    "bgp-as-a-service":
    {
        "fq_name": ["default-domain", "admin", "cumulusVX-bgp" ],
        "autonomous_system": 321,
        "bgpaas_session_attributes": {
            "address_families": {"family": ["inet"] }
            },
        "parent_type": "project",
        "virtual_machine_interface_refs": [{
            "attr": null,
            "to": ["default-domain", "admin", ${VMI_ID}]
            }],
        "bgpaas-shared": false,
        "bgpaas-ip-address": "10.0.100.164"
    }
}
EOF

curl -X POST -H "$CONTRAIL_AUTH" -H "$CTYPE" -d @bgpaas.json http://10.0.100.140:8082/bgp-as-a-services
```

The final step is setting up a BGP peering on the CumulusVX side. CumulusVX configuration is very simple and self-explanatory. The BGP neighbor IP is the IP of virtual network's default gateway located on local vRouter.

```
!
interface lo
 ip address 1.1.1.1/32
!
router bgp 321
 neighbor 10.0.100.161 remote-as 64512
 !
 address-family ipv4 unicast
  network 1.1.1.1/32
 exit-address-family
!
```

## Verification

Here's where we come across another limitation of EVPN. The loopback prefix `1.1.1.1/32` does not get injected into EVPN address family, however it does show up automatically in the VPNv4 address family which can be verified from the MX80:

```
admin@MX80> show route table bgp.l3vpn.0 hidden 1.1.1.1/32 extensive    

bgp.l3vpn.0: 6 destinations, 6 routes (3 active, 0 holddown, 3 hidden)
10.0.100.140:2:1.1.1.1/32 (1 entry, 0 announced)
         BGP    Preference: 170/-101
                Route Distinguisher: 10.0.100.140:2
                Next hop type: Unusable, Next hop index: 0
                Next-hop reference count: 6
                State: <Hidden Ext ProtectionPath ProtectionCand>
                Local AS: 65411 Peer AS: 64512
                Age: 37:44 
                Validation State: unverified 
                Task: BGP_64512.10.0.100.140
                AS path: 64512 321 I
                Communities: target:200:200 target:64512:8000003 encapsulation:unknown(0x2) encapsulation:mpls-in-udp(0xd) unknown type 8004 value fc00:7a1201 unknown type 8071 value fc00:1389
                Import Accepted
                VPN Label: 31
                Localpref: 100
                Router ID: 10.0.100.140
                Secondary Tables: EVPN-L3-IRB.inet.0
                Indirect next hops: 1
                        Protocol next hop: 10.0.100.140
                        Label operation: Push 31
                        Label TTL action: prop-ttl
                        Load balance label: Label 31: None; 
                        Indirect next hop: 0x0 - INH Session ID: 0x0
```

It's hidden since I haven't configured MPLSoUDP [dynamic tunnels](https://www.juniper.net/documentation/en_US/junos/topics/example/example-next-hop-based-dynamic-mpls-udp-tunnel-configuring.html) on MX80. However this proves that the prefix does get injected into customer VPNs and become available on all devices with the matching import route-target communities.

# Outro
This post concludes Series 2 of my OpenStack SDN saga. I've covered quite an extensive range of topics in my two-part series, however, OpenStack networking landscape is so big, it's simply impossible to cover everything I find interesting. I started writing about OpenStack SDN when I first learned I got a job with Nokia. Back then I knew little about VMware NSX and even less about OpenStack. That's why I started researching topics that I found interesting and branching out into adjacent areas as I went along. Almost 2 years later, looking back I can say I've learned a lot about the internals of SDN in general and hopefully so have my readers. Now I'm leaving Nokia to rediscover my networking roots at Arista. I'll dive into DC networking from a different perspective now and it may be awhile before I accumulate a critical mass of interesting material to start spilling it out in my blog again. I still may come back to OpenStack some day but for now I'm gonna take a little break, maybe do some house keeping (e.g. move my blog from Jekyll to [Hugo](https://gohugo.io/), add TLS support) and enjoy my time being a farther.

[odl-post]: /blog/2017/12/15/os-odl-netvirt/
[kolla-post]: /blog/2017/09/08/os-lab-docker/
[contrail-arch]: http://www.opencontrail.org/opencontrail-architecture-documentation/
[bgp-xmpp]: https://www.ietf.org/archive/id/draft-ietf-l3vpn-end-system-06.txt
[kolla-openstack]: https://docs.openstack.org/kolla/latest/
[kolla-contrail]: https://github.com/Juniper/contrail-docker/wiki/OpenContrail-Kolla
[bgpaas]: https://www.juniper.net/documentation/en_US/contrail3.2/topics/concept/bgp-as-a-service-overview.html
