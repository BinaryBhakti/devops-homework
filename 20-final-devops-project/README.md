# Homework 20 — Final DevOps Project: IncidentDesk

Course session: **`session21-python`**.

> **Status:** the code, infrastructure and pipeline are committed, and the full write-up (architecture,
> every stage's evidence, the troubleshooting challenge and lessons learned) is being completed. This
> page is replaced by the full README when the live runs are done.

IncidentDesk is a small incident tracker (FastAPI + PostgreSQL backend, React frontend) taken through
the whole DevOps chain from the course:

```
code ─► GitHub ─► CI: build & test ─► SAST / SCA / secret scan ─► Docker build ─► image scan
     ─► security gate ─► GHCR ─► deploy (kind, in CI) ─► GitOps: tag published to gitops-config
     ─► Argo CD ─► Minikube (Helm) ─► Prometheus + Grafana
Terraform: VPC, subnets, security groups, backup bucket, IAM, lock table on LocalStack
           + namespaces, quota and limits on the cluster
```

| Folder | Contents |
|---|---|
| [`application/`](application) | backend (FastAPI, SQLAlchemy, Alembic, pytest) and frontend (React + Vite → nginx) |
| [`docker/`](docker) | docker-compose for the full local stack |
| [`kubernetes/`](kubernetes) | plain manifests: namespace, ConfigMap, Secret (example only), Postgres + PVC, backend, frontend, Ingress, HPA, probes |
| [`helm/incidentdesk/`](helm/incidentdesk) | the chart Argo CD deploys (values, values-dev, values-prod) |
| [`terraform/`](terraform) | cloud side on LocalStack, plus [`terraform/k8s/`](terraform/k8s) for the cluster bootstrap |
| [`.github/workflows/`](.github/workflows) | points to the real workflow at the repo root: `.github/workflows/hw20-final.yml` |
| [`security/`](security) | Semgrep, Bandit, gitleaks and Trivy configuration, plus the gate policy |
| [`monitoring/`](monitoring) | alert rules, Grafana dashboard, lean Prometheus/Grafana values |
| [`gitops/`](gitops) | the Argo CD Application and the tag-bump script used by CI |
| [`troubleshooting/`](troubleshooting) | broken variants for the final troubleshooting challenge |
