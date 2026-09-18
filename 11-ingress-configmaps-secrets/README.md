# Homework 11 — ConfigMaps, Secrets & Ingress

Course session: **`session-12-ingress-configmaps-secrets`**.

Fourteen tasks: decoupling configuration into ConfigMaps, the fact that patching one does
nothing to running pods, Secrets and what base64 does and does not buy you, the trailing-newline
bug, the NGINX Ingress Controller, path- and host-based Layer 7 routing, TLS termination, and
the full multi-tier stack end to end.

**All output blocks are extracted verbatim** from the transcripts in [`outputs/`](outputs).
Cluster: the two-node Minikube from [Homework 8](../08-k8s-fundamentals).

Two findings worth flagging before you start, because both are bugs in the lab sheet's own
commands rather than in Kubernetes:

- **Task 13** — the `openssl` command as given produces a certificate with **no SANs**, so
  ingress-nginx silently refuses it and serves its own fake certificate. Fixed and re-verified.
- **Task 4** — `--from-literal="$(echo ...)"` does *not* reproduce the newline bug, because
  command substitution strips trailing newlines. The two places the bug actually lives are
  identified and demonstrated.

---

# Task 1 — ConfigMap

```console
$ kubectl apply -f 01-configmap/app-config.yaml
configmap/yatri-app-config created

$ kubectl get configmap yatri-app-config
NAME               DATA   AGE
yatri-app-config   5      1s

$ kubectl describe configmap yatri-app-config
Name:         yatri-app-config
Namespace:    default
Labels:       app=yatri-backend
Annotations:  <none>

Data
====
DEFAULT_CURRENCY:
----
INR
ENVIRONMENT:
----
production
LOG_LEVEL:
----
INFO
MAX_BOOKING_DAYS:
----
30
PORT:
----
5000

BinaryData
====
Events:  <none>
```

All five keys, **printed in full**. Note this for the contrast with `describe secret` in Task 3.

```console
$ kubectl get configmap yatri-app-config -o jsonpath='{.data.ENVIRONMENT}' && echo ''
production

$ kubectl get configmap yatri-app-config -o jsonpath='{.data.LOG_LEVEL}' && echo ''
INFO
```

JSONPath is how a CI pipeline reads one value without parsing YAML.

