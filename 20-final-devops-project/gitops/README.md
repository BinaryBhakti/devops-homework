# GitOps — Git is the deployment API

```
 developer ── git push ──► GitHub Actions ─ test ─ scan ─ build ─ push image (sha-abc1234)
                                                                 │
                                                  commit: values-dev.yaml tag → sha-abc1234 [skip ci]
                                                                 │
 Argo CD (in the cluster) ◄──── polls main every ~3 min ─────────┘
        │  renders helm/incidentdesk with values-dev.yaml, diffs against the cluster
        ▼
 Kubernetes: rolling update to sha-abc1234      (and: anything changed by hand → changed back)
```

| File | Role |
|---|---|
| [`application-dev.yaml`](application-dev.yaml) | the Argo CD `Application`: repo + path + values file → namespace, auto-sync with `prune` and `selfHeal`. Applied once, by an admin |
| [`bump-image-tag.sh`](bump-image-tag.sh) | what the CI `gitops` job runs: rewrites the two CI-managed `tag:` lines in `values-dev.yaml` and refuses to continue if it did not change exactly two |

**CI never holds cluster credentials.** It only writes to Git; the cluster pulls. A leaked CI
token can at worst push a commit — which is reviewed, visible, and revertable — instead of
`kubectl`-ing straight into production.

**Rollback = `git revert`.** The previous tag comes back through the same path as every deploy.

**Loop safety** (CI commits to the branch that triggers CI): the commit is made with
`GITHUB_TOKEN` (GitHub never starts workflows for those), the job skips the bot's own pushes,
and the message carries `[skip ci]`.

**What Argo CD must ignore:** `spec.replicas` on the backend Deployment — the HPA owns it, and
`selfHeal` would otherwise "fix" every autoscaling decision.
