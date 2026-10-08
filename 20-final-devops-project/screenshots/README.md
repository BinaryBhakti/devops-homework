# Screenshots — Homework 20 (Session 21)

26 images, referenced inline from [../README.md](../README.md).

## Two kinds of image

**Real browser screenshots (01–08).** The IncidentDesk UI and API docs (under Docker Compose),
the GitHub Actions runs, the `gitops-config` commit history, and the Prometheus UI, taken with
headless Chrome while everything was running. 07 and 08 were taken while the node was overloaded,
so they show targets down and `IncidentDeskBackendDown` firing; the README explains this.
There is no 06: the Grafana dashboard never finished loading under that load, and a blank image
was dropped rather than kept.

**Transcript renders (10–27).** The terminal labs ran non-interactively from scripts, so there was
no terminal window to photograph. Each image is a render of a captured transcript: the subtitle
bar names the exact file in [`../outputs/`](../outputs) it came from, and every character is
verbatim output from a command that actually ran.

## Index

| Image | Shows |
|---|---|
| [`01-ui-docker-compose.png`](01-ui-docker-compose.png) | ui docker compose |
| [`02-api-openapi-docs.png`](02-api-openapi-docs.png) | api openapi docs |
| [`03-github-run-2-success.png`](03-github-run-2-success.png) | github run 2 success |
| [`04-github-run-1-gate-blocked.png`](04-github-run-1-gate-blocked.png) | github run 1 gate blocked |
| [`05-gitops-config-commits.png`](05-gitops-config-commits.png) | gitops config commits |
| [`07-prometheus-targets.png`](07-prometheus-targets.png) | prometheus targets |
| [`08-prometheus-alerts.png`](08-prometheus-alerts.png) | prometheus alerts |
| [`10-backend-tests.png`](10-backend-tests.png) | backend tests |
| [`11-frontend-build.png`](11-frontend-build.png) | frontend build |
| [`12-docker-build.png`](12-docker-build.png) | docker build |
| [`13-docker-compose.png`](13-docker-compose.png) | docker compose |
| [`14-sast-sca.png`](14-sast-sca.png) | sast sca |
| [`15-image-scan-gate.png`](15-image-scan-gate.png) | image scan gate |
| [`16-secret-scan.png`](16-secret-scan.png) | secret scan |
| [`17-terraform-cloud.png`](17-terraform-cloud.png) | terraform cloud |
| [`17b-terraform-cloud-verify.png`](17b-terraform-cloud-verify.png) | terraform cloud verify |
| [`18-terraform-k8s.png`](18-terraform-k8s.png) | terraform k8s |
| [`19-monitoring-install.png`](19-monitoring-install.png) | monitoring install |
| [`20-gitops-first-deploy.png`](20-gitops-first-deploy.png) | gitops first deploy |
| [`21-real-deploy-issues.png`](21-real-deploy-issues.png) | real deploy issues |
| [`22-challenge-1-db-password.png`](22-challenge-1-db-password.png) | challenge 1 db password |
| [`23-challenge-2-readiness-path.png`](23-challenge-2-readiness-path.png) | challenge 2 readiness path |
| [`24-challenge-3-image-tag.png`](24-challenge-3-image-tag.png) | challenge 3 image tag |
| [`25-challenge-4-hpa-requests.png`](25-challenge-4-hpa-requests.png) | challenge 4 hpa requests |
| [`26-challenge-5-6-hand-edits.png`](26-challenge-5-6-hand-edits.png) | challenge 5 6 hand edits |
| [`27-monitoring-live.png`](27-monitoring-live.png) | monitoring live |