**Why this matters:** the same container image now runs in dev, staging and production. What
changes between them is a ConfigMap, not a rebuild — which is the whole point of the
[twelve-factor](https://12factor.net/config) "store config in the environment" rule.

---

# Task 2 — Patching a live ConfigMap does not touch running pods

```console
$ kubectl get configmap yatri-app-config -o jsonpath='{.data.ENVIRONMENT}' && echo ''
production

$ kubectl exec deploy/yatri-backend -- env | grep ENVIRONMENT
ENVIRONMENT=production

$ kubectl patch configmap yatri-app-config --type merge -p '{"data":{"ENVIRONMENT":"staging"}}'
configmap/yatri-app-config patched

$ kubectl get configmap yatri-app-config -o jsonpath='{.data.ENVIRONMENT}' && echo ''
staging
```

Thirty seconds later:

```console
$ kubectl exec deploy/yatri-backend -- env | grep ENVIRONMENT
ENVIRONMENT=production

$ kubectl get pods -l app=yatri-backend
NAME                             READY   STATUS    RESTARTS   AGE
yatri-backend-6c58cb99c7-pglsm   1/1     Running   0          57s
yatri-backend-6c58cb99c7-v8sws   1/1     Running   0          57s
```

**The ConfigMap says `staging`. The running pods still say `production`, and they will say it
forever.** `RESTARTS 0`, `AGE 57s` — nothing happened to them at all.

The reason is mechanical: `envFrom` is read **once**, by the kubelet, when the container is
created. The values are baked into the process's environment block, and a Linux process's
environment cannot be modified from outside. Kubernetes is not being lazy; there is no
mechanism by which this *could* update.

```console
$ kubectl rollout restart deployment/yatri-backend
deployment.apps/yatri-backend restarted

$ kubectl rollout status deployment/yatri-backend --timeout=300s
Waiting for deployment "yatri-backend" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "yatri-backend" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "yatri-backend" rollout to finish: 1 old replicas are pending termination...
deployment "yatri-backend" successfully rolled out

$ kubectl get pods -l app=yatri-backend
NAME                             READY   STATUS        RESTARTS   AGE
yatri-backend-67f597dfc8-nl7xn   1/1     Running       0          6s
yatri-backend-67f597dfc8-zqn6z   1/1     Running       0          7s
yatri-backend-6c58cb99c7-pglsm   1/1     Terminating   0          64s
yatri-backend-6c58cb99c7-v8sws   1/1     Terminating   0          64s

$ kubectl exec deploy/yatri-backend -- env | grep ENVIRONMENT
ENVIRONMENT=staging
```

New pod-template-hash (`6c58cb99c7` → `67f597dfc8`), new pods up **before** the old ones
terminate — `rollout restart` is an ordinary rolling update, so it is zero-downtime.

> **The mount exception.** A ConfigMap consumed as a **volume** does update in place — the
> kubelet refreshes the files (within about a minute, via a symlink swap). But the *application*
> still has to notice: it needs to re-read the file, or watch it with inotify. Nginx, Envoy and
> Prometheus support that; most application code does not, which is why `envFrom` + a rolling
> restart remains the common pattern.

| Consumption method | Updates live? | Application must |
|---|---|---|
| `envFrom` / `env.valueFrom.configMapKeyRef` | **no** | be restarted |
| volume mount | yes, ~60 s | re-read the file (inotify / SIGHUP) |
| `subPath` volume mount | **no** — a known trap | be restarted |

---

# Task 3 — Secrets, and what base64 is actually for

```console
$ kubectl apply -f 02-secret/db-secret.yaml
secret/yatri-db-secret created

$ kubectl get secret yatri-db-secret
NAME              TYPE     DATA   AGE
yatri-db-secret   Opaque   3      0s

$ kubectl describe secret yatri-db-secret
Name:         yatri-db-secret
Namespace:    default
Labels:       app=yatri-backend
Annotations:  <none>

Type:  Opaque

Data
====
POSTGRES_DB:        19 bytes
POSTGRES_PASSWORD:  14 bytes
POSTGRES_USER:      11 bytes
```

Compare directly with `describe configmap` in Task 1, which printed every value. `describe
secret` prints **byte counts only** — the one genuine security feature in the whole object, and
it protects against nothing more than a shoulder-surfer.

```console
$ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode && echo ''
secretpassword

$ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_USER}' | base64 --decode && echo ''
yatri_admin

$ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_DB}' | base64 --decode && echo ''
yatri_production_db
```

One pipe. No password prompt, no key, no audit gate.

```console
$ kubectl get secret yatri-db-secret -o jsonpath='{.data}' && echo ''
{"POSTGRES_DB":"eWF0cmlfcHJvZHVjdGlvbl9kYg==","POSTGRES_PASSWORD":"c2VjcmV0cGFzc3dvcmQ=","POSTGRES_USER":"eWF0cmlfYWRtaW4="}
```

**Base64 is an encoding, not encryption.** It exists so that arbitrary binary — a TLS key, a
keytab, a gzipped blob — survives a round trip through YAML and JSON, which are text formats. It
has no key and provides no confidentiality whatsoever; treat a base64 string exactly as you
would treat the plaintext.

What actually protects a Secret:

| Control | Status on this cluster |
|---|---|
| **RBAC** — who can `get secrets` | the only real control; see Task 5 |
| **Encryption at rest** (`EncryptionConfiguration` on the API server) | **not enabled** — values sit in etcd as plain base64 |
| Not mounting secrets the pod does not need | a manifest-review discipline |
| External secret store | not installed here; see Task 5 |

---

# Task 4 — The trailing-newline bug

```console
$ echo 'secretpassword' | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264 0a    secretpassword.

$ echo 'secretpassword' | base64
c2VjcmV0cGFzc3dvcmQK

$ echo -n 'secretpassword' | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264       secretpassword

$ echo -n 'secretpassword' | base64
c2VjcmV0cGFzc3dvcmQ=
```

The `0a` at the end of the first dump is the whole bug. It changes the base64 tail from
`...Q=` to `...QK` — one character, easy to miss in review:

```
c2VjcmV0cGFzc3dvcmQK    ← wrong, 15 bytes, ends in \n
c2VjcmV0cGFzc3dvcmQ=    ← right, 14 bytes
```

```console
$ echo 'c2VjcmV0cGFzc3dvcmQK' | base64 --decode | wc -c
      15
$ echo 'c2VjcmV0cGFzc3dvcmQ=' | base64 --decode | wc -c
      14
```

The course Secret is correct — verified rather than assumed:

```console
$ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264       secretpassword
```

## Where the bug actually enters — and where it does not

The lab sheet suggests reproducing it with `--from-literal="$(echo 'secretpassword')"`. That
came out **clean**, because `$(...)` strips trailing newlines:

```console
$ kubectl create secret generic broken-secret --from-literal=PASSWORD="$(echo 'secretpassword')" --dry-run=client -o yaml
apiVersion: v1
data:
  PASSWORD: c2VjcmV0cGFzc3dvcmQ=
```

So that is not where it lives. These two are.

**1. Hand-writing `echo | base64` output straight into a manifest:**

```console
$ echo 'secretpassword' | base64 > wrong.b64 && cat wrong.b64
c2VjcmV0cGFzc3dvcmQK

$ cat newline-demo.yaml
apiVersion: v1
kind: Secret
metadata:
  name: newline-demo
type: Opaque
data:
  POSTGRES_PASSWORD: c2VjcmV0cGFzc3dvcmQK

$ kubectl apply -f newline-demo.yaml
secret/newline-demo created

$ kubectl get secret newline-demo -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264 0a    secretpassword.
```

**2. `--from-file`, which reads the file byte for byte:**

```console
$ echo 'secretpassword' > pw.txt && xxd pw.txt
00000000: 7365 6372 6574 7061 7373 776f 7264 0a    secretpassword.

$ kubectl create secret generic fromfile-demo --from-file=POSTGRES_PASSWORD=pw.txt -o yaml --dry-run=client
apiVersion: v1
data:
  POSTGRES_PASSWORD: c2VjcmV0cGFzc3dvcmQK
```

Side by side:

```console
$ kubectl get secret newline-demo    -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode | wc -c
      15
$ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode | wc -c
      14
```

The failure this produces is maddening because everything *looks* right: `kubectl describe`
shows the Secret mounted, the env var is present, and the app reports
`password authentication failed for user "yatri_admin"`. The password is correct — plus one
invisible byte.

**The safe ways:**

```console
$ kubectl create secret generic safe-demo --from-literal=POSTGRES_PASSWORD=secretpassword -o yaml --dry-run=client | grep -A2 '^data'
data:
  POSTGRES_PASSWORD: c2VjcmV0cGFzc3dvcmQ=

$ printf 'secretpassword' > pw-clean.txt && xxd pw-clean.txt
00000000: 7365 6372 6574 7061 7373 776f 7264       secretpassword
$ kubectl create secret generic safe-file-demo --from-file=POSTGRES_PASSWORD=pw-clean.txt -o yaml --dry-run=client | grep -A2 '^data'
data:
  POSTGRES_PASSWORD: c2VjcmV0cGFzc3dvcmQ=
```

| Method | Result |
|---|---|
| `echo 'pw' \| base64` pasted into YAML | **broken** — trailing `\n` |
| `echo 'pw' > f` then `--from-file=f` | **broken** — file contains `\n` |
| `echo -n 'pw' \| base64` pasted into YAML | correct |
| `printf 'pw' > f` then `--from-file=f` | correct |
| `--from-literal=KEY=pw` | correct — **use this** |
| `stringData:` in the manifest (plain text, Kubernetes encodes it) | correct, and unreviewable-diff-free |

The best answer is `stringData:` — you never touch base64 at all, so the bug cannot occur.

---

# Task 5 — What this cluster has, and what production adds

```console
$ kubectl get crds 2>/dev/null | grep -i 'secret\|vault\|externalsecret' || echo 'no external-secret CRDs installed: this cluster uses native Secrets only'
no external-secret CRDs installed: this cluster uses native Secrets only

$ kubectl api-resources | grep -i secret
secrets                                          v1                                true         Secret
```

Native Secrets only. And the RBAC reality:

```console
$ kubectl auth can-i get secrets
yes
$ kubectl auth can-i list secrets --all-namespaces
yes
```

This kubeconfig is `cluster-admin`, so **every Secret in every namespace is readable in one
command**. On a real cluster that answer must be `no` for almost everyone.

## The vulnerability: committing Secret YAML to Git

| Problem | Why it is worse than it looks |
|---|---|
| **Git history is permanent** | deleting the file in a later commit removes nothing — `git log -p` still has it. Rotating the credential is the only remedy |
| **Read access is wide** | anyone who can clone the repo has the credential: CI runners, forks, laptop backups, the SaaS that indexes your repos |
| **No rotation story** | the credential's lifetime becomes the repo's lifetime |
| **No audit trail** | the API server logs who read a Secret; Git does not log who read a file |
| **Base64 fools reviewers** | `c2VjcmV0cGFzc3dvcmQ=` does not look like a password in a diff, so it sails through review |

## The production pattern

```
 ┌──────────────────────────────┐
 │  AWS Secrets Manager /       │   the source of truth: versioned, audited,
 │  Azure Key Vault /           │   rotatable, IAM-controlled
 │  HashiCorp Vault             │
 └───────────────┬──────────────┘
                 │  pull, on a schedule, using a workload identity
                 ▼
 ┌──────────────────────────────┐
 │  External Secrets Operator   │   an in-cluster controller. Git holds only an
 │  (reads ExternalSecret CRs)  │   ExternalSecret manifest — a POINTER, never a value
 └───────────────┬──────────────┘
                 │  creates / refreshes
                 ▼
 ┌──────────────────────────────┐
 │  native Kubernetes Secret    │   short-lived, re-synced, never committed anywhere
 └───────────────┬──────────────┘
                 ▼
            Pod  (envFrom / volume — the app is unchanged)
```

What Git holds under this pattern:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: yatri-db-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: yatri-db-secret           # the native Secret ESO will create
  data:
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: prod/yatri/db          # a POINTER. No value anywhere in the repo.
        property: password
```

The alternatives, and when each fits:

| Approach | Secret lives in Git? | Rotation | Notes |
|---|---|---|---|
| Plain `Secret` YAML committed | **yes — never do this** | manual | what Task 3 demonstrates |
| **External Secrets Operator** | no, only a pointer | automatic, `refreshInterval` | the common answer today |
| **Vault Agent Injector** | no | automatic, short-lived leases | injects into the pod filesystem; no Kubernetes Secret at all |
| **Sealed Secrets** (Bitnami) | yes, but encrypted to the cluster's key | manual | good when GitOps must be fully self-contained |
| **SOPS + age/KMS** | yes, encrypted | manual | popular with Flux |
| CI injection (GitHub Actions secrets, ADO variable groups) | no | via the CI platform | simplest; the credential lives in the CI provider |

Also worth turning on regardless: **encryption at rest** via an `EncryptionConfiguration` on the
API server, so etcd holds ciphertext rather than base64. It is off by default, including here.

---

# Task 6 — One pod, both sources

`04-full-demo/backend.yaml` uses both injection styles deliberately:

```yaml
envFrom:                          # bulk: every key in the ConfigMap becomes an env var
  - configMapRef:
      name: yatri-app-config
env:                              # granular: one named key at a time from the Secret
  - name: POSTGRES_USER
    valueFrom:
      secretKeyRef:
        name: yatri-db-secret
        key: POSTGRES_USER
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: yatri-db-secret
        key: POSTGRES_PASSWORD
```

```console
$ kubectl exec deploy/yatri-backend -- env | grep -E 'ENVIRONMENT|LOG_LEVEL|POSTGRES|DEFAULT_CURRENCY|MAX_BOOKING' | sort
DEFAULT_CURRENCY=INR
ENVIRONMENT=production
LOG_LEVEL=INFO
MAX_BOOKING_DAYS=30
POSTGRES_DB=yatri_production_db
POSTGRES_PASSWORD=secretpassword
POSTGRES_USER=yatri_admin
```

Seven variables from two objects, and **inside the container they are indistinguishable**. The
application does not know or care which came from a ConfigMap and which from a Secret — that
distinction exists entirely on the Kubernetes side, for access control and for `describe`
masking.

Why the asymmetry is the right default:

- **`envFrom` for the ConfigMap** — the keys are non-sensitive and adding a sixth key should not
  require editing the Deployment.
- **`secretKeyRef` for the Secret** — naming each key explicitly means the manifest states
  exactly which credentials this workload touches, which is reviewable. `envFrom: secretRef`
  would silently pull in every future key too.

> Note that `POSTGRES_PASSWORD=secretpassword` is plainly visible in `kubectl exec ... env`,
> and would also appear in a crash dump or a process listing. Env-var injection is convenient,
> not confidential; file-based mounts (or Vault's injector) are the stronger option.

---

# Task 7 — Ingress resource vs Ingress controller

Before enabling anything, the API type already exists:

```console
$ kubectl api-resources | grep -i ingress
ingressclasses                                   networking.k8s.io/v1              false        IngressClass
ingresses                           ing          networking.k8s.io/v1              true         Ingress

$ kubectl get ingressclass
No resources found

$ kubectl get pods -n ingress-nginx
No resources found in ingress-nginx namespace.
```

**The API exists; nothing implements it.** You can `kubectl apply` an Ingress right now and it
will be stored happily in etcd and route exactly zero packets. That is the distinction in one
observation.

| | **Ingress resource** | **Ingress controller** |
|---|---|---|
| What it is | a YAML object in etcd | a Deployment of real reverse-proxy pods |
| Written by | you | installed once, per cluster |
| Contains | hosts, paths, TLS secret names, backend services | nginx / Envoy / HAProxy / Traefik |
| Does it move traffic | **no** | **yes** — it *is* the data path |
| Without the other | inert configuration | a proxy with no routes |
| Analogy | the sheet music | the orchestra |

The control loop: the controller watches the API server for Ingress objects → renders them into
its own config (for NGINX, a real `nginx.conf`) → reloads. Every annotation in the manifests
here (`rewrite-target`, `use-regex`, `ssl-redirect`) is an instruction to *that specific
implementation* — which is exactly why the Gateway API was created, to move those knobs into the
typed API instead of string annotations.

---

# Task 8 — Enabling the NGINX Ingress Controller

```console
$ minikube addons enable ingress
* ingress is an addon maintained by Kubernetes. For any concerns contact minikube on GitHub.
* After the addon is enabled, please run "minikube tunnel" and your ingress resources would be available at "127.0.0.1"
  - Using image registry.k8s.io/ingress-nginx/controller:v1.15.1
  - Using image registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9
* Verifying ingress addon...
```

```console
$ kubectl get all -n ingress-nginx
NAME                                           READY   STATUS      RESTARTS   AGE
pod/ingress-nginx-admission-create-jkqlx       0/1     Completed   0          19m
pod/ingress-nginx-admission-patch-zxwjp        0/1     Completed   0          19m
pod/ingress-nginx-controller-d7cd8c989-ncxrt   0/1     Running     0          19m

NAME                                         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
service/ingress-nginx-controller             NodePort    10.105.42.197   <none>        80:30160/TCP,443:30381/TCP   19m
service/ingress-nginx-controller-admission   ClusterIP   10.97.188.175   <none>        443/TCP                      19m

NAME                                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/ingress-nginx-controller   0/1     1            0           19m

NAME                                       STATUS     COMPLETIONS   DURATION   AGE
job.batch/ingress-nginx-admission-create   Complete   1/1           68s        19m
job.batch/ingress-nginx-admission-patch    Complete   1/1           69s        19m
```

Four kinds of object, each with a job:

- **the controller Deployment** — the actual nginx proxy.
- **`ingress-nginx-controller` Service (NodePort)** — how traffic gets in: `80:30160`,
  `443:30381`.
- **`ingress-nginx-controller-admission` (ClusterIP)** — a **validating webhook**. This is why a
  malformed Ingress is rejected at `kubectl apply` time rather than silently breaking nginx.
- **the two admission Jobs** — one-shot pods that generate and patch the webhook's TLS
  certificate, then exit. `Completed`, not failed.

```console
$ kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
pod/ingress-nginx-controller-d7cd8c989-ncxrt condition met

$ kubectl get pods -n ingress-nginx -o wide
NAME                                       READY   STATUS      RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
ingress-nginx-controller-d7cd8c989-ncxrt   1/1     Running     0          21m   10.244.0.35   minikube   <none>           <none>
```

> **21 minutes from `enable` to `Ready`,** all of it spent pulling `controller:v1.15.1` on a slow
> connection. The pod sat at `ContainerCreating`/`0/1` the whole time — worth knowing so you do
> not start debugging a healthy install.

---

# Task 9 — Local DNS, and why `/etc/hosts` is not enough here

```console
$ minikube ip
192.168.49.2

$ grep -E 'yatri.local|campus.local' /etc/hosts || echo 'no lab entries in /etc/hosts yet'
no lab entries in /etc/hosts yet

$ curl --connect-timeout 4 -s -o /dev/null -w '%{http_code}\n' http://$(minikube ip) || echo 'no route to the node IP from macOS, as expected'
000
no route to the node IP from macOS, as expected
```

The lab sheet's step is:

```bash
echo "$(minikube ip)  yatri.local" | sudo tee -a /etc/hosts
```

On macOS with the Docker driver **that mapping is correct and still does not work**, for the
reason diagnosed in detail in
[Homework 10, Task 12](../10-k8s-services#task-12--why-node-ipnodeport-fails-on-macos): the Mac
has no route to `192.168.49.0/24`. `/etc/hosts` fixes name→IP; it cannot fix IP→reachability.

So every HTTP test below runs through a port-forward into the controller instead:

```bash
kubectl -n ingress-nginx port-forward service/ingress-nginx-controller 18080:80 18443:443
```

```console
Forwarding from 127.0.0.1:18080 -> 80
Forwarding from 127.0.0.1:18443 -> 443
```

and the Host header is set explicitly — `curl -H 'Host: yatri.local'` for HTTP, and
`curl --resolve portal.campus.local:18443:127.0.0.1` for HTTPS, which also sets SNI correctly.
Functionally this is identical to a browser hitting `http://yatri.local/`: the controller routes
on the `Host` header and does not care how the packet arrived.

> **To do it the lab-sheet way on your own machine**, run these yourself — the `sudo` needs your
> password, and `minikube tunnel` must stay open in its own terminal:
>
> ```bash
> echo "$(minikube ip)  yatri.local portal.campus.local api.campus.local" | sudo tee -a /etc/hosts
> minikube tunnel        # leave running
> curl http://yatri.local/            # and now the browser works too
> ```
>
> On bare-metal Linux, the `/etc/hosts` line alone is enough; no tunnel needed.

---

# Task 10 — Path-based Layer 7 routing

```yaml
annotations:
  nginx.ingress.kubernetes.io/ssl-redirect: "false"
  nginx.ingress.kubernetes.io/use-regex: "true"
  nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: yatri.local
      http:
        paths:
          - path: /api(/|$)(.*)          # $1 = "/" or "", $2 = everything after
            pathType: ImplementationSpecific
            backend: {service: {name: yatri-backend-service,  port: {number: 80}}}
          - path: /
            pathType: Prefix
            backend: {service: {name: yatri-frontend-service, port: {number: 80}}}
```

```console
$ kubectl get ingress yatri-ingress
NAME            CLASS   HOSTS         ADDRESS        PORTS   AGE
yatri-ingress   nginx   yatri.local   192.168.49.2   80      15s

$ kubectl describe ingress yatri-ingress
Name:             yatri-ingress
Namespace:        default
Address:          192.168.49.2
Ingress Class:    nginx
Default backend:  <default>
Rules:
  Host         Path  Backends
  ----         ----  --------
  yatri.local
               /api(/|$)(.*)   yatri-backend-service:80 (10.244.1.76:5000,10.244.0.32:5000)
               /               yatri-frontend-service:80 (10.244.1.77:80,10.244.0.36:80)
Annotations:   nginx.ingress.kubernetes.io/rewrite-target: /$2
               nginx.ingress.kubernetes.io/ssl-redirect: false
               nginx.ingress.kubernetes.io/use-regex: true
Events:
  Type    Reason  Age               From                      Message
  ----    ------  ----              ----                      -------
  Normal  Sync    2s (x2 over 15s)  nginx-ingress-controller  Scheduled for sync
```

`ADDRESS 192.168.49.2` appeared because the controller wrote its own address back into the
Ingress status — a healthy sign. The backends resolve all the way down to **pod IPs and
targetPorts** (`:5000` for the Python backend, `:80` for nginx), because ingress-nginx bypasses
the ClusterIP and proxies to endpoints directly.

```console
$ curl -s -H 'Host: yatri.local' http://127.0.0.1:18080/ | grep -i '<title>'
<title>Welcome to nginx!</title>

$ curl -s -H 'Host: yatri.local' http://127.0.0.1:18080/api/
Yatri Backend API
=================
ENVIRONMENT     : production
LOG_LEVEL       : INFO
DEFAULT_CURRENCY: INR
POSTGRES_USER   : yatri_admin
POSTGRES_DB     : yatri_production_db
```

**Two different services, one hostname, one port, routed by path.** And that body is the whole
homework in one response: those five values came from a ConfigMap (Task 1) and a Secret (Task 3),
were injected into the pod (Task 6), reached over a ClusterIP, through an Ingress rule.

The rewrite is doing real work. The request `GET /api/` arrives at nginx, `(.*)` captures the
empty string after `/api/`, and `rewrite-target: /$2` rewrites the path to `/` before it is
proxied. The Python server never sees `/api` — which is why the backend can be written without
knowing what prefix it is mounted under.

```console
$ curl -s -o /dev/null -w 'status=%{http_code}\n' -H 'Host: not-our-domain.local' http://127.0.0.1:18080/
status=404
```

An unmatched Host falls through to the controller's default backend, not to the frontend. Host
matching is strict.

```console
$ kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- /nginx-ingress-controller --version
-------------------------------------------------------------------------------
NGINX Ingress controller
  Release:       v1.15.1
  Build:         0df02f2cfcf5fe4ad3cf31492bca770ac2a1606a
  Repository:    https://github.com/kubernetes/ingress-nginx
  nginx version: nginx/1.27.1
```

A real nginx 1.27.1 inside the controller pod, running a config generated from the Ingress
object.

---

# Tasks 11 & 12 — Host-based and hybrid routing

One Ingress, two hostnames, different backends and different path rules per host:

```console
$ kubectl describe ingress campus-ingress-tls
Name:             campus-ingress-tls
Namespace:        default
Ingress Class:    nginx
Default backend:  <default>
TLS:
  campus-tls-cert terminates portal.campus.local,api.campus.local
Rules:
  Host                 Path  Backends
  ----                 ----  --------
  portal.campus.local
                       /()(.*)   yatri-frontend-service:80 (10.244.1.77:80,10.244.0.36:80)
  api.campus.local
                       /api(/|$)(.*)   yatri-backend-service:80 (10.244.1.76:5000,10.244.0.32:5000)
Annotations:           nginx.ingress.kubernetes.io/rewrite-target: /$2
                       nginx.ingress.kubernetes.io/ssl-redirect: true
```

That is the **hybrid** shape Task 12 asks for: `portal.campus.local` is pure host-based routing
(everything goes to the frontend), while `api.campus.local` combines host **and** path.

```console
$ curl -sk --resolve portal.campus.local:18443:127.0.0.1 https://portal.campus.local:18443/ | grep -i '<title>'
<title>Welcome to nginx!</title>

$ curl -sk --resolve api.campus.local:18443:127.0.0.1 https://api.campus.local:18443/api/
Yatri Backend API
=================
ENVIRONMENT     : production
LOG_LEVEL       : INFO
DEFAULT_CURRENCY: INR
POSTGRES_USER   : yatri_admin
POSTGRES_DB     : yatri_production_db
```

Same IP, same port, different `Host` — different service. That is virtual hosting, and it is
what makes the one-load-balancer cost argument in
[Homework 10, Task 11](../10-k8s-services#task-11--cost-why-not-just-use-loadbalancers) work.

```console
$ curl -sk -o /dev/null -w 'portal.campus.local -> %{http_code}\n'   --resolve portal.campus.local:18443:127.0.0.1 https://portal.campus.local:18443/
portal.campus.local -> 200
$ curl -sk -o /dev/null -w 'api.campus.local/api/ -> %{http_code}\n' --resolve api.campus.local:18443:127.0.0.1   https://api.campus.local:18443/api/
api.campus.local/api/ -> 200
$ curl -sk -o /dev/null -w 'api.campus.local/ -> %{http_code}\n'     --resolve api.campus.local:18443:127.0.0.1   https://api.campus.local:18443/
api.campus.local/ -> 404
```

`api.campus.local/` is **404 by design** — that host declares only an `/api` rule, so the bare
root has no backend. Host rules do not inherit each other's paths.

```console
$ curl -s -o /dev/null -w 'http -> %{http_code} %{redirect_url}\n' -H 'Host: portal.campus.local' http://127.0.0.1:18080/
http -> 308 https://portal.campus.local/
```

`ssl-redirect: "true"` (the default whenever a host has TLS configured) turns plain HTTP into a
**308 Permanent Redirect** to HTTPS. Compare `yatri-ingress`, which sets it to `"false"` and
therefore serves HTTP directly — the two behaviours side by side on the same controller.

---

# Task 13 — TLS termination, and a certificate that looked fine but was not

The lab sheet's command, run exactly as written:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=campus.local/O=CampusDevOps"
```

```console
$ kubectl create secret tls campus-tls-cert --cert=tls.crt --key=tls.key
secret/campus-tls-cert created

$ kubectl get secret campus-tls-cert
NAME              TYPE                DATA   AGE
campus-tls-cert   kubernetes.io/tls   2      0s

$ kubectl get ingress campus-ingress-tls -o jsonpath='{.spec.tls}'
[{"hosts":["portal.campus.local","api.campus.local"],"secretName":"campus-tls-cert"}]
```

`kubernetes.io/tls` with `DATA 2` (`tls.crt` + `tls.key`), the Ingress references it, `describe`
says `campus-tls-cert terminates portal.campus.local,api.campus.local`. Everything looks right.

Then the handshake:

```console
$ curl -k -v --resolve portal.campus.local:18443:127.0.0.1 https://portal.campus.local:18443/
* SSL connection using TLSv1.3 / AEAD-AES256-GCM-SHA384
* Server certificate:
*  subject: O=Acme Co; CN=Kubernetes Ingress Controller Fake Certificate
*  issuer: O=Acme Co; CN=Kubernetes Ingress Controller Fake Certificate
< HTTP/2 200
```

> **`CN=Kubernetes Ingress Controller Fake Certificate` — that is not our certificate.** The
> request succeeded and returned `HTTP/2 200`, so anyone checking only the status code would
> have called this task done. TLS was terminating against the controller's built-in fallback.

The controller logged exactly why:

```console
$ kubectl -n ingress-nginx logs deploy/ingress-nginx-controller | grep 'campus.local'
W0918 00:49:35.166141  controller.go:1482] Unexpected error validating SSL certificate "default/campus-tls-cert" for server "portal.campus.local": x509: certificate is not valid for any names, but wanted to match portal.campus.local
W0918 00:49:35.166241  controller.go:1488] SSL certificate "default/campus-tls-cert" does not contain a Common Name or Subject Alternative Name for server "portal.campus.local": x509: certificate is not valid for any names, but wanted to match portal.campus.local
W0918 00:49:35.166289  controller.go:1489] Using default certificate
```

**`certificate is not valid for any names`** — not "wrong name", *no* names:

```console
$ openssl x509 -in tls.crt -noout -subject
subject= /CN=campus.local/O=CampusDevOps
$ openssl x509 -in tls.crt -noout -text | grep -c 'Subject Alternative Name'
0
```

The certificate has a Common Name and **zero SANs**. Since **Go 1.15** (2020), `crypto/x509`
ignores Common Name for hostname verification entirely — and ingress-nginx is written in Go. A
cert with no SAN therefore matches no hostname at all. Two separate problems compound it: even
if CN were honoured, `CN=campus.local` would not match `portal.campus.local`.

## The fix

```console
$ openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls-san.key -out tls-san.crt \
    -subj '/CN=campus.local/O=CampusDevOps' \
    -addext 'subjectAltName=DNS:campus.local,DNS:portal.campus.local,DNS:api.campus.local'

