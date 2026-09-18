# Homework 10 — Kubernetes Services, DNS & Pod Identity

Course session: **`session-11-kubernetes-services`**.

Twelve tasks: the four ports, all five Service types, Services without selectors, CoreDNS and
the `ndots:5` trap, the Deployment-vs-StatefulSet identity drill, a workload-controller matrix,
cloud cost analysis, and a full diagnosis of why `<node-ip>:<nodePort>` does not work on macOS.

**All output blocks are extracted verbatim** from the transcripts in [`outputs/`](outputs).
Cluster: the two-node Minikube from [Homework 8](../08-k8s-fundamentals).

---

# Task 1 — The four ports

```
 External client
        │
        │  http://192.168.49.2:30080
        ▼
 ┌─────────────────────────────────────────┐
 │  every NODE, kernel iptables/nftables   │   nodePort  30080   (30000-32767)
 └──────────────────┬──────────────────────┘
                    │  DNAT
                    ▼
 ┌─────────────────────────────────────────┐
 │  Service ClusterIP  10.100.66.42        │   port       8080   (what in-cluster clients dial)
 └──────────────────┬──────────────────────┘
                    │  DNAT to one endpoint
                    ▼
 ┌─────────────────────────────────────────┐
 │  Pod  10.244.1.59                       │   targetPort   80   (the port ON the pod)
 └──────────────────┬──────────────────────┘
                    ▼
            nginx process                      containerPort  80   (documentation only)
```

Straight from the API schema rather than from memory:

```console
$ kubectl explain pod.spec.containers.ports.containerPort
KIND:       Pod
VERSION:    v1
FIELD: containerPort <integer>
DESCRIPTION:
    Number of port to expose on the pod's IP address. This must be a valid port
    number, 0 < x < 65536.

$ kubectl explain service.spec.ports.port
FIELD: port <integer>
DESCRIPTION:
    The port that will be exposed by this service.

$ kubectl explain service.spec.ports.targetPort
FIELD: targetPort <IntOrString>
DESCRIPTION:
    Number or name of the port to access on the pods targeted by the service.
    Number must be in the range 1 to 65535. Name must be an IANA_SVC_NAME. If
    this is a string, it will be looked up as a named port in the target Pod's
    container ports. If this is not specified, the value of the 'port' field is
    used (an identity map). This field is ignored for services with
    clusterIP=None, and should be omitted or set equal to the 'port' field.

$ kubectl explain service.spec.ports.nodePort
FIELD: nodePort <integer>
DESCRIPTION:
    The port on each node on which this service is exposed when type is NodePort
```

Three things the schema makes explicit that the diagram cannot:

1. **`targetPort` defaults to `port`** — "If this is not specified, the value of the `port`
   field is used (an identity map)." Most manifests set both purely for readability.
2. **`targetPort` may be a *name*** (`IntOrString`). Write `targetPort: web` and it resolves
   against a `containerPort` named `web` in the pod. That is the one situation where
   `containerPort` stops being decorative and becomes load-bearing.
3. **`targetPort` is ignored for headless Services** (`clusterIP: None`) — there is no proxy in
   the path to rewrite anything (Task 6).

The Task 2 Service is the whole table in one object: `port: 8080`, `targetPort: 80`. Clients
dial `8080`; nginx has never heard of `8080`.

---

# Task 2 — ClusterIP

```console
$ kubectl get pods -l app=web-clusterip -o wide
NAME                                 READY   STATUS    RESTARTS   AGE   IP            NODE           NOMINATED NODE   READINESS GATES
web-app-clusterip-66865d4855-ghktb   1/1     Running   0          2s    10.244.0.23   minikube       <none>           <none>
web-app-clusterip-66865d4855-wnsrl   1/1     Running   0          2s    10.244.1.59   minikube-m02   <none>           <none>
web-app-clusterip-66865d4855-wxzst   1/1     Running   0          2s    10.244.1.60   minikube-m02   <none>           <none>

$ kubectl get svc web-service-clusterip
NAME                    TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
web-service-clusterip   ClusterIP   10.100.66.42   <none>        8080/TCP   2s

$ kubectl get endpoints web-service-clusterip
NAME                    ENDPOINTS                                      AGE
web-service-clusterip   10.244.0.23:80,10.244.1.59:80,10.244.1.60:80   2s
```

The endpoint list is exactly the three pod IPs, on port **80** — `targetPort`, not `port`.
Nobody typed those IPs; the endpoint controller built the list by running the Service's selector
over the pods.

EndpointSlice is the modern form of the same data (`kubectl get endpoints` now prints a
deprecation warning on v1.33+):

```console
$ kubectl get endpointslices -l kubernetes.io/service-name=web-service-clusterip
NAME                          ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
web-service-clusterip-l68xw   IPv4          80      10.244.1.60,10.244.1.59,10.244.0.23   2s

$ kubectl describe svc web-service-clusterip
Name:                     web-service-clusterip
Namespace:                default
Selector:                 app=web-clusterip
Type:                     ClusterIP
IP:                       10.100.66.42
Port:                     http  8080/TCP
TargetPort:               80/TCP
Endpoints:                10.244.1.60:80,10.244.1.59:80,10.244.0.23:80
Session Affinity:         None
Internal Traffic Policy:  Cluster
```

Three ways to reach it from inside the cluster, all equivalent:

