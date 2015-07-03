---
layout: post
title: "IP address information collection with custom Ansible modules"
date: 2015-07-03
comments: true
sharing: true
footer: true
categories: [ansible, cisco]
description: Writing Ansible modules to parse text
---

Ansible has a very neat feature called "fact gathering", which collects useful information from hosts prior to executing any of the tasks and makes this information available for use within those tasks. Unfortunately, this also relies on Python being available on the remote machine which doesn't work for Cisco IOS. In this post I'll show how to write a simple module which will collect IP address information from remote devices and store it in global variable for future use. I'll also show how to write a module which will convert our human-readable TDD scenarios into YAML structures. As always, full code repository is available on [Github](https://github.com/networkop/simple-cisco-tdd)

<!--more-->

## Cisco IOS IP fact gathering

In order to recognise that a traceroute has traversed a certain device, without relying on DNS, we need to populate a local database mapping IP addresses to their respective devices. The resulting database (or YAML dictionary) needs to be stored in a file so that it can be read and used again by Ansible tasks doing the traceroute verification. In order to make it happen, we need to answer the following questions:

* How to get IP address information from each device?

> The most straight-forward way is to capture the result of running something like `show ip interface brief` and parse the output. The assumption is that all devices are living in a non-overlapping IP address space (however it is possible to modify the examples to be vrf-aware).

* Where to store the information?

> Ideally, we would need a hash-like data structure (e.g. python dictionary) which will return a hostname when given a certain IP address. This data structure needs to be available to all hosts, however most of the variables in Ansible are host-specific. The only way to simulate a global variable in Ansible is to store all data in `group_vars/all.yml` file which is exactly what our module will do.

* How will multiple processes write into a single file at the same time?

> That's where Ansible's concurrency feature bites back. This is a well known computer science problem and the solution to this is to use `mutex`, however that's beyond what Ansible can do. In order to overcome that, I'll make Ansible do the tasks sequentially, which will dramatically slow things down for bigger environments. However, this task only needs to be run once, to collect the data, while all the other tasks can be run in parallel, in separate playbooks.

## Developing Ansible playbook

Our Ansible playbook will need to accomplish the following tasks:

1. Capture the output `show ip interface brief` command
2. Parse the output capture in the previous step
3. Save the output in a `group_vars/all.yml` file

All these tasks will need to be run sequentially on every host from `cisco-devices` group. To get the output from a Cisco device we'll use the `raw` module again. The other two tasks don't require connection to remote device and will be run on a localhost by the virtue of a `delegate_to: 127.0.0.1` option.

{% codeblock lang:yaml ~/tdd_ansible/cisco-ip-collect.yml %}
---
- name: Collect IP address data
  hosts: cisco-devices
  gather_facts: false
  remote_user: cisco
  serial: 1

  tasks:

    - name: capture show ip interface brief
      raw: show ip interface brief | exclude unassigned
      register: siib_text

    - name: parse the output of "show ip interface brief"
      cisco_ip_intf_facts_collect: output_text="{{ siib_text.stdout }}"
      delegate_to: 127.0.0.1

    - name: combine ip address facts and save as a global variable
      cisco_ip_intf_facts_combine:
        ipTable="{{ IPs }}"
        hostname="{{ inventory_hostname }}"
      delegate_to: 127.0.0.1

  tags:
    - collect
{% endcodeblock  %}

## Writing a custom Ansible module

