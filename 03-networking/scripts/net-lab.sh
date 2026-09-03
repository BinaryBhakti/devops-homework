#!/bin/bash
run() { echo "\$ $*"; timeout 25 bash -c "$*" 2>&1 | head -30; echo; }
sec() { echo; echo "==================================================="; echo "  $*"; echo "==================================================="; }

sec "1. ip addr  --  show interfaces and IP addresses"
run "ip addr show"
run "ip -brief addr show"
run "ip -4 addr show eth0"
run "hostname -I"

sec "2. ifconfig  --  the older (net-tools) equivalent of 'ip addr'"
run "ifconfig"
run "ifconfig eth0"

sec "3. ip route / route  --  the routing table (where packets go)"
run "ip route show"
run "ip route get 8.8.8.8"
run "route -n"
run "ip -brief link show"

sec "4. ping  --  is the host reachable? (ICMP echo)"
run "ping -c 4 127.0.0.1"
run "ping -c 4 8.8.8.8"
run "ping -c 4 google.com"

sec "5. traceroute / mtr  --  what path do packets take?"
run "traceroute -m 8 -w 2 8.8.8.8"
run "mtr -r -c 3 8.8.8.8"

sec "6. DNS lookups  --  nslookup, dig, host"
run "nslookup github.com"
run "dig github.com +short"
run "dig github.com"
run "dig google.com MX +short"
run "dig -x 8.8.8.8 +short"
run "host github.com"
run "cat /etc/resolv.conf"
run "cat /etc/hosts"

sec "7. ss / netstat  --  which ports are open and who is listening?"
run "ss -tuln"
run "ss -tulnp"
run "ss -s"
run "netstat -tuln"
run "netstat -i"
run "netstat -rn"

sec "8. curl / wget  --  make HTTP requests"
run "curl -s -o /dev/null -w 'HTTP status: %{http_code}\nTotal time: %{time_total}s\nRemote IP: %{remote_ip}\n' https://github.com"
run "curl -I https://api.github.com"
run "curl -s https://api.github.com/zen"
run "curl -s ifconfig.me; echo"
run "wget -q -O - https://api.github.com/zen; echo"

sec "9. nc (netcat)  --  test whether a TCP port is open"
run "nc -zv github.com 443"
run "nc -zv github.com 80"
run "nc -zv -w 3 github.com 12345"
run "nc -zv 127.0.0.1 80"

sec "10. arp  --  IP-to-MAC address table (layer 2)"
run "arp -n"
run "ip neigh show"

sec "11. Interface details and statistics"
run "ip -s link show eth0"
run "ethtool eth0 2>&1 | head -12"
run "cat /sys/class/net/eth0/address"
run "cat /sys/class/net/eth0/mtu"

sec "12. tcpdump  --  capture live packets"
run "tcpdump -i eth0 -c 5 -nn icmp & sleep 1; ping -c 3 8.8.8.8 >/dev/null 2>&1; wait"

sec "13. whois  --  who owns a domain?"
run "whois github.com 2>&1 | grep -iE 'domain name|registrar:|creation date|expir|name server' | head -10"

sec "14. Local web server test (nginx is running in this container)"
run "systemctl is-active nginx"
run "curl -s http://localhost | head -8"
run "curl -sI http://localhost"
run "ss -tlnp | grep :80"