$ openssl x509 -in tls-san.crt -noout -subject; openssl x509 -in tls-san.crt -noout -text | grep -A1 'Subject Alternative Name'
subject= /CN=campus.local/O=CampusDevOps
            X509v3 Subject Alternative Name:
                DNS:campus.local, DNS:portal.campus.local, DNS:api.campus.local

$ kubectl delete secret campus-tls-cert
$ kubectl create secret tls campus-tls-cert --cert=tls-san.crt --key=tls-san.key
secret/campus-tls-cert created

$ kubectl get ingress campus-ingress-tls
NAME                 CLASS   HOSTS                                  ADDRESS        PORTS     AGE
campus-ingress-tls   nginx   portal.campus.local,api.campus.local   192.168.49.2   80, 443   20s
```

```console
$ curl -k -v --resolve portal.campus.local:18443:127.0.0.1 https://portal.campus.local:18443/
* SSL connection using TLSv1.3 / AEAD-AES256-GCM-SHA384
*  subject: CN=campus.local; O=CampusDevOps
*  issuer: CN=campus.local; O=CampusDevOps
*  start date: Sep 18 00:51:25 2026 GMT
*  expire date: Sep 18 00:51:25 2027 GMT
< HTTP/2 200
```

`CN=campus.local; O=CampusDevOps` — our certificate, now actually terminating TLS.

The strongest proof is dropping `-k` entirely and trusting our own CA explicitly. If the
certificate were still the controller's fake one, this would fail:

```console
$ curl -s -o /dev/null -w 'verified https status=%{http_code}\n' --cacert tls-san.crt --resolve portal.campus.local:18443:127.0.0.1 https://portal.campus.local:18443/
verified https status=200

