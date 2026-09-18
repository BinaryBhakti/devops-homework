# DevOps Homework

Completed homework for the **DevOps Heroes** sessions — Linux, Shell Scripting, Networking,
Git, Docker, and Kubernetes.

Course repository: <https://github.com/Nency-Ravaliya/devops-heros>

> **Everything here was actually executed.** No output in these documents is invented or
> hand-written from memory — every `console` block is extracted verbatim from a captured
> transcript, and every transcript is committed alongside the write-up so you can check it.
> Where something failed, broke, or behaved differently than expected, that is written down
> too, along with the fix.

---

## Contents

| # | Homework | What is in it |
|---|---|---|
| 1 | **[Linux](01-linux)** | soft vs hard links, `adduser` vs `useradd`, `journalctl`, 16-category command cheat sheet |
| 2 | **[Shell Scripting](02-shell-scripting)** | `sysinfo.sh` — date, hostname, user, disk, processes, `read -p`, `mkdir`, `touch`, `>` |
| 3 | **[Networking](03-networking)** | 14 networking commands with real output and an explanation of each |
| 4 | **[Git](04-git)** | `git commit -a -m` vs `git commit -m`, and cherry-picking one commit between branches |
| 5 | **[Docker Apps](05-docker-apps)** | six Hello World apps — Node.js, Python, Java, Apache, React, Nginx |
| 6 | **[Docker Multi-Stage](06-docker-multistage)** | multi-stage build on port 8080 + measured size comparison |
| 7 | **[Docker Networking & Volumes](07-docker-network-volume)** | 3 networks / 3 containers, host network, bind mounts, overlay networks |
| 8 | **[Kubernetes Fundamentals](08-k8s-fundamentals)** | Minikube install, a **two-node** cluster lifecycle, control-plane vs worker architecture |
| 9 | **[K8s Core Objects](09-k8s-core-objects)** | pods, 12 lifecycle states, ReplicaSet/StatefulSet/DaemonSet, rolling updates, blue-green, canary, recreate |
| 10 | **[K8s Services & DNS](10-k8s-services)** | all 5 Service types, services without selectors, CoreDNS and `ndots:5`, pod identity |
| 11 | **[Ingress, ConfigMaps & Secrets](11-ingress-configmaps-secrets)** | config decoupling, base64 gotchas, NGINX Ingress, path/host routing, TLS termination |

---

## Highlights

**Linux** — run inside a real **Ubuntu 24.04 container with systemd as PID 1**, because macOS
has no `useradd`, `adduser` or `journalctl`. That is what makes the `journalctl` output genuine
rather than "no journal files were found".

**Docker apps** — all six built, run, and **screenshotted in a real headless-Chrome browser**,
not just `curl`-ed. That matters for the React app, whose `<h1>` only exists after JavaScript
runs.

**Multi-stage builds** — measured honestly on two applications:

| Application | Single-stage | Multi-stage | Saving |
|---|---|---|---|
| Node.js + Express (one dependency, no build step) | 210 MB | 199 MB | 5% |
| React + Vite (full toolchain, real build step) | 411 MB | **76.1 MB** | **81%** |

The Node result is small, and the write-up explains why rather than pretending otherwise.

**Container networking** — the three-tier isolation was proved both ways: the backend runs a
**live SQL session** against MySQL over the shared network, while the frontend cannot even
resolve the name `database` (`NXDOMAIN`).

**Bind mounts** — the live-update claim is backed by `StartedAt` and `RestartCount` being
byte-for-byte identical before and after the file edit.

**Overlay networks** — not just researched. A single-node Swarm was created, a 3-replica
service deployed on a real overlay network, the VIP and `tasks.<service>` DNS behaviour
observed, the routing mesh tested — then the machine was restored to non-swarm mode.

**Kubernetes** — run on a **two-node** Minikube cluster (`--nodes=2`), not the usual single
node, because "one DaemonSet pod per node" and "the NodePort is open on every node" only mean
something when there is more than one node.

**Deployment strategies, measured rather than described:**

| Strategy | What the transcripts show |
|---|---|
| RollingUpdate | new pod reaches `1/1` **before** any old pod is touched — `maxUnavailable: 0` proved from a live pod watch |
| Blue-Green | endpoint set flips to a completely disjoint set of pod IPs; 6/6 requests switch version with no mixed-version window |
| Canary | 4/40 requests hit the canary at a 9:1 pod ratio — **10.0%**, dead on the prediction |
| Recreate | a real **~3 second outage**, 4 consecutive failed samples from a 2 Hz polling loop |

**Three bugs in the course material, found by running it:**

- `mysql:5.7` has **no arm64 image** — `no match for platform in manifest` on Apple Silicon.
  Documented, then re-run on `mysql:8.0` to finish the StatefulSet lab.
- The `openssl` command for the TLS task produces a certificate with **no SANs**, so
  ingress-nginx silently serves its own fake certificate while still returning `HTTP/2 200`.
  Caught by reading the served certificate rather than the status code.
- The ExternalName Service points at `nencyravaliya.me`, which returns **NXDOMAIN** — from the
  macOS host too, so not a cluster problem. Re-run against a domain that resolves, which then
  exposed the real ExternalName trap: TLS SNI verification fails through the alias.

---

## Running the labs

Requirements: Docker, and Git. Everything else runs inside containers.

```bash
git clone <this-repo>
cd devops-homework
```

Each folder's README has a **"Reproducing this"** section with the exact commands.

Quick tour:

