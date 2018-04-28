+++
title = "Verifying TDD Scenarios"
date = 2015-07-10T00:00:00Z
categories = ["automation"]
url = "/blog/2015/07/10/test-verification/"
slug = "/blog/2015/07/10/test-verification/"
tags = ["network-TDD", "Ansible", "DevOps"]
summary = "Writing a custom Ansible module to verify TDD scenarios"
draft = false
+++

Now that Ansible has done all the information gathering for us it's time to finally make use of it. In this post I will show how to use Ansible to run traceroutes from and to the hosts defined in a test scenario and perform verification of the results of those tests. Should any of those tests fail, Ansible will provide a meaningful description of what exactly failed and why. While doing all this I'll introduce a couple of new Ansible features like conditional looping and interactive prompts.


# TDD Playbook

In order to run and verify tests I will create a separate playbook. It makes sense to separate it from the [previous playbook][previous-post] simply because this time it will be used multiple times, while the information gathering playbook can only be run once. The new playbook will have to accomplish the following tasks:

1. Select which scenario to test 
2. Run tests as specified in that scenario
3. Parse test results
4. Verify that test results conform to the specification

# Selecting test scenario

Our `scenarios/all.txt` file contains multiple test scenarios each defined by a name. Each test scenario represent a certain state in the network, e.g. scenario #1 tests how the network behaves in a normal state with no outages or link failures, scenario #2 tests how traffic should be rerouted in the event of primary link failure. Inside each scenario there are one or more test steps each testing a behaviour of a particular traffic flow, e.g. traffic from router R1 to router R4 should traverse R2 followed by R3. Each steps contains keywords `From`, `To` and `Via` which identify  source, destination and transit routers. This is how a typical scenario file looks like.

```
1. Testing of Primary Link
1.1 From R1 to R3 via R2
1.2 From R1 to R4 via R2, R3
1.3 From R2 to R4 via R3
1.4 From R1 to R2 via R2
2. Testing of Backup Link
2.1 From R1 to R3 via R4
2.2 From R1 to R2 via R4,R3
```

In the [previous post][previous-post] I showed how to parse and store these scenarios in YAML dictionary in `group_vars/all.yml` file, which makes this information automatically available to any future playbooks. So in the new playbook `~/tdd_ansible/cisco_tdd.yml` all we need to do is let the user decide which scenario to test:

```  
- name: Run traceroute commands
  hosts: cisco-devices
  gather_facts: false
  remote_user: cisco

  vars_prompt:
    - name: scenario_num
      prompt: "Enter scenario number"
      default: "1"
      private: no

  tasks:

    - name: extracting scenario name and steps
      set_fact:
        scenario_steps: "{{ scenarios[scenario_num][1] }}"
        scenario_name: "{{ scenarios[scenario_num][0] }}"
```

This playbook contains a standard header followed by a `vars_prompt` section which prompts user to select a particular scenario number and stores the selection in `scenario_num` variable. The first task in the playbook extracts scenario name and steps from `scenarios` dictionary stored in `group_vars/all.yml` file and stores them in respective variables. Of course this task is optional and it's possible to reference the same data using full notation, however I prefer things to be more readable even if it leads to some inefficient memory use.

# Run test specified in scenario steps

Now it's time to run traceroutes to see how the packets flow in the network. As we did in one of the [previous posts](http://networkop.github.io/blog/2015/06/24/ansible-intro/) we'll use the `raw` module to run traceroutes. However this time, instead of running a full-mesh any-to-any traceroutes we'll only run them if they were defined in one of the test steps. Indeed, why would we run a traceroute between devices if we're not going to verify it? Ansible's conditionals will help us with that. For each of the hosts in `cisco-devices` group we'll look into scenario_steps dictionary and see if there were any tests defined and if there were, we'll run a traceroute to each of the destination hosts.

```  
    - name: run traceroutes as per the defined scenario steps
      raw: traceroute {{ hostvars[item.key]['ansible_ssh_host'] }} source Loopback0 probe 1 numeric
      when: scenario_steps[inventory_hostname] is defined
      with_dict: scenario_steps[inventory_hostname]|default({})
      register: trace_result
```

