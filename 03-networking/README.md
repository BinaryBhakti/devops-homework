# Homework 3 — Networking

**Task 1:** practise the commands from the `devops-heros` repo.
**Task 2:** create a Markdown file with the command output and an explanation of each command.

Every command below was executed live inside the Ubuntu 24.04 lab container (see
[Homework 1](../01-linux)), which has real network access. **All output blocks are extracted
verbatim from the captured transcript** — [`outputs/networking-commands.txt`](outputs/networking-commands.txt).
The script that produced it is [`scripts/net-lab.sh`](scripts/net-lab.sh).

The lab machine's addressing, for reference when reading the output below:

```
container IP  172.17.0.2/16      gateway 172.17.0.1     DNS 192.168.65.7
public IP     106.192.251.38     interface eth0         MTU 65535
```

---

## Where these commands sit — the OSI layers

```
  Layer 7  Application   curl  wget  dig  nslookup  host  whois
  Layer 4  Transport     ss  netstat  nc  telnet          (TCP/UDP ports)
  Layer 3  Network       ip addr  ip route  ping  traceroute  mtr   (IP)
  Layer 2  Data link     arp  ip neigh  ip link  ethtool          (MAC)
  Layer 1  Physical      ethtool  ip -s link                       (cable, signal)
```

Troubleshooting works **bottom up**: is the link up → do I have an IP → can I reach the gateway
→ can I reach the internet → does DNS resolve → is the port open → does the app respond.

---

## 1. `ip addr` — interfaces and IP addresses

**What I understood:** `ip addr` is the modern replacement for `ifconfig`. It lists every
network interface and the addresses assigned to it. `lo` is the loopback (always 127.0.0.1),
`eth0` is the real interface. The `/16` is the subnet mask in CIDR form, and `state UP` means
the link is live. This is the first command to run when something cannot connect — no IP means
nothing else will work.

```console
$ ip addr show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: tunl0@NONE: <NOARP> mtu 1480 qdisc noop state DOWN group default qlen 1000
    link/ipip 0.0.0.0 brd 0.0.0.0
3: gre0@NONE: <NOARP> mtu 1476 qdisc noop state DOWN group default qlen 1000
    link/gre 0.0.0.0 brd 0.0.0.0
4: gretap0@NONE: <BROADCAST,MULTICAST> mtu 1462 qdisc noop state DOWN group default qlen 1000
    link/ether 00:00:00:00:00:00 brd ff:ff:ff:ff:ff:ff
...

$ ip -brief addr show
lo               UNKNOWN        127.0.0.1/8 ::1/128 
tunl0@NONE       DOWN           
gre0@NONE        DOWN           
gretap0@NONE     DOWN           
erspan0@NONE     DOWN           
ip_vti0@NONE     DOWN           
ip6_vti0@NONE    DOWN           
sit0@NONE        DOWN           
ip6tnl0@NONE     DOWN           
ip6gre0@NONE     DOWN           
eth0@if25        UP             172.17.0.2/16 

$ hostname -I
172.17.0.2 
```

| Command | Purpose |
|---|---|
| `ip addr show` | all interfaces and addresses |
| `ip -brief addr show` | one compact line per interface |
| `ip -4 addr show eth0` | IPv4 only, one interface |
| `ip link show` | layer-2 state (up/down, MAC) without addresses |
| `hostname -I` | just the IPs, nothing else — handy in scripts |
| `ip addr add 10.0.0.5/24 dev eth0` | assign an address (temporary) |

## 2. `ifconfig` — the older equivalent

**What I understood:** `ifconfig` comes from the deprecated `net-tools` package. It shows
roughly the same information as `ip addr` but is no longer installed by default on modern
distros. Worth knowing because you will meet it on older servers and in old documentation,
but new work should use `ip`.

```console
$ ifconfig eth0
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 65535
        inet 172.17.0.2  netmask 255.255.0.0  broadcast 172.17.255.255
        ether e6:85:22:bb:eb:ea  txqueuelen 0  (Ethernet)
        RX packets 5779  bytes 52465504 (52.4 MB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 4324  bytes 300111 (300.1 KB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
```

Note it shows the mask as `255.255.0.0` where `ip` shows `/16` — the same thing written two ways.

## 3. `ip route` — the routing table

**What I understood:** the routing table decides *which interface and which next hop* a packet
uses. The `default via 172.17.0.1` line is the **default gateway** — anything not on a directly
connected network is handed to it. The second line says "172.17.0.0/16 is on my own link, no
gateway needed". If the default route is missing, you can ping your LAN but not the internet.

```console
$ ip route show
default via 172.17.0.1 dev eth0 
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.2 

$ ip route get 8.8.8.8
8.8.8.8 via 172.17.0.1 dev eth0 src 172.17.0.2 uid 0 
    cache 

$ route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         172.17.0.1      0.0.0.0         UG    0      0        0 eth0
172.17.0.0      0.0.0.0         255.255.0.0     U     0      0        0 eth0
```

`ip route get <ip>` is the useful one when debugging: it asks the kernel to *decide* the route
for a specific destination and shows you the answer.

## 4. `ping` — is the host reachable?

**What I understood:** `ping` sends ICMP echo requests and waits for replies. It proves two
things at once — the host is reachable at layer 3, and how long the round trip takes. The
`time=` value is latency; missing sequence numbers mean packet loss. Pinging `127.0.0.1` tests
your own TCP/IP stack; pinging the gateway tests the LAN; pinging `8.8.8.8` tests the internet
route; pinging a *name* also tests DNS.