$ curl -s --cacert tls-san.crt --resolve api.campus.local:18443:127.0.0.1 https://api.campus.local:18443/api/
Yatri Backend API
=================
ENVIRONMENT     : production
LOG_LEVEL       : INFO
DEFAULT_CURRENCY: INR
POSTGRES_USER   : yatri_admin
POSTGRES_DB     : yatri_production_db
```

**Full chain verification passes.** For contrast, with the system trust store — which has never
heard of `CampusDevOps` — curl correctly refuses:

```console
$ curl -s --resolve portal.campus.local:18443:127.0.0.1 https://portal.campus.local:18443/; echo "exit code: $?"
exit code: 60
```

Exit 60 is "peer certificate cannot be authenticated with known CA certificates". That is not a
failure of the setup; it is TLS working. Only `-k` (ignore) or `--cacert` (trust this CA
explicitly) get past it, and the second is the honest one.

**What terminates where:**

```
  client ──TLS──► ingress-nginx  ──plain HTTP──►  ClusterIP ──►  pod
          ▲                      ▲
   encrypted, cert from    decrypted here: the app never
   the Secret              sees a certificate or a key
```

The backend pods speak plain HTTP on port 5000/80 and know nothing about TLS. One place to
rotate certificates, one place to configure ciphers, for every service behind the controller.
(In production this Secret would be managed by **cert-manager** against Let's Encrypt, not by a
hand-run `openssl` — but the mechanism is identical: a `kubernetes.io/tls` Secret named in
`spec.tls`.)

---

# Task 14 — End to end

`backend.yaml` and `frontend.yaml` each hold two objects in one file:

```console
$ grep -c '^---' 04-full-demo/backend.yaml
2
```

Multi-document YAML (`---` separators) keeps a Deployment and the Service that fronts it in one
file — they are always created, reviewed and deleted together, so keeping them apart only
invites drift.

`run-demo.sh` performs the whole build in order — enable the addon, wait for the controller,
apply ConfigMap → Secret → frontend → backend, wait for both rollouts, apply the Ingress, then
print the audit. The full stack, running:

```console
$ kubectl get configmap/yatri-app-config secret/yatri-db-secret
NAME                         DATA   AGE
configmap/yatri-app-config   5      70s

