# gitops-config

The desired state for the Homework 19 GitOps demo, watched by Argo CD.

This is an orphan branch on purpose: it holds only deployment manifests, so Argo CD can
shallow-clone a few KB instead of the whole homework repository (~70 MB of screenshots over a
~0.5 MB/s link kept timing out). Every change here is a deploy.

See `19-monitoring-observability-gitops/README.md` on `main` for the write-up.