When both a loop (`with_dict`) and a conditional (`when`) are defined in a task, Ansible does the looping first. That's why if a test scenario is not defined for a particular host (e.g. `R3`) the conditional check will fail and stop execution of the playbook. To overcome that we can use Ansible (Jinja) templates inside the `with_dict` loop. Appending `|default({})` will instruct Ansible create an empty dictionary in case `scenario_steps[inventory_hostname]` does not exist which will make conditional return `False` and skip this host altogether. 

# Parse test results 

There's no silver bullet when it comes to parsing of the outcome of traceroute command. We'll have to use Python to traverse the textual output line by line looking for `msec` and storing all found IPs in a list. 

```python
class TraceParse(object):

    def __init__(self, module):
        self.std_out = module.params['std_out']
        self.dest_host = module.params['dest_host']

    def parse(self):
        result = dict()
        path = list()
        for line in self.std_out.split("\n"):
            if 'msec' in line:
                path.append(line.split()[1])
        result[self.dest_host] = path
        return result

def main():
    module = AnsibleModule(
        argument_spec=dict(
            std_out=dict(required=True, type='str'),
            dest_host=dict(required=True, type='str')
        )
    )
    traceParser = TraceParse(module)
    result = traceParser.parse()
    module.exit_json(changed=False, ansible_facts=result)

# import module snippets
from ansible.module_utils.basic import *
main()
```

The playbook task will run through each hosts' trace_results variable and pass it to the trace parse module. 

``` 
    - name: parse traceroute ouput
      cisco_trace_parse:
        dest_host: "{{ item.item.key }}"
        std_out: "{{ item.stdout }}"
      connection: local
      when: item.stdout is defined
      with_items: trace_result.results
```

# Test verification

Finally we need to compare the captured output with the scenario steps. This time all the information collected by Ansible in the previous tasks needs to be passed to a module. 

``` 
    - name: verify traceroutes against pre-defined scenarios
      cisco_tdd_verify:
        dest_host: "{{ item.key }}"
        src_host: "{{ inventory_hostname }}"
        scenario: "{{ scenario_steps }}"
        ip2host: "{{ ip2host }}"
        path: "{{ hostvars[inventory_hostname][item.key] }}"
        scenario_name: "{{ scenario_name }}"
      when: scenario_steps[inventory_hostname] is defined
      with_dict: scenario_steps[inventory_hostname]|default({})
      connection: local
```

Ansible module contains a class with a single public method `compare`. The first thing it does is converts the list of IP addresses of transit devices into a list of hostnames. That's where the IP-to-Hostname dictionary created in the [previous playbook][previous-post] is first used. IP address is used as a lookup key and the Hostname is extracted from the first element of the returned list (second element, the interface name, is currently unused). The private method `__validatepath` is used to confirm that devices listed after `Via` in a test scenario are present in the traceroute path in the specified order. If this verification fails, the whole module fails and the error message is passed back to Ansible playbook.

```python
class ResultCompare(object):

    def __init__(self, module):
        self.dest_host = module.params['dest_host']
        self.src_host = module.params['src_host']
        self.trace_path = module.params['path']
        self.ref_scenario = module.params['scenario']
        self.ip2host = module.params['ip2host']
        self.scenario_name = module.params['scenario_name']

    def compare(self):
        trace_path_new = list()
        for dev in self.trace_path:
            if dev in self.ip2host:
                trace_path_new.append(self.ip2host[dev][0])
            else:
                trace_path_new.append(dev)
        if self.src_host in self.ref_scenario:
            if self.dest_host in self.ref_scenario[self.src_host]:
                ref_path = self.ref_scenario[self.src_host][self.dest_host]
                if not self. __validatepath(trace_path_new):
                    msg = "Failed scenario " + self.scenario_name +  ".\r\nTraceroute from " + self.src_host + " to " + self.dest_host + " has not traversed " + str(ref_path)
                    msg += "\r\n Actual path taken: " + ' -> '.join([self.src_host] + trace_path_new) + "\r\n"
                    return 1, msg
        return 0, 'no error'

    def __validatepath(self, path):
        index = 0
        for device in path:
            if device == self.ref_scenario[self.src_host][self.dest_host][index]:
                index += 1
                if index == len(self.ref_scenario[self.src_host][self.dest_host]):
                    return True
        return False


def main():
    module = AnsibleModule(
        argument_spec=dict(
            dest_host=dict(required=True, type='str'),
            src_host=dict(required=True, type='str'),
            scenario=dict(required=True, type='dict'),
            ip2host=dict(required=True, type='dict'),
            path=dict(required=True, type='list'),
            scenario_name=dict(required=True, type='str')
        )
    )
    comparator = ResultCompare(module)
    rc, error = comparator.compare()
    if rc != 0:
        module.fail_json(msg=error)
    else:
        module.exit_json(changed=False)

from ansible.module_utils.basic import *
main()
```

