"""Orders API — a small service instrumented for all three observability pillars.

metrics : Prometheus client  -> GET /metrics
logs    : one JSON object per line on stdout (collected by Alloy into Loki)
traces  : OpenTelemetry spans exported over OTLP to Jaeger

Knobs for the demo (no restart needed):
  POST /admin/chaos {"error_rate": 0.3, "slow_ms": 800}   inject errors / latency
  POST /admin/health {"healthy": false}                   make /healthz fail
"""
import json
import logging
import os
import random
import sys
import time

from flask import Flask, Response, g, jsonify, request
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

SERVICE = "orders-api"
VERSION = os.getenv("APP_VERSION", "1.0.0")

# ---- traces -----------------------------------------------------------------------------
provider = TracerProvider(resource=Resource.create({"service.name": SERVICE, "service.version": VERSION}))
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(
    endpoint=os.getenv("OTLP_ENDPOINT", "http://jaeger:4318/v1/traces"))))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(SERVICE)

# ---- logs -------------------------------------------------------------------------------
class JsonFormatter(logging.Formatter):
    def format(self, record):
        span = trace.get_current_span().get_span_context()
        doc = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(record.created)),
               "level": record.levelname.lower(), "service": SERVICE, "version": VERSION,
               "msg": record.getMessage()}
        if span.is_valid:
            doc["trace_id"] = format(span.trace_id, "032x")
        doc.update(getattr(record, "fields", {}))
        return json.dumps(doc)

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
log = logging.getLogger(SERVICE)
log.addHandler(handler)
log.setLevel(logging.INFO)
logging.getLogger("werkzeug").setLevel(logging.WARNING)

# ---- metrics ----------------------------------------------------------------------------
REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "route", "status"])
LATENCY = Histogram("http_request_duration_seconds", "Request latency", ["route"],
                    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5))
IN_FLIGHT = Gauge("http_requests_in_flight", "Requests being served")
HEALTHY = Gauge("app_healthy", "1 if the app reports itself healthy")
ORDERS = Counter("orders_created_total", "Business metric: orders created")
INFO = Gauge("app_info", "Build info", ["version"])
INFO.labels(VERSION).set(1)

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app, excluded_urls="metrics,healthz")
state = {"error_rate": 0.0, "slow_ms": 0, "healthy": True}
HEALTHY.set(1)


@app.before_request
def _start():
    g.t0 = time.perf_counter()
    IN_FLIGHT.inc()


@app.after_request
def _finish(resp):
    IN_FLIGHT.dec()
    route = request.url_rule.rule if request.url_rule else "unmatched"
    if route not in ("/metrics",):
        REQUESTS.labels(request.method, route, str(resp.status_code)).inc()
        LATENCY.labels(route).observe(time.perf_counter() - g.t0)
    return resp


@app.get("/api/orders")
def list_orders():
    with tracer.start_as_current_span("db.query") as span:
        span.set_attribute("db.system", "postgresql")
        span.set_attribute("db.statement", "SELECT id, item, qty FROM orders LIMIT 20")
        delay = state["slow_ms"] / 1000 + random.uniform(0.005, 0.03)
        time.sleep(delay)
    if random.random() < state["error_rate"]:
        log.error("database timeout while listing orders",
                  extra={"fields": {"route": "/api/orders", "delay_ms": round(delay * 1000)}})
        return jsonify(error="database timeout"), 500
    log.info("listed orders", extra={"fields": {"route": "/api/orders", "count": 20}})
    return jsonify(orders=[{"id": i, "item": "widget", "qty": i % 3 + 1} for i in range(20)])


@app.post("/api/orders")
def create_order():
    with tracer.start_as_current_span("payment.authorize"):
        time.sleep(random.uniform(0.02, 0.06))
    with tracer.start_as_current_span("db.insert"):
        time.sleep(random.uniform(0.005, 0.02))
    ORDERS.inc()
    log.info("order created", extra={"fields": {"route": "/api/orders", "amount": 499}})
    return jsonify(status="created"), 201


@app.get("/healthz")
def healthz():
    if not state["healthy"]:
        return jsonify(status="unhealthy"), 503
    return jsonify(status="ok", version=VERSION)


@app.post("/admin/chaos")
def chaos():
    state.update({k: v for k, v in (request.get_json(force=True) or {}).items() if k in ("error_rate", "slow_ms")})
    log.warning("chaos settings changed", extra={"fields": dict(state)})
    return jsonify(state)


@app.post("/admin/health")
def set_health():
    state["healthy"] = bool((request.get_json(force=True) or {}).get("healthy", True))
    HEALTHY.set(1 if state["healthy"] else 0)
    log.warning("health flag changed", extra={"fields": {"healthy": state["healthy"]}})
    return jsonify(state)


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    log.info("starting", extra={"fields": {"port": 8000}})
    app.run(host="0.0.0.0", port=8000, threaded=True)