NAME                     TYPE     DATA   AGE
secret/yatri-db-secret   Opaque   3      70s

$ kubectl get deploy,svc,pods -l app=yatri-frontend
NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/yatri-frontend   2/2     2            2           71s

NAME                             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
service/yatri-frontend-service   ClusterIP   10.106.109.128   <none>        80/TCP    71s

NAME                                 READY   STATUS    RESTARTS   AGE
pod/yatri-frontend-ddcfc4b5f-bs6pn   1/1     Running   0          71s
pod/yatri-frontend-ddcfc4b5f-v8pjf   1/1     Running   0          71s

$ kubectl get deploy,svc,pods -l app=yatri-backend
NAME                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/yatri-backend   2/2     2            2           71s

NAME                            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/yatri-backend-service   ClusterIP   10.96.108.104   <none>        80/TCP    71s

NAME                                 READY   STATUS    RESTARTS   AGE
pod/yatri-backend-6c58cb99c7-bl6pd   1/1     Running   0          71s
pod/yatri-backend-6c58cb99c7-lfqrh   1/1     Running   0          71s

$ kubectl get ingress
NAME                 CLASS   HOSTS                                  ADDRESS        PORTS     AGE
campus-ingress-tls   nginx   portal.campus.local,api.campus.local   192.168.49.2   80, 443   59s
```

> The lab sheet's audit line, `kubectl get configmap,secret,ingress,deploy,svc,pods -l app=yatri-app`,
> returns only the ConfigMap and the Secret. That is correct behaviour, not a bug — only those
> two carry `app: yatri-app`; the workloads are labelled `app: yatri-frontend` /
> `app: yatri-backend`. (A related slip of mine in the first run:
> `kubectl get configmap yatri-app-config secret yatri-db-secret` reads `secret` as a second
> **ConfigMap** name. The comma form, `configmap/x secret/y`, is what works.)

The whole path, in one request:

```console
$ curl -s -H 'Host: yatri.local' http://127.0.0.1:18080/api/
Yatri Backend API
=================
ENVIRONMENT     : production
LOG_LEVEL       : INFO
DEFAULT_CURRENCY: INR
POSTGRES_USER   : yatri_admin
POSTGRES_DB     : yatri_production_db
```

```
curl ──► port-forward ──► ingress-nginx ──► path rule /api(/|$)(.*)  [rewrite /$2]
                                        ──► yatri-backend-service (ClusterIP)
                                        ──► pod 10.244.1.76:5000
                                        ──► env from ConfigMap + Secret ──► this body
