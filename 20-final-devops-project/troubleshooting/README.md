# Final troubleshooting challenge — broken variants

Six faults to inject into the running `incidentdesk` release, **one at a time**. Each file says
what someone *did*, not what goes wrong — finding that out is the exercise.

| # | File | What changed | Apply with |
|---|---|---|---|
| 1 | `01-db-password-rotated.values.yaml` | the DB password in the chart values was "rotated" | `helm upgrade incidentdesk ../helm/incidentdesk -n incidentdesk --reuse-values -f 01-db-password-rotated.values.yaml` |
| 2 | `02-readiness-path.values.yaml` | the readiness probe path was renamed | same, with `-f 02-readiness-path.values.yaml` |
| 3 | `03-image-tag.values.yaml` | a backend image tag was pinned by hand | same, with `-f 03-image-tag.values.yaml` |
| 4 | `04-hpa-requests.values.yaml` | the backend's resource requests were removed | same, with `-f 04-hpa-requests.values.yaml` |
| 5 | `05-service-selector.patch.json` | someone edited the backend Service directly | `kubectl -n incidentdesk patch svc incidentdesk-backend --type=json --patch-file 05-service-selector.patch.json` |
| 6 | `06-ingress-port.patch.json` | someone edited the Ingress directly | `kubectl -n incidentdesk patch ingress incidentdesk --type=json --patch-file 06-ingress-port.patch.json` |

**Before you start:** if the release is managed by Argo CD with `selfHeal: true`, any change
made with `helm`/`kubectl` is reverted within minutes. Either pause auto-sync for the
challenge (`kubectl -n argocd patch application incidentdesk-dev --type merge -p '{"spec":{"syncPolicy":null}}'`)
or inject the fault the GitOps way — as a commit — and observe what Argo CD does with it.

Reset between faults: `helm rollback incidentdesk -n incidentdesk` (values variants) or re-apply the
chart (`helm upgrade ... --reuse-values`) for the patches.