```console
$ ping -c 4 127.0.0.1
PING 127.0.0.1 (127.0.0.1) 56(84) bytes of data.
64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.057 ms
64 bytes from 127.0.0.1: icmp_seq=2 ttl=64 time=0.078 ms
64 bytes from 127.0.0.1: icmp_seq=3 ttl=64 time=0.078 ms
64 bytes from 127.0.0.1: icmp_seq=4 ttl=64 time=0.117 ms

--- 127.0.0.1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3053ms
rtt min/avg/max/mdev = 0.057/0.082/0.117/0.021 ms

$ ping -c 4 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=63 time=353 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=63 time=86.5 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=63 time=122 ms
64 bytes from 8.8.8.8: icmp_seq=4 ttl=63 time=79.5 ms

--- 8.8.8.8 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3018ms
rtt min/avg/max/mdev = 79.500/160.251/353.155/112.527 ms

$ ping -c 4 google.com
PING google.com (172.217.24.174) 56(84) bytes of data.
64 bytes from lcmaaa-bc-in-f14.1e100.net (172.217.24.174): icmp_seq=1 ttl=63 time=72.3 ms
64 bytes from lcmaaa-bc-in-f14.1e100.net (172.217.24.174): icmp_seq=2 ttl=63 time=90.4 ms
64 bytes from lcmaaa-bc-in-f14.1e100.net (172.217.24.174): icmp_seq=3 ttl=63 time=142 ms
64 bytes from lcmaaa-bc-in-f14.1e100.net (172.217.24.174): icmp_seq=4 ttl=63 time=83.2 ms

--- google.com ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3016ms
rtt min/avg/max/mdev = 72.302/97.040/142.285/26.904 ms
```

The classic diagnostic ladder: `ping 127.0.0.1` → `ping <gateway>` → `ping 8.8.8.8` →
`ping google.com`. Whichever step fails tells you the layer that is broken. Note that a failed
ping does **not** always mean "down" — many hosts and firewalls simply drop ICMP.

| Flag | Meaning |
|---|---|
| `-c 4` | send 4 packets and stop |
| `-i 0.2` | interval between packets |
| `-s 1400` | payload size — useful for finding MTU problems |
| `-W 2` | per-packet timeout |

## 5. `traceroute` / `mtr` — what path do packets take?

**What I understood:** traceroute finds every router between you and the destination by sending
packets with a deliberately small TTL and reading the "time exceeded" replies. Each line is one
hop. `* * *` means that hop did not reply — usually a router configured not to send ICMP, which
is normal and not necessarily a fault. `mtr` is traceroute and ping combined, run continuously,
which makes it much better at spotting *where* loss starts.

```console
$ traceroute -m 8 -w 2 8.8.8.8
traceroute to 8.8.8.8 (8.8.8.8), 8 hops max, 60 byte packets
 1  172.17.0.1 (172.17.0.1)  0.655 ms  0.024 ms  0.029 ms
 2  * * *
 3  * * *
 4  * * *
 5  * * *
 6  * * *
 7  * * *
 8  * * *

$ mtr -r -c 3 8.8.8.8
Start: 2026-09-03T05:10:52+0000
HOST: ff4c4be986b8                Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 172.17.0.1                 0.0%     3    0.4   0.4   0.2   0.5   0.1
  2.|-- dns.google                 0.0%     3  109.0 128.3 109.0 160.9  28.4
```

traceroute could only identify hop 1 (the Docker gateway) and got `* * *` for the rest, but
`mtr` resolved hop 2 to `dns.google` and reported 0% loss — a good illustration of why `mtr`
is the better tool.

## 6. DNS — `nslookup`, `dig`, `host`

**What I understood:** DNS turns names into IP addresses. `nslookup` is the simple one, `dig`
is the detailed one (it shows the actual DNS protocol sections), and `host` is the quick one.
"Non-authoritative answer" means the reply came from a caching resolver, not the domain's own
nameserver. `/etc/resolv.conf` says which resolver is being used, and `/etc/hosts` is checked
*before* DNS — which is why a stale line there can override the real world.

```console
$ nslookup github.com
Server:		192.168.65.7
Address:	192.168.65.7#53

Non-authoritative answer:
Name:	github.com
Address: 20.207.73.82

$ dig github.com +short
20.207.73.82

$ dig github.com

; <<>> DiG 9.18.39-0ubuntu0.24.04.7-Ubuntu <<>> github.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 19665
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0

;; QUESTION SECTION:
;github.com.			IN	A

;; ANSWER SECTION:
github.com.		40	IN	A	20.207.73.82

;; Query time: 3 msec
;; SERVER: 192.168.65.7#53(192.168.65.7) (UDP)
;; WHEN: Thu Sep 03 05:11:01 UTC 2026
;; MSG SIZE  rcvd: 54

$ dig google.com MX +short
10 smtp.google.com.

$ dig -x 8.8.8.8 +short
dns.google.

$ host github.com
github.com has address 20.207.73.82
github.com mail is handled by 0 github-com.mail.protection.outlook.com.

$ cat /etc/resolv.conf
# Generated by Docker Engine.
# This file can be edited; Docker Engine will not make further changes once it
# has been modified.

nameserver 192.168.65.7

# Based on host file: '/etc/resolv.conf' (legacy)
# Overrides: []
```

The number before `IN A` in the answer section is the **TTL** — how many more seconds this
answer may be cached. `status: NOERROR` means the lookup succeeded; `NXDOMAIN` means the name
does not exist.