```

Teardown:

```console
$ bash 04-full-demo/cleanup.sh
[INFO] Deleting Ingress...
[INFO] Deleting Backend Deployment and Service...
[INFO] Deleting Frontend Deployment and Service...
[INFO] Deleting Secret...
[INFO] Deleting ConfigMap...
[INFO] All demo resources removed.

$ kubectl get ingress yatri-ingress 2>&1 || echo 'Ingress deleted'
Error from server (NotFound): ingresses.networking.k8s.io "yatri-ingress" not found
Ingress deleted

$ kubectl get deployment yatri-backend yatri-frontend 2>&1 || echo 'Deployments deleted'
Error from server (NotFound): deployments.apps "yatri-backend" not found
Error from server (NotFound): deployments.apps "yatri-frontend" not found
Deployments deleted

$ kubectl get configmap yatri-app-config 2>&1 || echo 'ConfigMap deleted'
Error from server (NotFound): configmaps "yatri-app-config" not found
ConfigMap deleted
```

`cleanup.sh` deletes in the reverse order of creation and uses `--ignore-not-found` throughout,
so it is idempotent — running it twice is not an error. That is the property that makes a
teardown script safe to put in CI.

---

## Files

```
11-ingress-configmaps-secrets/
├── README.md
├── manifests/
│   ├── 01-configmap/  app-config.yaml
│   ├── 02-secret/     db-secret.yaml
│   ├── 03-ingress/    ingress-routes.yaml  ingress-tls.yaml
│   └── 04-full-demo/  configmap.yaml  secret.yaml  frontend.yaml  backend.yaml
│                      ingress.yaml  run-demo.sh  cleanup.sh
├── outputs/
│   ├── task1-configmap.txt
│   ├── task2-configmap-live-update.txt
│   ├── task3-secret-base64.txt
│   ├── task4-trailing-newline.txt
│   ├── task5-enterprise-secrets.txt
│   ├── task6-combined-injection.txt
│   ├── task7-8-ingress-controller.txt
│   ├── task9-local-dns.txt
│   ├── task10-path-routing.txt
│   ├── task11-12-host-and-hybrid-routing.txt
│   ├── task13-tls-termination.txt
│   └── task14-full-demo.txt
└── screenshots/
```