Ansible has an [official guide](http://docs.ansible.com/developing_modules.html) on module development. A typical module will contain a header with license information along with module documentation and usage examples, a `main()` function processing the arguments passed to this module from Ansible and, of course, the actual code that implements module's logic. For the sake of brevity I will omit the header and some of the less important details in the code. 

## Ansible module to parse command output

This ansible module needs to extract IP address and, optionally, interface name from the output of `show ip interface brief` and store it in a python dictionary. The right way to examine the module code is from `main()` function. This function will contain a `module` variable (instance of AnsibleModule) which specifies all the arguments expected by this module and their type (the type will be converted to the appropriate python type). Text parser is implemented with a `SIIBparse` class whose only public method `parse()` will traverse the text line by line looking for interfaces with Line Protocol in `up` state, extract IP address (1st column), interface name (2nd column) and store the result in a python dictionary with IP address as the key and interface name as it's value.

{% codeblock lang:python ~/tdd_ansible/library/cisco_ip_intf_facts_collect.py %}
class SIIBparse(object):

    def __init__(self, module):
        self.output_text = module.params['output_text']
        self.ip2intf = dict()

    def parse(self):
        for line in self.output_text.split("\n"):
            row = line.split()
            if len(row) > 0 and row[-1] == 'up':
                ipAddress = row[1]
                intfName = row[0]
                self.ip2intf[ipAddress] = intfName
        result = {
            "IPs": self.ip2intf
        }
        rc = 0 if len(self.ip2intf) > 0 else 1
        return rc, result

def main():
    module = AnsibleModule(
        argument_spec=dict(
            output_text=dict(required=True, type='str')
        )
    )
    siib = SIIBparse(module)
    rc, result = siib.parse()
    if rc != 0:
        module.fail_json(msg="Failed to parse. Incorrect input.")
    else:
        module.exit_json(changed=False, ansible_facts=result)

# import module snippets
from ansible.module_utils.basic import *
main()
{% endcodeblock  %}

If information passed to the module in the argument was invalid, the module must fail with a meaningful message passed inside a `fail_json` method call. When parsing is complete, our module exits and the resulting data structure is passed back to Ansible variables with `ansible_facts` argument. Now all hosts can access it through variable called `IPs`.


## Ansible module to save IP address information

The task of this module is to get all the information collected inside each hosts' `IPs` variables, combine it with devices' hostnames and save it in the `group_vars/all.yml` file. This module makes use of [Python's yaml library](http://pyyaml.org/wiki/PyYAMLDocumentation). Built-in class `FactUpdater` can read(), update() the contents and write() the global variable file defined in a `FILENAME` variable.

{% codeblock lang:python ~/tdd_ansible/library/cisco_ip_intf_facts_combine.py %}
import yaml 
FILENAME="group_vars/all.yml"

class FactUpdater(object):

    def __init__(self, module):
        self.ip2intf = module.params['ipTable']
        self.hostname = module.params['hostname']
        self.file_content = {'ip2host':{}}

    def read(self):
        try:
            with open(FILENAME, 'r') as fileObj:
                self.file_content = yaml.load(fileObj)
        except:
            # in case there is no file - create it
            open(FILENAME, 'w').close()

    def write(self):
        with open(FILENAME, 'w') as fileObj:
            yaml.safe_dump(self.file_content, fileObj, explicit_start=True, indent=2, allow_unicode=True)


    def update(self):
        if not 'ip2host' in self.file_content:
            self.file_content['ip2host'] = dict()
        for ip in self.ip2intf:
            self.file_content['ip2host'][ip] = [self.hostname, self.ip2intf[ip]]



def main():
    module = AnsibleModule(
        argument_spec=dict(
            ipTable=dict(required=True, type='dict'),
            hostname=dict(required=True, type='str'),
        )
    )
    result = ''
    factUpdater = FactUpdater(module)
    try:
        factUpdater.read()
        factUpdater.update()
        factUpdater.write()
    except IOError as e:
        module.fail_json(msg="Unexpected error: " + str(e))

    module.exit_json(changed=False)

# import module snippets
from ansible.module_utils.basic import *
main()
{% endcodeblock  %}

This module only performs actions on local file and does not provide any output back to Ansible.

## Read and parse TDD scenarios

Finally, since we're modifying Ansible global variable file, it would make sense to also update it with testing scenarios information. Technically, this steps doesn't need to be done in Ansible and could be done simply using Python or Bash scripts, but I'll still show it here to demonstrate two additional Ansible features. The first one is `local_action: module_name` which is a shorthand for specifying `module` with `delegate_to` option (see above). Second feature is `tags`, it allows to specify which play to run in playbook containing many of them. In our case one file `cisco-ip-collect.yml` will have two plays defined and will run both of them by default unless `--tag=scenario` or `--tag=collect` specifies the exact play.

{% codeblock lang:yaml ~/tdd_ansible/cisco-ip-collect.yml %}
- name: Parse and save scenarios
  hosts: localhost
  gather_facts: false

  tasks:

    - name: parse scenario file and save it in group_vars/all.yml
      local_action: cisco_scenarios_convert

  tags:
    - scenario
{% endcodeblock  %}

This play has a single task which runs a single custom module. Before we proceed to the module let's see how a typical testing scenario file looks like.

{% codeblock lang:text ~/tdd_ansible/scenarios/all.txt %}
1. Testing of Primary Link
1.1 From R1 to R3 via R2
1.2 From R1 to R4 via R2, R3
2. Testing of Backup Link
2.1 From R1 to R3 via R4
2.2 From R1 to R2 via R4,R3
{% endcodeblock  %}

The file should be stored in a `scenarios/` directory and should have a name `all.txt`. This file contains a list of scenarios, each with its own name, and a list of test steps that need to be performed to validate a particular scenario. The parser for this file is a custom Python module which opens and reads the contents of `group_vars/all.yml` file, parses the scenarios file with the help of some ugly-looking regular expressions, and, finally, updates and saves the contents of Ansible group variable back to file.

{% codeblock lang:python ~/tdd_ansible/library/cisco_scenarios_convert.py %}
import yaml
import re
SCENARIO_FILE = "scenarios/all.txt"
GROUP_VAR_FILE = "group_vars/all.yml"

class ScenarioParser(object):

    def __init__(self):
        self.rc = 0
        self.storage = dict()
        self.file_content = dict()

    def open(self):
       try:
            with open(GROUP_VAR_FILE, 'r') as fileObj:
                self.file_content = yaml.load(fileObj)
       except:
           open(GROUP_VAR_FILE, 'w').close()

    def read(self):
        scenario_number = 0
        scenario_step   = 0
        scenario_name   = ''
        name_pattern = re.compile(r'^(\d+)\.?\s+(.*)')
        step_pattern = re.compile(r'.*from\s+([\d\w]+)\s+to\s+([\d\w]+)\s+via\s+([\d\w]+,*\s*[\d\w]+)*')
        with open(SCENARIO_FILE, 'r') as fileObj:
            for line in fileObj:
                # ignore commented and empty lines
                if not line.startswith('#') and len(line) > 3:
                    line = line.lower()
                    name_match = name_pattern.match(line)
                    step_match = step_pattern.match(line)
                    if name_match:
                        scenario_number = name_match.group(1)
                        scenario_name   = name_match.group(2)
                        scenario_steps  = [scenario_name, []]
                        self.storage[scenario_number] = scenario_steps
                    elif step_match:
                        from_device = step_match.group(1)
                        to_device = step_match.group(2)
                        via = step_match.group(3)
                        via_devices = [device_name.strip() for device_name in via.split(',')]
                        if not scenario_number == 0 or scenario_name:
                            scenario_steps[1].append([from_device, to_device, via_devices])
                    else:
                        self.rc = 1

    def write(self):
       self.file_content['scenarios'] = self.storage
       if self.rc == 0:
           with open(GROUP_VAR_FILE, 'w+') as fileObj:
               yaml.safe_dump(self.file_content, fileObj, explicit_start=True, indent=3, allow_unicode=True)

def main():
    module = AnsibleModule(argument_spec=dict())
    parser = ScenarioParser()
    parser.open()
    parser.read()
    parser.write()
    if not parser.rc == 0:
        module.fail_json(msg="Failed to parse. Incorrect input.")
    else:
        module.exit_json(changed=False)

# import module snippets
from ansible.module_utils.basic import *
main()
{% endcodeblock  %}

The biggest portion of code is the read() method of the parser which does the following:

* scans text file line by line ignoring lines starting with `#` and whose length is not enough to contain either a scenario name or scenario step
* matches each line against pre-compiled regular expressions for scenario name or for scenario step ([a very helpful tool for regex testing](https://regex101.com/))
* attempts to save the data in a Python dictionary whose keys are scenario numbers and whose values is a list consisting of a scenario name (1st element) and a list of scenario steps (2nd element)

The end result of running both ip address collection and scenarios conversion plays is Ansible group variable file that looks like this:

{% codeblock lang:yaml  ~/tdd_ansible/library/group_vars/all.yml %}
---
ip2host:
   10.0.0.1: [R1, Loopback0]
   10.0.0.2: [R2, Loopback0]
   10.0.0.3: [R3, Loopback0]
   10.0.0.4: [R4, Loopback0]
   12.12.12.1: [R1, Ethernet0/0]
   12.12.12.2: [R2, Ethernet0/0]
   14.14.14.1: [R1, Ethernet0/1]
   14.14.14.4: [R4, Ethernet0/1]
   192.168.247.25: [R1, Ethernet0/2]
   23.23.23.2: [R3, Ethernet0/0]
   34.34.34.3: [R3, Ethernet0/1]
   34.34.34.4: [R4, Ethernet0/0]
scenarios:
   '1':
   - testing of primary link
   -  -  - r1
         - r3
         - [r2]
      -  - r1
         - r4
         - [r2, r3]
   '2':
   - testing of backup link
   -  -  - r1
         - r3
         - [r4]
      -  - r1
         - r2
         - [r4, r3]
{% endcodeblock  %}

***

The next post, final in a series, will show how to write an Ansible play to validate TDD scenarios and produce a meaningful error message in case it fails.