# TDD in action

So let's finally see the whole thing action. First let's modify a [4-router topology](/blog/2015/06/17/dev-env-setup/) so that traffic from R1 to R4 is routed via R2 and R3 (a simple `delay 9999` on Ethernet0/1 will do). Now let's run the first scenario and verify that no errors are displayed.

```
~/tdd_ansible# ansible-playbook cisco_tdd.yml
Enter scenario number [1]: 

PLAY [Run traceroute commands] ************************************************
...
PLAY RECAP ********************************************************************
R1                         : ok=4    changed=0    unreachable=0    failed=0
R2                         : ok=4    changed=0    unreachable=0    failed=0
R3                         : ok=2    changed=0    unreachable=0    failed=0
R4                         : ok=2    changed=0    unreachable=0    failed=0
```

Nothing much really, which is good, that means all scenarios were verified successfully. Now let's see how it fails. The easiest way is to run the tests from a second scenario, the one that assumes that the link between R1 and R2 failed and all the traffic is routed via R4.
 
```
~/tdd_ansible# ansible-playbook cisco_tdd.yml
Enter scenario number [1]: 2

PLAY [Run traceroute commands] ************************************************
...
TASK: [verify traceroutes against pre-defined scenarios] **********************
skipping: [R2]
skipping: [R4]
failed: [R1] => (item={'key': 'R2', 'value': ['R4', 'R3']}) => {"failed": true, "item": {"key": "R2", "value": ["R4", "R3"]}}
msg: Failed scenario Testing of Backup Link.
Traceroute from R1 to R2 has not traversed ['R4', 'R3']
 Actual path taken: R1 -> R2

failed: [R3] => (item={'key': 'R1', 'value': ['R4']}) => {"failed": true, "item": {"key": "R1", "value": ["R4"]}}
msg: Failed scenario Testing of Backup Link.
Traceroute from R3 to R1 has not traversed ['R4']
 Actual path taken: R3 -> R2 -> R1

failed: [R1] => (item={'key': 'R3', 'value': ['R4']}) => {"failed": true, "item": {"key": "R3", "value": ["R4"]}}
msg: Failed scenario Testing of Backup Link.
Traceroute from R1 to R3 has not traversed ['R4']
 Actual path taken: R1 -> R2 -> R3


PLAY RECAP ********************************************************************
           to retry, use: --limit @/root/cisco_tdd.retry

R1                         : ok=3    changed=0    unreachable=0    failed=1
R2                         : ok=2    changed=0    unreachable=0    failed=0
R3                         : ok=3    changed=0    unreachable=0    failed=1
R4                         : ok=2    changed=0    unreachable=0    failed=0
```

Here all 3 test steps within a scenario failed. Ansible displayed error messages passed down by our module, specifying the expected and the actual path.  
Now if we simply shutdown Ethernet0/0 of R1 to simulate a link failure and re-run the same scenario all tests will succeed again.

```
~/tdd_ansible# ansible-playbook cisco_tdd.yml
Enter scenario number [1]: 2

PLAY [Run traceroute commands] ************************************************
...
PLAY RECAP ********************************************************************
R1                         : ok=4    changed=0    unreachable=0    failed=0
R2                         : ok=2    changed=0    unreachable=0    failed=0
R3                         : ok=4    changed=0    unreachable=0    failed=0
R4                         : ok=2    changed=0    unreachable=0    failed=0
```

So there it is, a working network TDD framework in action. I still haven't covered a lot of corner cases (e.g. when traceroute times out) and deployment scenarios (device with VRFs) but it should still work for a lot of scenarios and can be easily extended to cover those corner cases.

[previous-post]: /blog/2015/07/03/parser-modules/