```console
$ kubectl exec curl-client -- curl -s http://web-service-clusterip:8080 | grep -i '<title>'
<title>Welcome to nginx!</title>

$ kubectl exec curl-client -- curl -s http://web-service-clusterip.default.svc.cluster.local:8080 | grep -i '<title>'
<title>Welcome to nginx!</title>

$ kubectl exec curl-client -- curl -s http://10.100.66.42:8080 | grep -i '<title>'
<title>Welcome to nginx!</title>
```

## The ClusterIP is not a machine

```console
$ kubectl exec curl-client -- ping -c 2 -W 2 10.100.66.42; echo "exit code: $?"
PING 10.100.66.42 (10.100.66.42): 56 data bytes
--- 10.100.66.42 ping statistics ---
2 packets transmitted, 0 packets received, 100% packet loss
command terminated with exit code 1
```

**100% packet loss on an address that serves HTTP perfectly.** No NIC anywhere owns
`10.100.66.42`. It exists only as a set of DNAT rules in each node's kernel, and those rules
match TCP port 8080 — an ICMP echo matches nothing and is dropped. "I can't ping the service"
is therefore never evidence of a problem.

## Proving it load-balances

The first attempt at this used `curl -w '%{remote_ip}'` and got a useless answer:

```console
$ kubectl exec curl-client -- sh -c 'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{remote_ip}\n" http://web-service-clusterip:8080; done' | sort | uniq -c
  20 10.100.66.42
```

`%{remote_ip}` reports the address **curl dialled**, and the DNAT happens in the kernel after
curl is done — so it always shows the VIP. Giving each pod a distinguishable page works:

```console
$ kubectl get pods -l app=web-clusterip -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.podIP}{"\n"}{end}'
web-app-clusterip-66865d4855-ghktb 10.244.0.23
web-app-clusterip-66865d4855-wnsrl 10.244.1.59
web-app-clusterip-66865d4855-wxzst 10.244.1.60

$ kubectl exec curl-client -- sh -c 'for i in $(seq 1 30); do curl -s http://web-service-clusterip:8080/whoami.txt; done' | sort | uniq -c
  15 served-by: web-app-clusterip-66865d4855-ghktb
  10 served-by: web-app-clusterip-66865d4855-wnsrl
   5 served-by: web-app-clusterip-66865d4855-wxzst
```

