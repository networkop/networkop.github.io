---
layout: post
title:  "My First Post"
date:   2015-06-02 21:19:02
tags: [sample post, code, highlighting, cisco, ios]
modified: 2015-06-05
published: true
categories: [sample, octopress]
keywords: sample, post, octopress, blog
comments: true
---


## Syntax highlighting
Here's the first post written in kramdown markup. Example of `text` syntax highlighting

{% codeblock lang:text %}
enable
! IOS comment
configure terminal
hostname MY-NEW-BLOG
interface GigabitEthernet0/0
 description WAN INTERFACE
 ip address 192.168.1.1 255.255.255.0
banner motd ^
 BANNER-TEXT  
^C
{% endcodeblock  %}

and now test it with `fenced code block` highlighting

~~~~
route-map RM-FILTER-OUT 10 permit
version 15.2
ip prefix-list PL-TEST permit 0.0.0.0/0 le 32
ip access-list ACL-DENY deny ip any any
!
router bgp 100
 bgp router-id 1.1.1.1
 neighbor peer-group SPOKES
 neighbor SPOKES remote-as 100
 neighbor SPOKES update-source Loopback0
 neighbor 2.2.2.2 peer-group SPOKES
 neighbor 3.3.3.3 peer-group SPOKES
!
line vty 0 4
 transport input ssh
!
end
~~~~

---

<!--more-->

Unfortunately, there's no way to modify GH-PAGES's default syntax highlighter. Otherwise it could have been possible 
to use a version of [Cisco IOS lexer][link-to-ios-lexer] developed by [Brandon Bennett][nemith-github-link] for pygments.
Of course, there's always an option to build a site locally and push it out already compiled. That's something I might consider later on, if I really need that IOS syntax highlighter.

BTW, while playing with lexers and troubleshooting regexps found [a brilliant tool for regex testing][regex-101-link]

Installation procedure of a new pygments lexer is described on [Pygments Website][pygments-new-lexer-link].

## Diagrams
{% img centre /images/unetlab-full-topo.png 'Big Network topology'%}


For network virtualization I'll be using [Unetlab][unetlab-link]

## Guithub gists
{% gist 1ae62939b268945cec10 gistfile1.py %}
Link to the site of [Big C][cisco-link]. And here's the link to github pages blog [Github.io][github-link]. Link to my github account [Michael Kashin's github][mkashin-github].

[cisco-link]:      http://cisco.com
[github-link]:   https://github.io/
[mkashin-github]: https://github.com/mkashin
[link-to-ios-lexer]: https://github.com/nemith/pygments-routerlexers
[nemith-github-link]: https://github.com/nemith
[pygments-new-lexer-link]: http://pygments.org/docs/lexerdevelopment/
[regex-101-link]: https://regex101.com/
[kramdown-link]: http://kramdown.gettalong.org/quickref.html
[hpstr-theme-link]: https://mmistakes.github.io/hpstr-jekyll-theme/
[unetlab-link]: http://www.unetlab.com/