| Record | Meaning |
|---|---|
| `A` / `AAAA` | name → IPv4 / IPv6 address |
| `MX` | mail servers for the domain |
| `NS` | authoritative nameservers |
| `CNAME` | alias to another name |
| `TXT` | free text — SPF, domain verification |
| `PTR` | reverse: IP → name (`dig -x`) |

## 7. `ss` / `netstat` — which ports are open?

**What I understood:** `ss` lists sockets. `-t` TCP, `-u` UDP, `-l` only listening, `-n` numeric
(don't resolve names, which makes it instant), `-p` show the owning process. This is how you
answer "is my service actually running and bound to the right address?" Binding to `0.0.0.0`
means all interfaces; `127.0.0.1` means local only, which is the usual reason a service works
on the box but not from outside. `netstat` is the older, deprecated equivalent.

```console
$ ss -tuln
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*          
tcp   LISTEN 0      511             [::]:80           [::]:*          

$ ss -s
Total: 56
TCP:   66 (estab 0, closed 64, orphaned 0, timewait 1)

Transport Total     IP        IPv6
RAW	  0         0         0        
UDP	  0         0         0        
TCP	  2         1         1        
INET	  2         1         1        
FRAG	  0         0         0        

$ netstat -i
Kernel Interface table
Iface             MTU    RX-OK RX-ERR RX-DRP RX-OVR    TX-OK TX-ERR TX-DRP TX-OVR Flg
eth0            65535     5813      0      0 0          4379      0      0      0 BMRU
lo              65536       74      0      0 0            74      0      0      0 LRU

$ netstat -rn
Kernel IP routing table
Destination     Gateway         Genmask         Flags   MSS Window  irtt Iface
0.0.0.0         172.17.0.1      0.0.0.0         UG        0 0          0 eth0
172.17.0.0      0.0.0.0         255.255.0.0     U         0 0          0 eth0
```

`ss -tulnp` additionally names the exact process holding the port — that is the command to
reach for when a port is "already in use":

```console
$ ss -tulnp
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess                                                                                                                                                                                                                         
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=1070,fd=5),("nginx",pid=1069,fd=5),("nginx",pid=1068,fd=5),("nginx",pid=1067,fd=5),("nginx",pid=1065,fd=5),("nginx",pid=1064,fd=5),("nginx",pid=1063,fd=5),("nginx",pid=1062,fd=5),("nginx",pid=1061,fd=5))
...
```

| Command | Purpose |
|---|---|
| `ss -tuln` | all listening TCP/UDP ports |
| `ss -tulnp` | …plus the owning process |
| `ss -tan state established` | current established connections |
| `ss -s` | summary counts |
| `netstat -rn` | routing table (old equivalent of `ip route`) |
| `netstat -i` | per-interface packet counters |

## 8. `curl` / `wget` — make HTTP requests

**What I understood:** `curl` sends an HTTP request and prints the response. It is the fastest
way to check whether a web service is alive, what status code it returns, and how long it takes
— without a browser. `-I` fetches only the headers, `-s` silences the progress meter, and `-w`
lets you print exactly the timing/status fields you care about. `wget` is similar but is
oriented towards *downloading files*.

```console
$ curl -s -o /dev/null -w 'HTTP status: %{http_code}\nTotal time: %{time_total}s\nRemote IP: %{remote_ip}\n' https://github.com
HTTP status: 200
Total time: 1.572165s
Remote IP: 20.207.73.82

$ curl -s https://api.github.com/zen
Approachable is better than simple.

$ curl -s ifconfig.me; echo
106.192.251.38
```

That last one is the machine's **public** IP, as the internet sees it — different from the
private `172.17.0.2` on `eth0`.

```console
$ curl -I https://api.github.com
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed

  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
  0  2396    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
HTTP/2 200 
date: Thu, 03 Sep 2026 05:10:51 GMT
...
```

> **Gotcha found in this lab:** the first run of these commands failed with
> `curl: (77) error setting certificate file: /etc/ssl/certs/ca-certificates.crt` and
> `HTTP status: 000`. A minimal Ubuntu image ships **no CA certificates**, so TLS verification
> cannot happen. Fixed with `apt-get install ca-certificates && update-ca-certificates`, after
> which the same commands returned `HTTP status: 200`.
> `HTTP 000` from curl always means "the connection never completed" — not a server error.

| Flag | Purpose |
|---|---|
| `-I` | headers only (HEAD request) |
| `-s` | silent — no progress meter |
| `-o file` | save body to a file (`-o /dev/null` to discard) |
| `-L` | follow redirects |
| `-w '%{http_code}'` | print selected response metadata |
| `-X POST -d 'data'` | send a POST |
| `-H 'Header: value'` | add a request header |
| `-k` | skip TLS verification (debugging only) |

## 9. `nc` (netcat) — is this TCP port open?

**What I understood:** netcat opens a raw TCP connection. With `-z` it just checks whether the
port accepts a connection and reports, without sending data. This separates "the network is
fine but the service is down" from "the network is blocking me" — a `ping` can succeed while
the port is firewalled.

```console
$ nc -zv github.com 443
Connection to github.com (20.207.73.82) 443 port [tcp/https] succeeded!

$ nc -zv github.com 80
Connection to github.com (20.207.73.82) 80 port [tcp/http] succeeded!

$ nc -zv -w 3 github.com 12345
nc: connect to github.com (20.207.73.82) port 12345 (tcp) timed out: Operation now in progress

$ nc -zv 127.0.0.1 80
Connection to 127.0.0.1 80 port [tcp/http] succeeded!
```

Port 12345 timed out — nothing is listening there. Note the difference between a **timeout**
(a firewall silently dropped the packet) and **connection refused** (the host answered, but no
service is on that port). That distinction is diagnostic gold.

## 10. `arp` / `ip neigh` — IP to MAC (layer 2)

**What I understood:** on a local network, packets are actually delivered to **MAC addresses**,
not IPs. ARP is the protocol that asks "who has this IP?" and caches the answer. The ARP table
only ever contains hosts on the *same subnet* — anything else goes via the gateway, so you will
only ever see the gateway's MAC for remote traffic.

```console
$ arp -n
Address                  HWtype  HWaddress           Flags Mask            Iface
172.17.0.1               ether   62:e5:3a:24:1e:65   C                     eth0

$ ip neigh show
172.17.0.1 dev eth0 lladdr 62:e5:3a:24:1e:65 REACHABLE 
```

`REACHABLE` is the cache state; others include `STALE` and `FAILED` (which usually means the
host is off, or ARP is being blocked).

## 11. Interface statistics

**What I understood:** the RX/TX counters tell you whether the interface is actually passing
traffic and whether it is seeing errors or drops. Non-zero `errors` or `dropped` points at a
hardware, driver or MTU problem rather than an application one.

```console
$ ip -s link show eth0
11: eth0@if25: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65535 qdisc noqueue state UP mode DEFAULT group default 
    link/ether e6:85:22:bb:eb:ea brd ff:ff:ff:ff:ff:ff link-netnsid 0
    RX:  bytes packets errors dropped  missed   mcast           
      53075865    5933      0       0       0       0 
    TX:  bytes packets errors dropped carrier collsns           
        315731    4502      0       0       0       0 

$ cat /sys/class/net/eth0/address
e6:85:22:bb:eb:ea

$ cat /sys/class/net/eth0/mtu
65535
```

## 12. `tcpdump` — capture live packets

**What I understood:** tcpdump captures actual packets off the wire and decodes them. It is the
ultimate answer to "is my traffic even leaving this machine?" Below it captured a real ping:
you can see the echo *request* leaving 172.17.0.2 and the echo *reply* coming back from 8.8.8.8,
with matching `id` and `seq` values. If you only see requests and no replies, the problem is
somewhere outbound.

```console
$ tcpdump -i eth0 -c 5 -nn icmp & sleep 1; ping -c 3 8.8.8.8 >/dev/null 2>&1; wait
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
05:11:12.740849 IP 172.17.0.2 > 8.8.8.8: ICMP echo request, id 35081, seq 1, length 64
05:11:13.159566 IP 8.8.8.8 > 172.17.0.2: ICMP echo reply, id 35081, seq 1, length 64
05:11:13.747145 IP 172.17.0.2 > 8.8.8.8: ICMP echo request, id 35081, seq 2, length 64
05:11:13.904628 IP 8.8.8.8 > 172.17.0.2: ICMP echo reply, id 35081, seq 2, length 64
05:11:14.753833 IP 172.17.0.2 > 8.8.8.8: ICMP echo request, id 35081, seq 3, length 64
5 packets captured
6 packets received by filter
0 packets dropped by kernel
```

| Flag | Meaning |
|---|---|
| `-i eth0` | which interface (`-i any` for all) |
| `-c 5` | stop after 5 packets |
| `-nn` | don't resolve hostnames **or** port names — much faster |
| `-w file.pcap` | write a capture file for Wireshark |
| `port 80` / `host 8.8.8.8` / `icmp` | BPF filter expressions |

## 13. `whois` — who owns a domain?

**What I understood:** whois queries the domain registry for registration data — registrar,
creation and expiry dates, and the authoritative nameservers. Useful for checking whether a
domain is about to expire, or finding who to contact about it.

```console
$ whois github.com 2>&1 | grep -iE 'domain name|registrar:|creation date|expir|name server' | head -10
   Domain Name: GITHUB.COM
   Creation Date: 2007-10-09T18:20:50Z
   Registry Expiry Date: 2026-10-09T18:20:50Z
   Registrar: MarkMonitor Inc.
   Name Server: DNS1.P08.NSONE.NET
   Name Server: DNS2.P08.NSONE.NET
   Name Server: DNS3.P08.NSONE.NET
   Name Server: DNS4.P08.NSONE.NET
   Name Server: NS-1283.AWSDNS-32.ORG
   Name Server: NS-1707.AWSDNS-21.CO.UK
```

## 14. Putting it together — testing a local web server

**What I understood:** this is the full chain in miniature. `systemctl is-active` says the
service is running, `ss` proves it is bound to port 80, and `curl` proves it actually answers
HTTP. All three together is what "the service is up" really means.

```console
$ systemctl is-active nginx
active

$ curl -sI http://localhost
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Date: Thu, 03 Sep 2026 05:11:18 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Thu, 03 Sep 2026 04:19:23 GMT
Connection: keep-alive
ETag: "6a98f54b-267"
Accept-Ranges: bytes

$ ss -tlnp | grep :80
LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=1070,fd=5),("nginx",pid=1069,fd=5),("nginx",pid=1068,fd=5),("nginx",pid=1067,fd=5),("nginx",pid=1065,fd=5),("nginx",pid=1064,fd=5),("nginx",pid=1063,fd=5),("nginx",pid=1062,fd=5),("nginx",pid=1061,fd=5))
LISTEN 0      511             [::]:80           [::]:*    users:(("nginx",pid=1070,fd=6),("nginx",pid=1069,fd=6),("nginx",pid=1068,fd=6),("nginx",pid=1067,fd=6),("nginx",pid=1065,fd=6),("nginx",pid=1064,fd=6),("nginx",pid=1063,fd=6),("nginx",pid=1062,fd=6),("nginx",pid=1061,fd=6))
```

---

## Quick reference

| Question | Command |
|---|---|
| What is my IP? | `ip addr show` / `hostname -I` |
| What is my **public** IP? | `curl ifconfig.me` |
| What is my gateway? | `ip route` |
| Can I reach that host? | `ping -c 4 host` |
| Which route do packets take? | `traceroute host` / `mtr host` |
| Does this name resolve? | `dig name +short` / `nslookup name` |
| What ports am I listening on? | `ss -tuln` |
| Which process owns port 80? | `ss -tulnp \| grep :80` |
| Is that remote port open? | `nc -zv host port` |
| Does the web service answer? | `curl -I http://host` |
| What is that IP's MAC? | `ip neigh show` |
| Are packets actually flowing? | `tcpdump -i eth0 -nn` |
| Who owns this domain? | `whois domain.com` |

## Subnetting notes (from the session material)

| Class | First octet | Default mask | Network / host bits |
|---|---|---|---|
| A | 1 – 126 | `255.0.0.0` (`/8`) | 8 / 24 |
| B | 128 – 191 | `255.255.0.0` (`/16`) | 16 / 16 |
| C | 192 – 223 | `255.255.255.0` (`/24`) | 24 / 8 |
| D | 224 – 239 | multicast | — |
| E | 240 – 255 | experimental | — |

- Hosts in a subnet = `2^(host bits)`, **usable** = `2^(host bits) − 2`
  (one address is the network, one is the broadcast).
  A `/24` gives `2^8 − 2 = 254` usable addresses; a `/8` gives `2^24 − 2 = 16,777,214`.
- Private ranges (RFC 1918): `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.
- `127.0.0.0/8` is loopback. `169.254.0.0/16` is link-local (APIPA) — seeing one of these
  usually means DHCP failed.
- Example: `197.23.45.10` with mask `255.255.255.0` → network `197.23.45.0`,
  broadcast `197.23.45.255`, usable range `.1` – `.254`.

<details>
<summary><b>Full transcript — all 14 sections</b> (click to expand)</summary>

```console

===================================================
  1. ip addr  --  show interfaces and IP addresses
===================================================
$ ip addr show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: tunl0@NONE: <NOARP> mtu 1480 qdisc noop state DOWN group default qlen 1000
    link/ipip 0.0.0.0 brd 0.0.0.0
3: gre0@NONE: <NOARP> mtu 1476 qdisc noop state DOWN group default qlen 1000
    link/gre 0.0.0.0 brd 0.0.0.0
4: gretap0@NONE: <BROADCAST,MULTICAST> mtu 1462 qdisc noop state DOWN group default qlen 1000
    link/ether 00:00:00:00:00:00 brd ff:ff:ff:ff:ff:ff
5: erspan0@NONE: <BROADCAST,MULTICAST> mtu 1450 qdisc noop state DOWN group default qlen 1000
    link/ether 00:00:00:00:00:00 brd ff:ff:ff:ff:ff:ff
6: ip_vti0@NONE: <NOARP> mtu 1480 qdisc noop state DOWN group default qlen 1000
    link/ipip 0.0.0.0 brd 0.0.0.0
7: ip6_vti0@NONE: <NOARP> mtu 1428 qdisc noop state DOWN group default qlen 1000
    link/tunnel6 :: brd :: permaddr 6ebe:73fd:b2c8::
8: sit0@NONE: <NOARP> mtu 1480 qdisc noop state DOWN group default qlen 1000
    link/sit 0.0.0.0 brd 0.0.0.0
9: ip6tnl0@NONE: <NOARP> mtu 1452 qdisc noop state DOWN group default qlen 1000
    link/tunnel6 :: brd :: permaddr 4eb4:c424:ccfb::
10: ip6gre0@NONE: <NOARP> mtu 1448 qdisc noop state DOWN group default qlen 1000
    link/gre6 :: brd :: permaddr 6a0f:752b:6a91::
11: eth0@if25: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65535 qdisc noqueue state UP group default 
    link/ether e6:85:22:bb:eb:ea brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever

$ ip -brief addr show
lo               UNKNOWN        127.0.0.1/8 ::1/128 
tunl0@NONE       DOWN           
gre0@NONE        DOWN           
gretap0@NONE     DOWN           
erspan0@NONE     DOWN           
ip_vti0@NONE     DOWN           
ip6_vti0@NONE    DOWN           
sit0@NONE        DOWN           
ip6tnl0@NONE     DOWN           
ip6gre0@NONE     DOWN           
eth0@if25        UP             172.17.0.2/16 

$ ip -4 addr show eth0
11: eth0@if25: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65535 qdisc noqueue state UP group default  link-netnsid 0
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever

$ hostname -I
172.17.0.2 


===================================================
  2. ifconfig  --  the older (net-tools) equivalent of 'ip addr'
===================================================
$ ifconfig
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 65535
        inet 172.17.0.2  netmask 255.255.0.0  broadcast 172.17.255.255
        ether e6:85:22:bb:eb:ea  txqueuelen 0  (Ethernet)
        RX packets 5779  bytes 52465504 (52.4 MB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 4324  bytes 300111 (300.1 KB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
        inet 127.0.0.1  netmask 255.0.0.0
        inet6 ::1  prefixlen 128  scopeid 0x10<host>
        loop  txqueuelen 1000  (Local Loopback)
        RX packets 66  bytes 6846 (6.8 KB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 66  bytes 6846 (6.8 KB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0


$ ifconfig eth0
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 65535
        inet 172.17.0.2  netmask 255.255.0.0  broadcast 172.17.255.255
        ether e6:85:22:bb:eb:ea  txqueuelen 0  (Ethernet)
        RX packets 5779  bytes 52465504 (52.4 MB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 4324  bytes 300111 (300.1 KB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0



===================================================
  3. ip route / route  --  the routing table (where packets go)
===================================================
$ ip route show
default via 172.17.0.1 dev eth0 
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.2 

$ ip route get 8.8.8.8
8.8.8.8 via 172.17.0.1 dev eth0 src 172.17.0.2 uid 0 
    cache 

$ route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         172.17.0.1      0.0.0.0         UG    0      0        0 eth0
172.17.0.0      0.0.0.0         255.255.0.0     U     0      0        0 eth0

$ ip -brief link show
lo               UNKNOWN        00:00:00:00:00:00 <LOOPBACK,UP,LOWER_UP> 
tunl0@NONE       DOWN           0.0.0.0 <NOARP> 
gre0@NONE        DOWN           0.0.0.0 <NOARP> 
gretap0@NONE     DOWN           00:00:00:00:00:00 <BROADCAST,MULTICAST> 
erspan0@NONE     DOWN           00:00:00:00:00:00 <BROADCAST,MULTICAST> 
ip_vti0@NONE     DOWN           0.0.0.0 <NOARP> 
ip6_vti0@NONE    DOWN           :: <NOARP> 
sit0@NONE        DOWN           0.0.0.0 <NOARP> 
ip6tnl0@NONE     DOWN           :: <NOARP> 
ip6gre0@NONE     DOWN           :: <NOARP> 
eth0@if25        UP             e6:85:22:bb:eb:ea <BROADCAST,MULTICAST,UP,LOWER_UP> 


===================================================
  4. ping  --  is the host reachable? (ICMP echo)
===================================================
$ ping -c 4 127.0.0.1
PING 127.0.0.1 (127.0.0.1) 56(84) bytes of data.
64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.057 ms
64 bytes from 127.0.0.1: icmp_seq=2 ttl=64 time=0.078 ms
64 bytes from 127.0.0.1: icmp_seq=3 ttl=64 time=0.078 ms
64 bytes from 127.0.0.1: icmp_seq=4 ttl=64 time=0.117 ms

--- 127.0.0.1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3053ms
rtt min/avg/max/mdev = 0.057/0.082/0.117/0.021 ms

$ ping -c 4 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=63 time=353 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=63 time=86.5 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=63 time=122 ms
64 bytes from 8.8.8.8: icmp_seq=4 ttl=63 time=79.5 ms

--- 8.8.8.8 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3018ms
rtt min/avg/max/mdev = 79.500/160.251/353.155/112.527 ms

$ ping -c 4 google.com
PING google.com (172.217.24.174) 56(84) bytes of data.
64 bytes from lcmaaa-bc-in-f14.1e100.net (172.217.24.174): icmp_seq=1 ttl=63 time=72.3 ms
64 bytes from lcmaaa-bc-in-f14.1e100.net (172.217.24.174): icmp_seq=2 ttl=63 time=90.4 ms
64 bytes from lcmaaa-bc-in-f14.1e100.net (172.217.24.174): icmp_seq=3 ttl=63 time=142 ms
64 bytes from lcmaaa-bc-in-f14.1e100.net (172.217.24.174): icmp_seq=4 ttl=63 time=83.2 ms

--- google.com ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3016ms
rtt min/avg/max/mdev = 72.302/97.040/142.285/26.904 ms


===================================================
  5. traceroute / mtr  --  what path do packets take?
===================================================
$ traceroute -m 8 -w 2 8.8.8.8
traceroute to 8.8.8.8 (8.8.8.8), 8 hops max, 60 byte packets
 1  172.17.0.1 (172.17.0.1)  0.655 ms  0.024 ms  0.029 ms
 2  * * *
 3  * * *
 4  * * *
 5  * * *
 6  * * *
 7  * * *
 8  * * *

$ mtr -r -c 3 8.8.8.8
Start: 2026-09-03T05:10:52+0000
HOST: ff4c4be986b8                Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 172.17.0.1                 0.0%     3    0.4   0.4   0.2   0.5   0.1
  2.|-- dns.google                 0.0%     3  109.0 128.3 109.0 160.9  28.4


===================================================
  6. DNS lookups  --  nslookup, dig, host
===================================================
$ nslookup github.com
Server:		192.168.65.7
Address:	192.168.65.7#53

Non-authoritative answer:
Name:	github.com
Address: 20.207.73.82


$ dig github.com +short
20.207.73.82

$ dig github.com

; <<>> DiG 9.18.39-0ubuntu0.24.04.7-Ubuntu <<>> github.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 19665
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0

;; QUESTION SECTION:
;github.com.			IN	A

;; ANSWER SECTION:
github.com.		40	IN	A	20.207.73.82

;; Query time: 3 msec
;; SERVER: 192.168.65.7#53(192.168.65.7) (UDP)
;; WHEN: Thu Sep 03 05:11:01 UTC 2026
;; MSG SIZE  rcvd: 54


$ dig google.com MX +short
10 smtp.google.com.

$ dig -x 8.8.8.8 +short
dns.google.

$ host github.com
github.com has address 20.207.73.82
github.com mail is handled by 0 github-com.mail.protection.outlook.com.

$ cat /etc/resolv.conf
# Generated by Docker Engine.
# This file can be edited; Docker Engine will not make further changes once it
# has been modified.

nameserver 192.168.65.7

# Based on host file: '/etc/resolv.conf' (legacy)
# Overrides: []

$ cat /etc/hosts
127.0.0.1	localhost
::1	localhost ip6-localhost ip6-loopback
fe00::	ip6-localnet
ff00::	ip6-mcastprefix
ff02::1	ip6-allnodes
ff02::2	ip6-allrouters
172.17.0.2	ff4c4be986b8


===================================================
  7. ss / netstat  --  which ports are open and who is listening?
===================================================
$ ss -tuln
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*          
tcp   LISTEN 0      511             [::]:80           [::]:*          

$ ss -tulnp
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess                                                                                                                                                                                                                         
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=1070,fd=5),("nginx",pid=1069,fd=5),("nginx",pid=1068,fd=5),("nginx",pid=1067,fd=5),("nginx",pid=1065,fd=5),("nginx",pid=1064,fd=5),("nginx",pid=1063,fd=5),("nginx",pid=1062,fd=5),("nginx",pid=1061,fd=5))
tcp   LISTEN 0      511             [::]:80           [::]:*    users:(("nginx",pid=1070,fd=6),("nginx",pid=1069,fd=6),("nginx",pid=1068,fd=6),("nginx",pid=1067,fd=6),("nginx",pid=1065,fd=6),("nginx",pid=1064,fd=6),("nginx",pid=1063,fd=6),("nginx",pid=1062,fd=6),("nginx",pid=1061,fd=6))

$ ss -s
Total: 56
TCP:   66 (estab 0, closed 64, orphaned 0, timewait 1)

Transport Total     IP        IPv6
RAW	  0         0         0        
UDP	  0         0         0        
TCP	  2         1         1        
INET	  2         1         1        
FRAG	  0         0         0        


$ netstat -tuln
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State      
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN     
tcp6       0      0 :::80                   :::*                    LISTEN     

$ netstat -i
Kernel Interface table
Iface             MTU    RX-OK RX-ERR RX-DRP RX-OVR    TX-OK TX-ERR TX-DRP TX-OVR Flg
eth0            65535     5813      0      0 0          4379      0      0      0 BMRU
lo              65536       74      0      0 0            74      0      0      0 LRU

$ netstat -rn
Kernel IP routing table
Destination     Gateway         Genmask         Flags   MSS Window  irtt Iface
0.0.0.0         172.17.0.1      0.0.0.0         UG        0 0          0 eth0
172.17.0.0      0.0.0.0         255.255.0.0     U         0 0          0 eth0


===================================================
  8. curl / wget  --  make HTTP requests
===================================================
$ curl -s -o /dev/null -w 'HTTP status: %{http_code}\nTotal time: %{time_total}s\nRemote IP: %{remote_ip}\n' https://github.com
HTTP status: 200
Total time: 1.572165s
Remote IP: 20.207.73.82

$ curl -I https://api.github.com
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed

  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
  0  2396    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
HTTP/2 200 
date: Thu, 03 Sep 2026 05:10:51 GMT
cache-control: public, max-age=60, s-maxage=60
vary: Accept,Accept-Encoding, Accept, X-Requested-With
x-github-api-version-selected: 2022-11-28
access-control-expose-headers: ETag, Link, Location, Retry-After, X-GitHub-OTP, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Used, X-RateLimit-Resource, X-RateLimit-Reset, X-OAuth-Scopes, X-Accepted-OAuth-Scopes, X-Poll-Interval, X-GitHub-Media-Type, X-GitHub-SSO, X-GitHub-Request-Id, Deprecation, Sunset, Warning
access-control-allow-origin: *
strict-transport-security: max-age=31536000; includeSubdomains; preload
x-frame-options: deny
x-content-type-options: nosniff
x-xss-protection: 0
referrer-policy: origin-when-cross-origin, strict-origin-when-cross-origin
content-security-policy: default-src 'none'
server: github.com
content-type: application/json; charset=utf-8
x-github-media-type: github.v3; format=json
etag: W/"4f825cc84e1c733059d46e76e6df9db557ae5254f9625dfe8e1b09499c449438"
accept-ranges: bytes
x-ratelimit-limit: 60
x-ratelimit-remaining: 56
x-ratelimit-used: 4
x-ratelimit-resource: core
x-ratelimit-reset: 1788413435
content-length: 2396
x-github-request-id: F5AC:29BBAD:30CFA2:3608B8:6A990167
x-github-edge-region: centralindia


$ curl -s https://api.github.com/zen
Approachable is better than simple.
$ curl -s ifconfig.me; echo
106.192.251.38

$ wget -q -O - https://api.github.com/zen; echo
Approachable is better than simple.


===================================================
  9. nc (netcat)  --  test whether a TCP port is open
===================================================
$ nc -zv github.com 443
Connection to github.com (20.207.73.82) 443 port [tcp/https] succeeded!

$ nc -zv github.com 80
Connection to github.com (20.207.73.82) 80 port [tcp/http] succeeded!

$ nc -zv -w 3 github.com 12345
nc: connect to github.com (20.207.73.82) port 12345 (tcp) timed out: Operation now in progress

$ nc -zv 127.0.0.1 80
Connection to 127.0.0.1 80 port [tcp/http] succeeded!


===================================================
  10. arp  --  IP-to-MAC address table (layer 2)
===================================================
$ arp -n
Address                  HWtype  HWaddress           Flags Mask            Iface
172.17.0.1               ether   62:e5:3a:24:1e:65   C                     eth0

$ ip neigh show
172.17.0.1 dev eth0 lladdr 62:e5:3a:24:1e:65 REACHABLE 


===================================================
  11. Interface details and statistics
===================================================
$ ip -s link show eth0
11: eth0@if25: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65535 qdisc noqueue state UP mode DEFAULT group default 
    link/ether e6:85:22:bb:eb:ea brd ff:ff:ff:ff:ff:ff link-netnsid 0
    RX:  bytes packets errors dropped  missed   mcast           
      53075865    5933      0       0       0       0 
    TX:  bytes packets errors dropped carrier collsns           
        315731    4502      0       0       0       0 

$ ethtool eth0 2>&1 | head -12
Settings for eth0:
	Supported ports: [  ]
	Supported link modes:   Not reported
	Supported pause frame use: No
	Supports auto-negotiation: No
	Supported FEC modes: Not reported
	Advertised link modes:  Not reported
	Advertised pause frame use: No
	Advertised auto-negotiation: No
	Advertised FEC modes: Not reported
	Speed: 10000Mb/s
	Duplex: Full

$ cat /sys/class/net/eth0/address
e6:85:22:bb:eb:ea

$ cat /sys/class/net/eth0/mtu
65535


===================================================
  12. tcpdump  --  capture live packets
===================================================
$ tcpdump -i eth0 -c 5 -nn icmp & sleep 1; ping -c 3 8.8.8.8 >/dev/null 2>&1; wait
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
05:11:12.740849 IP 172.17.0.2 > 8.8.8.8: ICMP echo request, id 35081, seq 1, length 64
05:11:13.159566 IP 8.8.8.8 > 172.17.0.2: ICMP echo reply, id 35081, seq 1, length 64
05:11:13.747145 IP 172.17.0.2 > 8.8.8.8: ICMP echo request, id 35081, seq 2, length 64
05:11:13.904628 IP 8.8.8.8 > 172.17.0.2: ICMP echo reply, id 35081, seq 2, length 64
05:11:14.753833 IP 172.17.0.2 > 8.8.8.8: ICMP echo request, id 35081, seq 3, length 64
5 packets captured
6 packets received by filter
0 packets dropped by kernel


===================================================
  13. whois  --  who owns a domain?
===================================================
$ whois github.com 2>&1 | grep -iE 'domain name|registrar:|creation date|expir|name server' | head -10
   Domain Name: GITHUB.COM
   Creation Date: 2007-10-09T18:20:50Z
   Registry Expiry Date: 2026-10-09T18:20:50Z
   Registrar: MarkMonitor Inc.
   Name Server: DNS1.P08.NSONE.NET
   Name Server: DNS2.P08.NSONE.NET
   Name Server: DNS3.P08.NSONE.NET
   Name Server: DNS4.P08.NSONE.NET
   Name Server: NS-1283.AWSDNS-32.ORG
   Name Server: NS-1707.AWSDNS-21.CO.UK


===================================================
  14. Local web server test (nginx is running in this container)
===================================================
$ systemctl is-active nginx
active

$ curl -s http://localhost | head -8
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }

$ curl -sI http://localhost
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Date: Thu, 03 Sep 2026 05:11:18 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Thu, 03 Sep 2026 04:19:23 GMT
Connection: keep-alive
ETag: "6a98f54b-267"
Accept-Ranges: bytes


$ ss -tlnp | grep :80
LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=1070,fd=5),("nginx",pid=1069,fd=5),("nginx",pid=1068,fd=5),("nginx",pid=1067,fd=5),("nginx",pid=1065,fd=5),("nginx",pid=1064,fd=5),("nginx",pid=1063,fd=5),("nginx",pid=1062,fd=5),("nginx",pid=1061,fd=5))
LISTEN 0      511             [::]:80           [::]:*    users:(("nginx",pid=1070,fd=6),("nginx",pid=1069,fd=6),("nginx",pid=1068,fd=6),("nginx",pid=1067,fd=6),("nginx",pid=1065,fd=6),("nginx",pid=1064,fd=6),("nginx",pid=1063,fd=6),("nginx",pid=1062,fd=6),("nginx",pid=1061,fd=6))
```

</details>

## Reproducing this

```bash
docker exec linux-lab bash /root/net-lab.sh
```

or on any Linux box with the tools installed:

```bash
sudo apt install -y iproute2 net-tools dnsutils traceroute mtr-tiny \
                    netcat-openbsd whois tcpdump curl wget ca-certificates
bash scripts/net-lab.sh
```

## Reference repos from the session

- <https://github.com/Nency-Ravaliya/Network-Troubleshooting>
- <https://github.com/Nency-Ravaliya/OSI-Network-devices>
- <https://github.com/Nency-Ravaliya/Networking>
- <https://github.com/Nency-Ravaliya/Subnetting>
- <https://github.com/Nency-Ravaliya/IP-quest>
- <https://github.com/Nency-Ravaliya/IPFIX-NETFLOW-NTP>
- <https://github.com/Nency-Ravaliya/How-DHCP-Works>