All three pods answered. The split is 15/10/5, not 10/10/10 — kube-proxy picks a backend at
**random per connection**, not round-robin, so 30 samples are nowhere near enough to look even.
That randomness is exactly the mechanism the canary split in
[Homework 9, Task 12](../09-k8s-core-objects#task-12--canary-deployment) rides on.

---

# Task 3 — NodePort

```yaml
type: NodePort
ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
```

```console
$ kubectl get svc web-service-nodeport
NAME                   TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
web-service-nodeport   NodePort   10.98.175.186   <none>        80:30080/TCP   1s
```

`80:30080/TCP` — the Service port, then the node port. A NodePort Service **still has a
ClusterIP**; the node port is an extra door, not a replacement.

Two pods, one per node:

```console
$ kubectl get pods -l app=web-nodeport -o wide
NAME                              READY   STATUS    RESTARTS   AGE   IP            NODE           NOMINATED NODE   READINESS GATES
web-app-nodeport-6c8f48bd-hvxt2   1/1     Running   0          42s   10.244.0.24   minikube       <none>           <none>
web-app-nodeport-6c8f48bd-ktvp4   1/1     Running   0          42s   10.244.1.62   minikube-m02   <none>           <none>
```

The claim to test is that the port is open on **every** node. Checking from each node's own
network namespace, all four combinations:

```console
$ docker exec minikube curl -s -o /dev/null -w 'node minikube     -> 192.168.49.2:30080 = %{http_code}\n' --max-time 5 http://192.168.49.2:30080
node minikube     -> 192.168.49.2:30080 = 200
$ docker exec minikube-m02 curl -s -o /dev/null -w 'node minikube-m02 -> 192.168.49.2:30080 = %{http_code}\n' --max-time 5 http://192.168.49.2:30080
node minikube-m02 -> 192.168.49.2:30080 = 200
$ docker exec minikube curl -s -o /dev/null -w 'node minikube     -> 192.168.49.3:30080 = %{http_code}\n' --max-time 5 http://192.168.49.3:30080
node minikube     -> 192.168.49.3:30080 = 200
$ docker exec minikube-m02 curl -s -o /dev/null -w 'node minikube-m02 -> 192.168.49.3:30080 = %{http_code}\n' --max-time 5 http://192.168.49.3:30080
node minikube-m02 -> 192.168.49.3:30080 = 200
```

And the rule count confirms kube-proxy programmed both kernels identically:

```console
$ docker exec minikube sh -c 'iptables-save | grep -c 30080'
2
$ docker exec minikube-m02 sh -c 'iptables-save | grep -c 30080'
2
```

> **One combination did fail, and it is worth recording.** The same test run from **inside a
> pod** on `minikube-m02` reached that node's own IP but not the other node's:
>
> ```console
> $ kubectl exec curl-client -- curl -s -o /dev/null -w "%{http_code}\n" http://192.168.49.2:30080   # node minikube
> 000
> command terminated with exit code 7
> $ kubectl exec curl-client -- curl -s -o /dev/null -w "%{http_code}\n" http://192.168.49.3:30080   # node minikube-m02
> 200
> ```
>
> The node hosts prove the NodePort is genuinely open on both nodes, so this is specific to the
> **pod → remote node IP** path under kindnet in multi-node minikube, not to the Service. It is
> also not a path anything real uses: pods talk to each other through the ClusterIP, and
> external clients come in from outside the pod network entirely.

From macOS, the node IP is unreachable — which is Task 12's entire subject:

```console
$ curl --connect-timeout 5 -s -o /dev/null -w '%{http_code}\n' http://$(minikube ip):30080 || echo 'connection failed, as expected on the docker driver'
000
connection failed, as expected on the docker driver
```

---

# Task 4 — LoadBalancer

```console
$ kubectl get svc web-service-loadbalancer
NAME                       TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
web-service-loadbalancer   LoadBalancer   10.108.100.161   <pending>     80:31710/TCP   2s
```

**`EXTERNAL-IP: <pending>`, and it will stay that way forever.** `type: LoadBalancer` is a
*request* addressed to a cloud controller manager. On AWS that controller creates an NLB and
writes its hostname back into `status.loadBalancer`; a bare Minikube has no such controller, so
nobody ever answers.

The important structural point — a LoadBalancer is a strict superset:

```console
$ kubectl describe svc web-service-loadbalancer | grep -E 'Type|IP:|Port|NodePort|Endpoints'
Type:                     LoadBalancer
IP:                       10.108.100.161
Port:                     http  80/TCP
TargetPort:               80/TCP
NodePort:                 http  31710/TCP
Endpoints:                10.244.1.64:80,10.244.1.63:80,10.244.0.25:80
```

```
            ClusterIP   ─ virtual IP + endpoints
  NodePort  = ClusterIP + a port on every node
LoadBalancer = NodePort + an external IP asked of the cloud provider
```

Kubernetes allocated `nodePort 31710` without being asked. That is how real cloud load balancers
work: the LB's target group points at `<every node>:31710`, and kube-proxy takes it from there.

## Reaching it without sudo

`minikube tunnel` is the documented fix, but it needs root to write host routes and bind
privileged ports:

```console
$ sudo -n true 2>&1; echo "exit code: $?"
sudo: a password is required
exit code: 1
```

So `minikube service --url`, which opens a plain loopback forwarder, was used instead:

```console
$ minikube service web-service-loadbalancer --url
http://127.0.0.1:61254
! Because you are using a Docker driver on darwin, the terminal needs to be open to run it.

$ curl -I -s --max-time 10 http://127.0.0.1:61254 | head -4
HTTP/1.1 200 OK
Server: nginx/1.25.5
Date: Fri, 18 Sep 2026 00:20:31 GMT
Content-Type: text/html

$ curl -s --max-time 10 http://127.0.0.1:61254 | grep -i '<title>'
<title>Welcome to nginx!</title>
```

> **To reproduce the tunnel yourself**, run this in your own terminal and enter your password
> when prompted — it must stay open:
>
> ```bash
> minikube tunnel
> # then, in another terminal:
> kubectl get svc web-service-loadbalancer   # EXTERNAL-IP becomes 127.0.0.1
> curl -s http://127.0.0.1 | grep -i '<title>'
> ```

Meanwhile the Service works perfectly from inside the cluster, external IP or not:

```console
$ kubectl exec curl-client -- curl -s http://web-service-loadbalancer | grep -i '<title>'
<title>Welcome to nginx!</title>
```

---

# Task 5 — ExternalName

```yaml
type: ExternalName
externalName: nencyravaliya.me
```

```console
$ kubectl get svc external-database-service
NAME                        TYPE           CLUSTER-IP   EXTERNAL-IP        PORT(S)   AGE
external-database-service   ExternalName   <none>       nencyravaliya.me   <none>    1s

$ kubectl get endpoints external-database-service; echo "exit code: $?"
Error from server (NotFound): endpoints "external-database-service" not found
exit code: 1
```

No ClusterIP, **no `PORT(S)` at all**, and no Endpoints object — not an empty one, none. An
ExternalName Service is a pure CoreDNS record; there is no proxying, so there is nothing to
proxy to.

```console
$ kubectl exec dns-test-client -- nslookup external-database-service.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53
external-database-service.default.svc.cluster.local	canonical name = nencyravaliya.me
```

The CNAME works exactly as designed. The `curl` through it, however, did not:

```console
$ kubectl exec dns-test-client -- curl -s -o /dev/null -w 'http_code=%{http_code} resolved_ip=%{remote_ip}\n' -k --max-time 10 https://external-database-service
http_code=000 resolved_ip=
command terminated with exit code 6
```

> **The course manifest points at a domain that does not exist.** curl exit 6 is "couldn't
> resolve host", and the reason is the *target*, not the alias:
>
> ```console
> $ kubectl exec dns-test-client -- nslookup nencyravaliya.me
> ** server can't find nencyravaliya.me: NXDOMAIN
>
> $ nslookup nencyravaliya.me          # from the macOS host, outside the cluster entirely
> ** server can't find nencyravaliya.me: NXDOMAIN
> ```
>
> Same NXDOMAIN from the host, so cluster DNS is fine — `nencyravaliya.me` simply is not
> registered.

Repeating the task against a domain that does resolve
([`manifests/04-externalname/service-github.yaml`](manifests/04-externalname/service-github.yaml),
written here):

```console
$ kubectl get svc external-api-service
NAME                   TYPE           CLUSTER-IP   EXTERNAL-IP      PORT(S)   AGE
external-api-service   ExternalName   <none>       api.github.com   <none>    0s

$ kubectl exec dns-test-client -- nslookup external-api-service.default.svc.cluster.local
external-api-service.default.svc.cluster.local	canonical name = api.github.com
Name:	api.github.com
Address: 20.207.73.85
```

The alias resolves through to a real address. The request still failed, with a different and
much more instructive error:

```console
$ kubectl exec dns-test-client -- curl -sv -o /dev/null --max-time 15 https://external-api-service 2>&1 | grep -E 'Connected to|subject:|certificate'
* Connected to external-api-service (20.207.73.85) port 443
* Server certificate:
*  subject: CN=*.github.com
* SSL: no alternative certificate subject name matches target host name 'external-api-service'

$ kubectl exec dns-test-client -- curl -sk -o /dev/null -w 'http_code=%{http_code} resolved_ip=%{remote_ip}\n' --max-time 15 https://external-api-service
http_code=400 resolved_ip=20.207.73.85
```

**This is the real operational catch with ExternalName.** The connection reached GitHub, but
curl sent SNI `external-api-service`, and GitHub's certificate says `CN=*.github.com` — so TLS
verification fails. The alias changes the *name the client dials*, and TLS verifies names. Any
HTTPS backend behind an ExternalName needs the client to override SNI/Host, which usually
defeats the point of having the alias.

**Where ExternalName genuinely fits:** giving in-cluster code a stable internal name for an
external plain-TCP dependency — `postgres.default.svc.cluster.local` today pointing at an RDS
hostname, switched to a real in-cluster StatefulSet later without touching a single line of
application config.

---

# Task 6 — Headless Service (`clusterIP: None`)

```console
$ kubectl get svc web-service-headless
NAME                   TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
web-service-headless   ClusterIP   None         <none>        80/TCP    4s

$ kubectl get endpoints web-service-headless
NAME                   ENDPOINTS                                      AGE
web-service-headless   10.244.0.26:80,10.244.1.66:80,10.244.1.68:80   4s
```

`CLUSTER-IP: None`, but the endpoints are still tracked. The difference is what DNS answers:

```console
$ kubectl exec headless-dns-client -- nslookup web-service-headless
Server:		10.96.0.10
Address:	10.96.0.10:53
Name:	web-service-headless.default.svc.cluster.local
Address: 10.244.1.68
Name:	web-service-headless.default.svc.cluster.local
Address: 10.244.0.26
Name:	web-service-headless.default.svc.cluster.local
Address: 10.244.1.66
```

**Three A records — the pod IPs themselves.** Compare with the ClusterIP Service from Task 2,
queried from the same pod moments later:

```console
$ kubectl exec headless-dns-client -- nslookup web-service-clusterip
Name:	web-service-clusterip.default.svc.cluster.local
Address: 10.100.66.42
```

One virtual IP. That is the entire distinction: a headless Service hands the client the full
membership list and gets out of the way. There is no kube-proxy in the path, no load balancing,
no DNAT — the client picks.

Because the StatefulSet names its pods deterministically, each gets a permanent DNS name:

```console
$ kubectl exec headless-dns-client -- nslookup web-stateful-0.web-service-headless.default.svc.cluster.local
Name:	web-stateful-0.web-service-headless.default.svc.cluster.local
Address: 10.244.1.66

$ kubectl exec headless-dns-client -- nslookup web-stateful-1.web-service-headless.default.svc.cluster.local
Name:	web-stateful-1.web-service-headless.default.svc.cluster.local
Address: 10.244.0.26

$ kubectl exec headless-dns-client -- curl -s http://web-stateful-0.web-service-headless | grep -i '<title>'
<title>Welcome to nginx!</title>
```

`<pod>.<headless-service>.<namespace>.svc.cluster.local` — this is why a Kafka broker list or a
MongoDB replica-set config can be written by hand and stay correct across restarts. A
load-balanced VIP is useless to a database client that must reach **the primary**, specifically.

---

# Task 7 — A Service with no selector

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-legacy-db
spec:
  ports:
    - protocol: TCP
      port: 3306
      targetPort: 3306
```

No `selector`. Kubernetes allocates the VIP and then does nothing else:

```console
$ kubectl get svc external-legacy-db
NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
external-legacy-db   ClusterIP   10.103.139.57   <none>        3306/TCP   0s

$ kubectl get endpoints external-legacy-db
Error from server (NotFound): endpoints "external-legacy-db" not found

$ kubectl describe svc external-legacy-db | grep -E 'Selector|Endpoints'
Selector:                 <none>
Endpoints:                <none>
```

The Endpoints object does not exist, because the endpoint controller **only manages Endpoints
for Services that have a selector**. Writing one by hand, name-matched to the Service:

```yaml
apiVersion: v1
kind: Endpoints
metadata:
  name: external-legacy-db     # must equal the Service name — that is the entire binding
subsets:
  - addresses:
      - ip: 192.168.1.150
    ports:
      - port: 3306
```

```console
$ kubectl apply -f 06-no-selector/external-legacy-endpoints.yaml
endpoints/external-legacy-db created

$ kubectl get endpoints external-legacy-db
NAME                 ENDPOINTS            AGE
external-legacy-db   192.168.1.150:3306   0s

$ kubectl describe svc external-legacy-db | grep -E 'Selector|Endpoints'
Selector:                 <none>
Endpoints:                192.168.1.150:3306
```

`Selector: <none>` and yet `Endpoints: 192.168.1.150:3306`. In-cluster code now connects to
`external-legacy-db:3306` and lands on a machine that is not in the cluster and never will be.

**ExternalName vs no-selector Service** — both point outward, very differently:

| | ExternalName | Service without selector |
|---|---|---|
| Mechanism | DNS CNAME | real ClusterIP + hand-written Endpoints |
| Target | a **hostname** | an **IP address** |
| kube-proxy involved | no | yes — real DNAT |
| Works for TLS clients | breaks SNI (Task 5) | fine; the client still dials the Service name |
| Use when | the external thing has a stable DNS name | you have IPs, or need the VIP indirection |

The clean use of the no-selector form: run the Service and Endpoints as separate objects, then
migrate by deleting the manual Endpoints and adding a selector — the Service name and every
client config stay untouched.

---

# Task 8 — CoreDNS, FQDNs and `ndots:5`

```console
$ kubectl exec curl-client -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

Three lines, and every DNS behaviour in this homework follows from them.

```
web-service-clusterip . default . svc . cluster.local
        │                 │        │         │
     service          namespace   type   cluster domain
```

```console
$ kubectl exec curl-client -- nslookup web-service-clusterip
** server can't find web-service-clusterip.cluster.local: NXDOMAIN
** server can't find web-service-clusterip.svc.cluster.local: NXDOMAIN
Name:	web-service-clusterip.default.svc.cluster.local
Address: 10.100.66.42

$ kubectl exec curl-client -- nslookup web-service-clusterip.default.svc.cluster.local
Name:	web-service-clusterip.default.svc.cluster.local
Address: 10.100.66.42
```

Look at the NXDOMAIN lines: the short name was tried against **every** search suffix, and only
one matched. The FQDN went straight through with no failures at all. That is the cost, made
visible.

```console
$ kubectl exec curl-client -- nslookup web-service-clusterip.default
** server can't find web-service-clusterip.default: NXDOMAIN
```

`web-service-clusterip.default` has one dot — still under `ndots:5`, so it gets the search
suffixes appended too, and `web-service-clusterip.default.default.svc.cluster.local` does not
exist. **A partial name is not a shortcut; it is a different query.**

## Measuring the `ndots:5` penalty

`api.github.com` has 2 dots, fewer than 5, so it is treated as relative and tried against all
three cluster suffixes **before** anyone asks the internet.

The first attempt at timing this used busybox's built-in `time`, which has 10 ms resolution and
reported `0.00s` for both cases — useless. Measured from the host across 30 lookups instead:

```console
$ time kubectl exec curl-client -- sh -c "for i in \$(seq 1 30); do nslookup api.github.com  >/dev/null 2>&1; done"   # relative, 2 dots
kubectl exec curl-client -- sh -c   0.06s user 0.08s system 23% cpu 0.603 total

$ time kubectl exec curl-client -- sh -c "for i in \$(seq 1 30); do nslookup api.github.com. >/dev/null 2>&1; done"   # rooted, skips the search path
kubectl exec curl-client -- sh -c   0.06s user 0.02s system 37% cpu 0.205 total
```

**0.603 s vs 0.205 s — about 3× slower**, and the only difference is a trailing dot. Under
`ndots:5`, `api.github.com` costs 4 queries (3 doomed suffixes + 1 real); `api.github.com.` is
rooted and costs exactly 1. The ratio matches almost exactly.

Now multiply by a service that calls an external API on every request. Three wasted round trips
per call, all hitting CoreDNS. This is the single most common cause of "our cluster's DNS is
slow" — and CoreDNS is not slow, it is answering four times as many queries as it should.

The fixes, in order of preference:

1. **Trailing dot** — `https://api.stripe.com./v1/charges`. One character, zero infrastructure.
2. **`dnsConfig: {options: [{name: ndots, value: "2"}]}`** on pods that mostly talk outward.
3. **NodeLocal DNSCache** — a per-node DNS cache, which is what large clusters run.

```console
$ kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
NAME                       READY   STATUS    RESTARTS      AGE   IP           NODE       NOMINATED NODE   READINESS GATES
coredns-559f6c778d-gndv7   1/1     Running   1 (49m ago)   50m   10.244.0.2   minikube   <none>           <none>
```

**One** CoreDNS pod for the whole cluster, on the control-plane node. Real clusters run at
least two with anti-affinity; a single replica is a single point of failure for *every*
service-to-service call.

Its config explains why cluster names resolve instantly and external ones do not:

```
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30 {
       disable success cluster.local
       disable denial cluster.local
    }
```

Caching is **disabled for `cluster.local`** (endpoints change constantly and must never be
stale) and everything else is forwarded to the node's upstream resolver, cached for 30 s.

---

# Task 9 — Pod identity: Deployment vs StatefulSet

Before:

```console
$ kubectl get pods -l app=web-clusterip
NAME                                 READY   STATUS    RESTARTS   AGE
web-app-clusterip-66865d4855-ghktb   1/1     Running   0          2m25s
web-app-clusterip-66865d4855-wnsrl   1/1     Running   0          2m25s
web-app-clusterip-66865d4855-wxzst   1/1     Running   0          2m25s

$ kubectl get pods -l app=web-headless
NAME             READY   STATUS    RESTARTS   AGE
web-stateful-0   1/1     Running   0          81s
web-stateful-1   1/1     Running   0          80s
web-stateful-2   1/1     Running   0          78s
```

`<deployment>-<replicaset-hash>-<random>` against `<statefulset>-<ordinal>`.

```console
$ kubectl get pod web-app-clusterip-66865d4855-ghktb -o jsonpath='name=... ip=... node=...'
name=web-app-clusterip-66865d4855-ghktb ip=10.244.0.23 node=minikube

$ kubectl get pod web-stateful-0 -o jsonpath='name=... ip=... node=...'
name=web-stateful-0 ip=10.244.1.66 node=minikube-m02
```

Delete one of each:

```console
$ kubectl delete pod web-app-clusterip-66865d4855-ghktb
$ kubectl delete pod web-stateful-0

$ kubectl get pods -l app=web-clusterip
NAME                                 READY   STATUS    RESTARTS   AGE
web-app-clusterip-66865d4855-pl8wp   1/1     Running   0          30s     <- brand-new name
web-app-clusterip-66865d4855-wnsrl   1/1     Running   0          2m55s
web-app-clusterip-66865d4855-wxzst   1/1     Running   0          2m55s

$ kubectl get pods -l app=web-headless
NAME             READY   STATUS    RESTARTS   AGE
web-stateful-0   1/1     Running   0          26s     <- same name
web-stateful-1   1/1     Running   0          110s
web-stateful-2   1/1     Running   0          108s
```

| | Deployment | StatefulSet |
|---|---|---|
| deleted | `web-app-clusterip-66865d4855-ghktb` | `web-stateful-0` |
| replaced by | `web-app-clusterip-66865d4855-pl8wp` | **`web-stateful-0`** |
| name | new random suffix | identical |
| pod IP | new | new (`10.244.1.66` → `10.244.1.69`) |
| node | may move anywhere | same node, held by its PVC |
| DNS name | none of its own | **unchanged** |

The subtle part: **the IP changed for the StatefulSet pod too.** Pod IPs are never stable in
Kubernetes. What is stable is the *name*, and DNS follows it automatically:

```console
$ kubectl exec headless-dns-client -- nslookup web-stateful-0.web-service-headless.default.svc.cluster.local
Name:	web-stateful-0.web-service-headless.default.svc.cluster.local
Address: 10.244.1.69
```

Same FQDN, new address, no client reconfiguration. That is the whole promise of the
StatefulSet + headless Service pair — and the reason clustered databases are written against
hostnames, never IPs.

---

# Task 10 — Deployment vs StatefulSet vs DaemonSet

All three running at once on this cluster:

```console
$ kubectl get deploy,sts,ds
NAME                                READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/web-app-clusterip   3/3     3            3           3m21s
deployment.apps/web-app-nodeport    2/2     2            2           3m13s

NAME                            READY   AGE
statefulset.apps/web-stateful   3/3     2m17s

NAME                                DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/node-logging-agent   2         2         2       2            2           <none>          25s
```

Note the different column sets: Deployments report `UP-TO-DATE`, StatefulSets only
`READY`, DaemonSets report `DESIRED` — a number nobody configured, derived from the node count.

```console
$ kubectl get pods -o wide --sort-by=.spec.nodeName
NAME                                 READY   STATUS    RESTARTS   AGE     IP            NODE
node-logging-agent-gngvd             1/1     Running   0          25s     10.244.0.28   minikube
web-stateful-1                       1/1     Running   0          2m16s   10.244.0.26   minikube
web-app-nodeport-6c8f48bd-hvxt2      1/1     Running   0          3m13s   10.244.0.24   minikube
web-app-clusterip-66865d4855-pl8wp   1/1     Running   0          56s     10.244.0.27   minikube
web-app-clusterip-66865d4855-wnsrl   1/1     Running   0          3m21s   10.244.1.59   minikube-m02
node-logging-agent-6gch9             1/1     Running   0          25s     10.244.1.70   minikube-m02
web-app-clusterip-66865d4855-wxzst   1/1     Running   0          3m21s   10.244.1.60   minikube-m02
web-app-nodeport-6c8f48bd-ktvp4      1/1     Running   0          3m13s   10.244.1.62   minikube-m02
web-stateful-0                       1/1     Running   0          52s     10.244.1.69   minikube-m02
web-stateful-2                       1/1     Running   0          2m14s   10.244.1.68   minikube-m02
```

Exactly one `node-logging-agent` per node; the Deployment and StatefulSet pods are distributed
by the scheduler with no such guarantee (`web-app-clusterip` went 2+1, `web-stateful` went 2+1).

| Metric | Deployment | StatefulSet | DaemonSet |
|---|---|---|---|
| **Workload** | stateless services, web APIs | clustered databases, queues, consensus systems | node-level agents |
| **Pod naming** | `<deploy>-<rs-hash>-<random>` | `<name>-0`, `-1`, `-2` | `<ds>-<random>` |
| **Identity across restarts** | ephemeral — new name every time | invariant — same ordinal, same PVC, same DNS name | tied to a node |
| **Replica count** | `spec.replicas` | `spec.replicas` | **none** — derived from node count |
| **Start / stop order** | parallel, unordered | strictly sequential `0→1→2`, reversed on scale-down | parallel |
| **Storage** | shared PVC or `emptyDir` | one PVC **per ordinal** via `volumeClaimTemplates` | `hostPath` / node-local |
| **Service type** | ClusterIP / NodePort / LoadBalancer | **headless** (`clusterIP: None`) for per-pod DNS | usually none |
| **Scaling** | anywhere there is room | at the tail only | automatic as nodes join/leave |
| **Rollout** | RollingUpdate / Recreate | `RollingUpdate` (reverse ordinal) or `OnDelete` | `RollingUpdate` or `OnDelete` |
| **Examples** | nginx, Flask, Node.js, Go services | Kafka, MongoDB, Cassandra, PostgreSQL, ZooKeeper | Fluent Bit, node-exporter, Cilium, Falco |

Two fields from the schema worth knowing:

```console
$ kubectl explain statefulset.spec.podManagementPolicy
FIELD: podManagementPolicy <string>
DESCRIPTION:
    podManagementPolicy controls how pods are created during initial scale up,
    when replacing pods on nodes, or when scaling down. The default policy is
    `OrderedReady` ... The alternative policy is `Parallel` ...
```

`Parallel` gives up ordered startup while keeping ordinal names and per-ordinal PVCs — the right
choice for a stateful system whose members do not need to bootstrap in sequence.

`updateStrategy: OnDelete` (available on both StatefulSets and DaemonSets) means Kubernetes
changes nothing until *you* delete a pod — manual control for upgrades that need a human between
each step.

---

# Task 11 — Cost: why not just use LoadBalancers

```
ANTI-PATTERN — one cloud load balancer per service
  api.example.com      ──► AWS NLB #1   ($18-25/mo)  ──► ClusterIP ──► pods
  auth.example.com     ──► AWS NLB #2   ($18-25/mo)  ──► ClusterIP ──► pods
  payments.example.com ──► AWS NLB #3   ($18-25/mo)  ──► ClusterIP ──► pods
  ...
  50 services                                          ≈ $1,250 / month

BEST PRACTICE — one load balancer, Layer 7 routing behind it
  *.example.com ──► 1 AWS NLB ($18-25/mo)
                          │
                          ▼
              ┌───────────────────────┐
              │ NGINX Ingress         │   host + path rules
              │ Controller (pods)     │
              └───┬───────┬───────┬───┘
                  ▼       ▼       ▼
             ClusterIP ClusterIP ClusterIP        ← all internal, $0 each
  50 services                                      ≈ $25 / month
```

| | 50 × LoadBalancer | 1 × Ingress |
|---|---|---|
| Cloud LB cost | ~$1,250/mo | ~$25/mo |
| Public IPs | 50 | 1 |
| TLS certificates | 50 to manage | 1 wildcard, or cert-manager |
| DNS records | 50 A records to separate IPs | 50 CNAMEs to one hostname |
| Path-based routing | impossible (L4) | native (L7) |
| Per-route auth / rate limiting | no | yes, via annotations |

At ~$1,225/month saved, this is usually the single largest line item on a Kubernetes cost
review. The catch is that Ingress is **HTTP/HTTPS only** — raw TCP or UDP (a database, a game
server, syslog) still needs its own LoadBalancer, or a Gateway API implementation.

## Decision tree

```
Does anything outside the cluster need to reach this?
│
├─ NO ──► Do clients need to address individual pods (Kafka, Mongo, Cassandra)?
│          ├─ YES ──► HEADLESS SERVICE      clusterIP: None      (Task 6)
│          └─ NO  ──► CLUSTERIP             the default          (Task 2)
│
└─ YES ─► Is the backend outside the cluster (RDS, Stripe, a legacy box)?
           ├─ hostname ──► EXTERNALNAME               (Task 5 — mind the TLS/SNI trap)
           ├─ IP only  ──► SERVICE WITHOUT SELECTOR   (Task 7)
           └─ in-cluster app:
                ├─ HTTP/HTTPS ──► INGRESS in front of CLUSTERIP services   ← the default answer
                ├─ raw TCP/UDP ─► LOADBALANCER                             (Task 4)
                └─ dev / on-prem / no cloud LB ──► NODEPORT                (Task 3)
```

---

# Task 12 — Why `<node-ip>:<nodePort>` fails on macOS

The Service is healthy and its endpoints are populated:

```console
$ kubectl get svc web-service-nodeport
NAME                   TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
web-service-nodeport   NodePort   10.98.175.186   <none>        80:30080/TCP   3m

$ minikube ip
192.168.49.2
```

From macOS:

```console
$ time curl --connect-timeout 5 -s -o /dev/null -w "%{http_code}\n" http://$(minikube ip):30080
000

real	0m5.165s
```

Zero HTTP status, and it took the full 5-second connect timeout — a **timeout**, not a refusal.
Nothing answered at all.

## The diagnosis, in three commands

```console
$ docker network inspect minikube --format '{{.Name}} driver={{.Driver}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}} gateway={{range .IPAM.Config}}{{.Gateway}}{{end}}'
minikube driver=bridge subnet=192.168.49.0/24 gateway=192.168.49.1
```

The node IPs live on a **Docker bridge network** — and on macOS, Docker's bridges exist inside
the Linux VM that Docker Desktop runs, not on the Mac itself.

```console
$ ifconfig | grep -c 192.168.49
0
```

**No macOS interface holds an address in that subnet.** The Mac is not on this network.

```console
$ route -n get $(minikube ip) | head -6
   route to: 192.168.49.2
destination: default
       mask: default
    gateway: 10.114.0.1
  interface: en0
```

There is no specific route to `192.168.49.0/24`, so the packet falls through to the
**default** route and is sent out `en0` to the internet gateway — where `192.168.49.2`, a
private RFC 1918 address, is dropped. That is the timeout, precisely explained.

And the proof that nothing is wrong with Kubernetes — the identical request from inside the
cluster network:

```console
$ kubectl exec curl-client -- curl -s -o /dev/null -w '%{http_code}\n' http://192.168.49.2:30080
200
```

```
  macOS host                      Docker Desktop's Linux VM
 ┌──────────────┐                ┌──────────────────────────────────────────┐
 │              │   no route     │  docker bridge "minikube" 192.168.49.0/24│
 │  curl ──────────────✗─────────┼──►  node minikube      192.168.49.2      │
 │              │                │     node minikube-m02  192.168.49.3      │
 │              │   published    │                                          │
 │  127.0.0.1 ──────────✓────────┼──►  node's :8443 (API server only)       │
 └──────────────┘                └──────────────────────────────────────────┘
```

Only the ports Docker explicitly publishes to `127.0.0.1` are reachable — and as
[Homework 8](../08-k8s-fundamentals#the-nodes-are-docker-containers) showed, that list is
`22, 2376, 5000, 8443, 32443`. **The 30000–32767 NodePort range is not published.**

On bare-metal Linux none of this applies: the node IP is on a real interface on the real LAN,
and `curl http://<node-ip>:30080` simply works. The problem is the driver, not Kubernetes.

## Workaround 1 — `minikube service --url`

```console
$ minikube service web-service-nodeport --url
http://127.0.0.1:61232
! Because you are using a Docker driver on darwin, the terminal needs to be open to run it.

$ curl -I -s --max-time 10 http://127.0.0.1:61232 | head -5
HTTP/1.1 200 OK
Server: nginx/1.25.5
Date: Fri, 18 Sep 2026 00:19:54 GMT
Content-Type: text/html
Content-Length: 615

$ curl -s --max-time 10 http://127.0.0.1:61232 | grep -i '<title>'
<title>Welcome to nginx!</title>
```

minikube opens a forwarder from a random loopback port into the node. Note the warning: **the
terminal must stay open** — kill it and the port dies. The port is random, so it cannot be
scripted or bookmarked.

## Workaround 2 — `kubectl port-forward`

```console
$ kubectl port-forward service/web-service-nodeport 38080:80
Forwarding from 127.0.0.1:38080 -> 80
Forwarding from [::1]:38080 -> 80

$ curl -I -s --max-time 10 http://127.0.0.1:38080 | head -5
HTTP/1.1 200 OK
Server: nginx/1.25.5
Date: Fri, 18 Sep 2026 00:20:00 GMT
Content-Type: text/html
Content-Length: 615
```

Driver-independent, works against any cluster anywhere, and **you choose the port** — which is
why this is the one used to drive every Ingress test in
[Homework 11](../11-ingress-configmaps-secrets). Its limitation: it forwards to a *single* pod,
so it proves reachability but never load balancing.

## Workaround 3 — `minikube tunnel`

```console
$ minikube tunnel --help | head -3
tunnel creates a route to services deployed with type LoadBalancer and sets their Ingress to their ClusterIP.
```

The most faithful simulation — it adds a real host route and populates `EXTERNAL-IP` — and the
only one that needs `sudo`, which this session did not have (see Task 4).

| | `minikube service --url` | `kubectl port-forward` | `minikube tunnel` |
|---|---|---|---|
| sudo needed | no | no | **yes** |
| port | random | **you choose** | the Service's real port |
| load balances | yes (via nodePort) | no — one pod | yes |
| works on any cluster | minikube only | **any** | minikube only |
| populates `EXTERNAL-IP` | no | no | **yes** |

---

## Files

```
10-k8s-services/
├── README.md
├── manifests/
│   ├── 01-clusterip/     app-deployment.yaml  client-pod.yaml  service.yaml
│   ├── 02-nodeport/      app-deployment.yaml  service.yaml
│   ├── 03-loadbalancer/  app-deployment.yaml  service.yaml
│   ├── 04-externalname/  service.yaml  client-pod.yaml
│   │                     service-github.yaml        ← written here: a target that resolves
│   ├── 05-headless/      service.yaml  app-statefulset.yaml  client-pod.yaml
│   └── 06-no-selector/   external-legacy-db.yaml  external-legacy-endpoints.yaml   ← written here
├── outputs/
│   ├── task1-port-architecture.txt
│   ├── task2-clusterip.txt
│   ├── task3-nodeport.txt
│   ├── task4-loadbalancer.txt
│   ├── task5-externalname.txt
│   ├── task6-headless.txt
│   ├── task7-service-without-selector.txt
│   ├── task8-coredns-fqdn.txt
│   ├── task9-pod-identity.txt
│   ├── task10-controller-matrix.txt
│   └── task12-minikube-nodeport-gotcha.txt
└── screenshots/
```
