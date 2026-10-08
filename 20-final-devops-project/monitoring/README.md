# Monitoring — Prometheus + Grafana, sized for a laptop cluster

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm upgrade --install prometheus prometheus-community/prometheus -n monitoring --create-namespace -f prometheus-values.yaml
helm upgrade --install grafana grafana-community/grafana -n monitoring -f grafana-values.yaml
kubectl -n monitoring port-forward svc/prometheus-server 9090:80     # Status → Targets, Alerts
kubectl -n monitoring port-forward svc/grafana 3001:80               # Dashboards → IncidentDesk
```

| File | What |
|---|---|
| `prometheus-values.yaml` | server (2 d retention, emptyDir) + kube-state-metrics; alertmanager, pushgateway and node-exporter **off**; the alert rules embedded under `serverFiles` |
| `alert-rules.yml` | the source of those rules (availability, readiness, restarts, error rate, p95 latency, HPA at max) |
| `grafana-values.yaml` | one Grafana pod, Prometheus datasource and the dashboard provisioned from code |
| `dashboards/incidentdesk.json` | the dashboard: up, request rate, error ratio, p95, incidents/h, firing alerts; per-route traffic, latency percentiles, CPU and memory per pod, HPA replicas, restarts, not-ready pods |

**How the app is found:** the chart puts `prometheus.io/scrape: "true"`, `port` and `path` on
backend pods; the prometheus chart's built-in `kubernetes-pods` job scrapes every annotated pod
and copies pod labels in, so queries can say `app_kubernetes_io_component="backend"`. No
Prometheus Operator, no ServiceMonitor needed — the chart's ServiceMonitor template is there,
off by default, for clusters that run kube-prometheus-stack.

**Sizing:** about 250 MiB requested in total (Prometheus 192 Mi, Grafana 128 Mi requests are
generous; kube-state-metrics 32 Mi). kube-prometheus-stack would want well over 1.5 GiB, on a
cluster with ~4 GiB for everything — and this repo has already watched an overloaded control
plane fall over ([Homework 13, Task 4](../../13-k8s-troubleshooting)).

**Chart note:** `grafana/grafana` from `grafana.github.io/helm-charts` is marked `deprecated: true`
— the chart moved to `grafana-community` after 2026-01-30. The course's values file targeted the
old one.