```bash
# Homework 1 & 3 — Linux + networking lab container
cd 01-linux
docker build -t linux-lab:24.04 -f Dockerfile.lab .
docker run -d --name linux-lab --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /run/lock linux-lab:24.04

# Homework 2 — the shell script
bash 02-shell-scripting/sysinfo.sh

# Homework 4 — git lab (uses throwaway repos in /tmp)
bash 04-git/scripts/git-lab.sh

# Homework 5 — six Hello World apps
cd 05-docker-apps
for app in nodejs-app python-app java-app apache-app react-app nginx-app; do
  (cd "$app" && docker build -t "hw-${app}:1.0" .)
done

# Homework 6 — multi-stage build on port 8080
cd 06-docker-multistage
docker build -t multistage-hello:1.0 .
docker run -d --name multistage-app -p 8080:8080 multistage-hello:1.0
curl http://localhost:8080

# Homework 7 — networks, host network, bind mount, overlay
bash 07-docker-network-volume/scripts/net-task1.sh

# Homework 8-11 — Kubernetes. Two-node cluster, then apply the manifests per README.
minikube start --nodes=2 --driver=docker --memory=1800 --cpus=2
kubectl get nodes -o wide
kubectl apply -f 09-k8s-core-objects/manifests/pod.yml
minikube addons enable ingress          # needed for Homework 11
```

> **On macOS with the Docker driver, `curl http://$(minikube ip):<nodePort>` will not work** —
> the Mac has no route to the node's Docker bridge subnet.
> [Homework 10, Task 12](10-k8s-services#task-12--why-node-ipnodeport-fails-on-macos) diagnoses
> it properly and gives three workarounds. Every HTTP test in Homeworks 9-11 goes through
> `kubectl port-forward` or an in-cluster `curl` pod for that reason.

### Ports used

| Port | Service |
|---|---|
| 8080 | multi-stage build app (Homework 6) |
| 9001–9006 | the six Hello World apps (Homework 5) |
| 9080 | Apache, bridge network (Homework 7) |
| 9090 | Nginx with a bind mount (Homework 7) |
| 9091 | Nginx with a named volume (Homework 7) |
| 9095 | Swarm service via the routing mesh (Homework 7) |
| 80 | Apache on the host network (Homework 7) |

### Cleaning up

```bash
docker rm -f hw-nodejs hw-python hw-java hw-apache hw-react hw-nginx \
             multistage-app frontend backend database \
             apache-host apache-bridge nginx-bind nginx-volume linux-lab
docker network rm frontend-net backend-net mgmt-net
docker volume rm demo-volume
```

---

## Repository layout
```
devops-homework/
├── 01-linux/
│   ├── README.md                 the write-up
│   ├── Dockerfile.lab            Ubuntu 24.04 + systemd lab image
│   ├── scripts/                  the four lab scripts
│   └── outputs/                  raw captured transcripts
├── 02-shell-scripting/
│   ├── README.md
│   ├── sysinfo.sh                the deliverable script
│   ├── sample-output/            process.log + summary.txt it generated
│   └── outputs/
├── 03-networking/
│   ├── README.md                 14 commands, each explained
│   ├── scripts/net-lab.sh
│   └── outputs/
├── 04-git/
│   ├── README.md                 commit -a and cherry-pick
│   ├── scripts/git-lab.sh
│   └── outputs/
├── 05-docker-apps/
│   ├── README.md
│   ├── nodejs-app/  python-app/  java-app/
│   ├── apache-app/  react-app/   nginx-app/
│   ├── screenshots/              six browser screenshots
│   └── outputs/
├── 06-docker-multistage/
│   ├── README.md
│   ├── Dockerfile                the multi-stage build
│   ├── Dockerfile.single-stage   for size comparison
│   ├── server.js  package.json
│   ├── screenshots/
│   └── outputs/
├── 07-docker-network-volume/
│   ├── README.md
│   ├── bind-mount-demo/html/     the bind-mounted site
│   ├── scripts/net-task1.sh
│   ├── screenshots/
│   └── outputs/
├── 08-k8s-fundamentals/
│   ├── README.md                 cluster lifecycle + architecture write-up
│   └── outputs/                  install, start, status, stop/restart transcripts
├── 09-k8s-core-objects/
│   ├── README.md
│   ├── manifests/                course manifests + 2 written here
│   │   ├── pod-lifecycle/        the 12 lifecycle states
│   │   ├── 01-rolling-update/  02-blue-green/  03-canary/  04-recreate/
│   │   ├── daemonset/  troubleshooting/
│   │   └── statefulset-arm64.yml the Apple Silicon fix
│   └── outputs/                  13 task transcripts
├── 10-k8s-services/
│   ├── README.md
│   ├── manifests/                01-clusterip .. 06-no-selector
│   └── outputs/
└── 11-ingress-configmaps-secrets/
    ├── README.md
    ├── manifests/                configmap, secret, ingress, full-demo
    └── outputs/
```

---

## Environment

| | |
|---|---|
| Host | macOS (Darwin 25.5.0), Apple Silicon |
| Docker | 29.7.2, Docker Desktop |
| Linux lab | Ubuntu 24.04.4 LTS with systemd as PID 1 |
| Git | 2.50.1 |
| Browser (screenshots) | Google Chrome, headless |
| Minikube | v1.39.0, docker driver, **2 nodes** |
| Kubernetes | server v1.37.0, client v1.36.1, containerd 2.3.4 |
| Ingress controller | ingress-nginx v1.15.1 (nginx 1.27.1) |

Where the macOS host behaves differently from Linux — most notably `--network host` — the
difference is documented in place rather than glossed over.
