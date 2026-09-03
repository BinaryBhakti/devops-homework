# DevOps Homework

Completed homework for the **DevOps Heroes** sessions — Linux, Shell Scripting, Networking,
Git, Docker, Docker Multi-Stage Builds, and Docker Networking & Volumes.

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
```

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
└── 07-docker-network-volume/
    ├── README.md
    ├── bind-mount-demo/html/     the bind-mounted site
    ├── scripts/net-task1.sh
    ├── screenshots/
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

Where the macOS host behaves differently from Linux — most notably `--network host` — the
difference is documented in place rather than glossed over.
