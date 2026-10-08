# Observability — Metrics, Logs and Traces

Session 20, **Task 2**: what the three pillars are, why observability is needed, the common
tools, and how it all applies to Kubernetes.

This README is documentation. The practical side is
[`../01-monitoring`](../01-monitoring), where all three pillars run for real against one
instrumented app: Prometheus metrics, structured JSON logs in Loki, and OpenTelemetry traces in
Jaeger. Links to that evidence are marked **→ seen in the demo**.

---

## Monitoring vs observability

| | Monitoring | Observability |
|---|---|---|
| Question it answers | **"Is it broken?"** | **"Why is it broken?"**, including for failures nobody predicted |
| Built from | checks and thresholds you decided on in advance | rich telemetry you can slice in ways you did not plan |
| Typical output | a dashboard, an alert | an investigation: drill from a symptom to a cause |
| Works for | known failure modes ("disk > 90%") | unknown-unknowns ("p99 latency up only for one tenant on one pod after the 14:02 deploy") |

They are not rivals. **Monitoring is something you do with an observable system.** Alerts
tell you *that* something is wrong, and observability data lets you find out *what* without
shipping new code to add a log line.

## Why observability is required

A monolith on one server can be debugged with `top`, `tail -f` and an SSH session. A
Kubernetes application cannot:

- **Requests cross many processes.** One checkout can touch an ingress, three services, a
  queue and two databases. No single log file has the whole story.
- **Things are ephemeral.** The pod that failed at 03:00 has been replaced. Its logs and its
  IP are gone unless they were shipped somewhere.
- **Failures are partial.** One replica of five is slow, or one node has a noisy neighbour.
  Averages hide it. You need per-pod, per-route, per-version breakdowns.
- **Change is constant.** Many deploys a day means "what changed?" is the first question in
  every incident, and only telemetry that carries version and deploy labels can answer it.
- **You cannot attach a debugger to production.** The telemetry is the debugger.

The business case is MTTR (mean time to recovery). Detection comes from alerts on metrics;
diagnosis comes from logs and traces. Every minute saved in either is downtime avoided.

---

## The three pillars

```
            ┌───────────────── one request, three views ─────────────────┐
  METRICS   │ http_requests_total{route="/api/orders",status="500"} 37   │  how much / how often / how fast (aggregated)
  LOGS      │ {"level":"error","msg":"db timeout","trace_id":"4bf9…"}    │  what happened, in detail, per event
  TRACES    │ ingress ─► orders (180 ms) ─► db.query (170 ms)            │  where the time went, across services
            └────────────────────────────────────────────────────────────┘
                 linked by labels (service, pod, version) and trace_id
```

### 1. Metrics

**Numeric measurements over time**, stored as time series: a name, a set of labels, and
`(timestamp, value)` samples.

```
http_requests_total{method="GET", route="/api/orders", status="200"}   1027
process_resident_memory_bytes{pod="orders-7d9f-xk2"}                   5.2e+07
```

| Type | Meaning | Example |
|---|---|---|
| Counter | only goes up (reset on restart) | requests served, errors |
| Gauge | goes up and down | memory in use, queue depth, in-flight requests |
| Histogram | values counted into buckets → percentiles | request latency |
| Summary | client-side percentiles (not aggregatable across pods) | legacy latency |

- **Strengths:** cheap to store, fast to query, perfect for dashboards and **alerting**,
  trends over months.
- **Limits:** aggregated, so it tells you *that* the error rate rose, not *which request*
  or *why*. High-cardinality labels (user ID, request ID) will blow up the time-series
  database, so don't use them.
- **Golden signals** (Google SRE): **latency, traffic, errors, saturation**. The equivalent
  method for request-driven services is **RED** (Rate, Errors, Duration), and for resources it
  is **USE** (Utilisation, Saturation, Errors).
- **→ seen in the demo:** the app's `/metrics`, a Grafana dashboard of request rate, error
  ratio, p95 latency, CPU and memory, and Prometheus alert rules going `pending` → `firing`.

### 2. Logs

**Timestamped records of discrete events**, written by the application.

