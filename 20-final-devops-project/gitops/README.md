# GitOps — Git is the deployment API

```
 developer ── git push ──► GitHub Actions ─ test ─ scan ─ build ─ push image (sha-abc1234)
                                                                 │
                          job "gitops": copy helm/incidentdesk + set tag sha-abc1234
                          → commit to the gitops-config branch (incidentdesk/) [skip ci]
                                                                 │
 Argo CD (in the cluster) ◄── shallow-clones gitops-config, ~3 min or on refresh ─┘
        │  renders helm/incidentdesk with values-dev.yaml, diffs against the cluster
        ▼
 Kubernetes: rolling update to sha-abc1234      (and: anything changed by hand → changed back)
```

| File | Role |
|---|---|
| [`application-dev.yaml`](application-dev.yaml) | the Argo CD `Application`: branch `gitops-config`, path `incidentdesk`, `values-dev.yaml` → namespace, auto-sync with `prune` and `selfHeal`. Applied once, by an admin |
| [`bump-image-tag.sh`](bump-image-tag.sh) | what the CI `gitops` job runs on the published copy: rewrites the two CI-managed `tag:` lines and refuses to continue if it did not change exactly two |
| [`gitops-config`](https://github.com/BinaryBhakti/devops-homework/tree/gitops-config) branch | the environment: only deployable config. `main` is the source of truth for code and chart; this branch is what is *deployed*, written by CI after a green pipeline |

**Why a separate branch:** Argo CD has to clone what it watches. This repository is ~70 MB of
homework screenshots and the link it ran on is ~0.5 MB/s, so clones of `main` timed out (worked
through in [Homework 19](../../19-monitoring-observability-gitops#why-argo-cd-watches-a-separate-branch)).
The config branch is a few KB and is cloned shallow (`depth: 1`). It is also the standard GitOps
separation: app source and environment config change for different reasons, at different rates.

**CI never holds cluster credentials.** It only writes to Git; the cluster pulls. A leaked CI
token can at worst push a commit — which is reviewed, visible, and revertable — instead of
`kubectl`-ing straight into production.

**Rollback = `git revert`.** The previous tag comes back through the same path as every deploy.

**Loop safety:** the workflow only triggers on `main` (and only for this folder), the bot commits
to `gitops-config`, the commit is made with `GITHUB_TOKEN` (GitHub never starts workflows for
those), and the message carries `[skip ci]`.

**What Argo CD must ignore:** `spec.replicas` on the backend Deployment — the HPA owns it, and
`selfHeal` would otherwise "fix" every autoscaling decision.
