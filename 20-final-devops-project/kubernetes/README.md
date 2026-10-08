# Plain Kubernetes manifests

The **Helm chart in [`../helm/incidentdesk`](../helm/incidentdesk) is how the app is actually
deployed** (by Argo CD). These hand-written manifests show the same objects without templating,
so each one can be read on its own.

| File | Objects | Why it is there |
|---|---|---|
| `00-namespace.yaml` | Namespace | Pod Security Admission: `enforce: baseline`, `warn: restricted` |
| `01-configmap.yaml` | ConfigMap | non-secret settings (env, DB host/name/user) |
| `02-secret.example.yaml` | Secret (**template only**) | real values are created out-of-band — see below |
| `03-postgres.yaml` | headless Service + StatefulSet | stable identity + a PVC per pod from `volumeClaimTemplates` |
| `04-backend.yaml` | Deployment + Service | init containers (wait-for-db, Alembic migrate), startup/readiness/liveness probes, non-root, read-only root FS |
| `05-frontend.yaml` | Deployment + Service | unprivileged nginx; proxies `/api` to the backend Service |
| `06-ingress.yaml` | Ingress | `/api` → backend:8000, `/` → frontend |
| `07-hpa.yaml` | HPA + PodDisruptionBudget | 2–5 backend replicas at 60% CPU; at least 1 always up during node drains |

```bash
./99-apply.sh        # creates the Secret with a random password, applies everything in order
```

## Probes — three different questions

| Probe | Endpoint | Asks | On failure |
|---|---|---|---|
| startup | `/health` | has it finished booting? (up to 60 s) | restart — and until it passes, the other two are not run |
| readiness | `/ready` — **runs `SELECT 1`** | can it serve a request right now? | removed from the Service endpoints, **not** restarted |
| liveness | `/health` — **no DB call** | is the process wedged? | restarted |

Liveness deliberately does not touch the database: if Postgres goes down, every backend pod
becomes NotReady (traffic stops cleanly) instead of being restarted in a loop that cannot fix a
database outage.

## Why the Secret is only an example

A Secret in Git is a password in Git — base64 is an encoding, not encryption, and Git history
is forever. `99-apply.sh` generates the password at install time; the Helm chart either takes it
from values (dev only) or uses `postgres.existingSecret` (anything real). For GitOps the answer is
Sealed Secrets / SOPS (encrypted in Git) or the External Secrets Operator (fetched from a vault).