```json
{"ts":"2026-10-07T17:02:11Z","level":"error","service":"orders","msg":"payment declined",
 "order_id":"A-1042","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736"}
```

- **Strengths:** the most detail. Error messages, stack traces, business context.
- **Limits:** the most expensive pillar at scale (volume), and slow to aggregate.
- **Make them useful:** structured (JSON) rather than free text; consistent fields; a
  severity level; and the **`trace_id`**, which turns a log line into an entry point to the
  full trace.
- **In Kubernetes:** write to **stdout/stderr**. The container runtime writes them to files
  on the node, `kubectl logs` reads those files, and a **node-level agent** (a DaemonSet:
  Fluent Bit, Promtail/Alloy, Vector) ships them to a central store before the pod, and its
  logs, disappear.
- **→ seen in the demo:** JSON logs collected into Loki and queried with LogQL in Grafana,
  filtered to errors only.

### 3. Traces

**The path of one request through the system**, as a tree of timed operations (**spans**).

```
trace 4bf92f35…   total 212 ms
├─ GET /api/checkout            frontend   212 ms
│  ├─ POST /orders              orders     180 ms
│  │  ├─ SELECT … FROM orders   postgres   170 ms   ◄── the slow part
│  │  └─ publish order.created  kafka        4 ms
│  └─ GET /recommendations      recs        21 ms
```

- Each span carries a trace ID (shared), a span ID, a parent span ID, a start time, a duration
  and attributes. The **trace context** is passed between services in HTTP headers
  (`traceparent`, W3C Trace Context), which is how one trace crosses many processes.
- **Strengths:** shows *where* latency and errors come from in a distributed call graph, which
  neither metrics nor logs can show.
- **Limits:** needs instrumentation (now standardised by OpenTelemetry), and usually
  **sampling** (keep e.g. 10% of traces, or all errors) to control cost.
- **→ seen in the demo:** OpenTelemetry spans from the app in Jaeger, including a nested span
  for the deliberately slow operation.

### How the pillars work together in an incident

```
 ALERT (metric)     error ratio > 5% for 2m on route /api/orders           → something is wrong
     │
 DASHBOARD (metric) only pods of version 1.4.2; started at the 14:02 deploy → narrowed down
     │
 TRACE              failing requests spend 3 s in "db.query"               → where
     │
 LOGS (by trace_id) "connection pool exhausted (max=5)"                    → why
```

| | Metrics | Logs | Traces |
|---|---|---|---|
| Answers | is it healthy? how much? | what exactly happened? | where did the time / error come from? |
| Granularity | aggregate | per event | per request |
| Cost at scale | low | **high** | medium (sampled) |
| Best for | alerting, trends, capacity | root-cause detail, audit | latency, dependencies |

**Signals beyond the three:** profiles (continuous profiling, e.g. Pyroscope) and events
(deploys, config changes, and Kubernetes `Events`) are increasingly treated as the fourth and
fifth.

---

## Common tools

| Pillar | Collect / instrument | Store & query | Visualise / alert |
|---|---|---|---|
| Metrics | Prometheus client libs, **exporters** (node-exporter, kube-state-metrics, cAdvisor), OpenTelemetry | **Prometheus**, Thanos / Cortex / **Mimir**, VictoriaMetrics | **Grafana**, Alertmanager |
| Logs | Fluent Bit, Fluentd, Promtail / **Grafana Alloy**, Vector, Filebeat | **Loki**, Elasticsearch / OpenSearch | Grafana, Kibana / OpenSearch Dashboards |
| Traces | **OpenTelemetry** SDKs + Collector | **Jaeger**, Grafana **Tempo**, Zipkin | Jaeger UI, Grafana |
| All-in-one (SaaS) | vendor agents or OTel | Datadog, New Relic, Dynatrace, Honeycomb, Grafana Cloud, Elastic Cloud | same |
| Cloud native | CloudWatch agent | **CloudWatch** Metrics/Logs, **X-Ray** | CloudWatch dashboards and alarms |

**OpenTelemetry (OTel)** is the important standard. It is one vendor-neutral set of APIs,
SDKs and wire protocol (OTLP) for all three signals. You instrument once and send the data to
Jaeger today and Datadog tomorrow without touching application code.

The two common open-source stacks:
- **"PLG / LGTM"**: Prometheus (or Mimir), Loki, Grafana, Tempo. This is what the demo uses,
  with Jaeger in place of Tempo.
- **"ELK / EFK"**: Elasticsearch, Logstash or Fluentd, Kibana. Log-centric.

---

## Kubernetes observability

### What is there to observe

```
 cluster ──► nodes ──► pods ──► containers ──► the application inside
   │           │         │          │                  │
 control    kubelet   kube-state  cAdvisor      app /metrics, logs, traces
 plane      node-exp  -metrics    (in kubelet)
 metrics
```

| Layer | Source | Examples |
|---|---|---|
| Node | **node-exporter** (DaemonSet) | CPU, memory, disk, network per node |
| Container | **cAdvisor** (built into the kubelet) | `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`, throttling |
| Object state | **kube-state-metrics** | desired vs available replicas, pod phase, restarts, `OOMKilled` reasons, HPA status |
| Control plane | API server, etcd, scheduler, controller-manager `/metrics` | API request latency, etcd fsync time, scheduling failures |
| Resource API | **metrics-server** | the *live* numbers behind `kubectl top` and the **HPA**. Not a monitoring system: no history |
| Application | instrumented code | RED metrics, business metrics, logs, traces |
| Events | Kubernetes `Events` API | `BackOff`, `FailedScheduling`, `Unhealthy`, `Killing`. **They expire after 1 hour**, so ship them |

### The standard setup

- **kube-prometheus-stack** (Helm) installs Prometheus Operator, Prometheus, Alertmanager,
  Grafana, node-exporter and kube-state-metrics, plus ready-made dashboards and alerts.
  Applications opt in with a **`ServiceMonitor`** / `PodMonitor` custom resource instead of
  editing Prometheus config. The course's Session 21 Helm chart ships one
  (`templates/servicemonitor.yaml`).
- **Logs:** a DaemonSet agent (Fluent Bit or Alloy) tails `/var/log/containers/*.log` on each
  node and enriches every line with pod, namespace and labels from the API.
- **Traces:** an OpenTelemetry Collector, as a Deployment or a DaemonSet, receives OTLP from
  pods and exports to Jaeger or Tempo.
- **Probes are observability too:** readiness and liveness results feed straight into
  `Events`, endpoint membership and restart counts.

### Lessons from this repo's own cluster

Two real incidents in this repository were diagnosed purely from cluster telemetry, and both
show why history matters:

- **[Homework 13, Task 4](../../13-k8s-troubleshooting#task-4--a-real-incident-control-plane-starved-on-this-cluster)**:
  ingress-nginx restarted 137 times and kube-apiserver 55 times. Restart counts, `Unhealthy`
  events, exit code 143 and the node's cgroup `memory.events` led to a memory-starved
  control-plane node, then later to CPU starvation from an unthrottled load generator.
  `kubectl top` only shows *now*. The evidence that mattered was counters and events that
  happened to still exist. With Prometheus, `container_cpu_cfs_throttled_seconds_total` and
  API-server latency would have shown it on a graph in seconds.
- **[Homework 12](../../12-storage-hpa-probes)**: the HPA reported `<unknown>` until
  metrics-server had scraped twice, and **metrics-server itself crashed** during the
  starvation. Autoscaling depends on an observability component, so that component needs
  monitoring too.

### Good practice checklist

- Alert on **symptoms users feel** (error rate, latency, availability, using SLOs and burn
  rates), not on every cause ("CPU 80%").
- Every alert gets a **runbook** link and an owner; an alert nobody acts on gets deleted.
- Put `service`, `version`, `pod` and `namespace` on every signal so the pillars can be joined.
- Keep metric labels **low-cardinality**; put IDs in logs and traces instead.
- Ship logs and events **off the node**: pods and nodes are cattle, and their local data dies
  with them.
- Monitor the monitoring (Prometheus `up`, Alertmanager delivery, a dead-man's-switch alert).
