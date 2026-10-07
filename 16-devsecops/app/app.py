from flask import Flask, jsonify, request, render_template
import platform
import datetime
import os
import re
import secrets
import sys

app = Flask(__name__)

# Not used for anything security-related, but SystemRandom keeps the intent explicit
# and satisfies Bandit B311 without a blanket # nosec.
_rng = secrets.SystemRandom()
_BRANCH_RE = re.compile(r"^[A-Za-z0-9._/-]{1,64}$")


def _now():
    return datetime.datetime.now(datetime.timezone.utc)


def _iso(ts):
    return ts.isoformat().replace("+00:00", "Z")


# --- In-memory storage for demo ---
_request_count = 0
_start_time = _now()


@app.after_request
def _security_headers(resp):
    # Inline onclick= handlers in the course template need 'unsafe-inline' for scripts;
    # everything else is locked to this origin (+ Google Fonts used by the page).
    resp.headers["Content-Security-Policy"] = (
        "default-src 'self'; script-src 'self' 'unsafe-inline'; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "font-src https://fonts.gstatic.com; frame-ancestors 'none'; base-uri 'self'"
    )
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Referrer-Policy"] = "no-referrer"
    resp.headers["X-Frame-Options"] = "DENY"
    return resp


def _increment_requests():
    global _request_count
    _request_count += 1


# ─────────────────────────────────────────────────────────
#  Pages
# ─────────────────────────────────────────────────────────

@app.route("/")
def home():
    _increment_requests()
    return render_template("index.html")


# ─────────────────────────────────────────────────────────
#  Health & Status API
# ─────────────────────────────────────────────────────────

@app.route("/health")
def health():
    _increment_requests()
    uptime_seconds = (_now() - _start_time).total_seconds()
    return jsonify({
        "status": "healthy",
        "uptime_seconds": round(uptime_seconds, 2),
        "timestamp": _iso(_now()),
    })


@app.route("/api/status")
def status():
    _increment_requests()
    uptime = _now() - _start_time
    hours, remainder = divmod(int(uptime.total_seconds()), 3600)
    minutes, seconds = divmod(remainder, 60)
    return jsonify({
        "app": "DevSecOps Dashboard",
        "version": "2.0.0",
        "git_sha": os.getenv("GIT_SHA", "local"),
        "status": "running",
        "python_version": sys.version.split()[0],
        "platform": platform.system(),
        "uptime": f"{hours:02d}h {minutes:02d}m {seconds:02d}s",
        "total_requests": _request_count,
        "timestamp": _iso(_now()),
    })


# ─────────────────────────────────────────────────────────
#  Greeting API
# ─────────────────────────────────────────────────────────

@app.route("/api/greet/<name>")
def greet(name):
    _increment_requests()
    greetings = [
        f"Hello, {name}! 👋",
        f"Hey {name}, welcome aboard! 🚀",
        f"Greetings, {name}! You rock! 🌟",
        f"What's up, {name}! Happy coding! 💻",
        f"Hi {name}! May your pipelines always pass! ✅",
    ]
    return jsonify({
        "message": _rng.choice(greetings),
        "name": name,
        "timestamp": _iso(_now()),
    })


# ─────────────────────────────────────────────────────────
#  Math API
# ─────────────────────────────────────────────────────────

@app.route("/api/add", methods=["POST"])
def add_numbers():
    _increment_requests()
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    number1 = data.get("number1")
    number2 = data.get("number2")

    if number1 is None or number2 is None:
        return jsonify({"error": "Both number1 and number2 are required"}), 400

    try:
        n1, n2 = float(number1), float(number2)
    except (TypeError, ValueError):
        return jsonify({"error": "Values must be numbers"}), 400

    return jsonify({
        "number1": n1,
        "number2": n2,
        "operation": "addition",
        "result": n1 + n2,
    })


@app.route("/api/calculate", methods=["POST"])
def calculate():
    """Multi-operation calculator."""
    _increment_requests()
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    a = data.get("a")
    b = data.get("b")
    op = data.get("operation", "add")

    if a is None or b is None:
        return jsonify({"error": "Fields 'a' and 'b' are required"}), 400

    try:
        a, b = float(a), float(b)
    except (TypeError, ValueError):
        return jsonify({"error": "Values must be numbers"}), 400

    ops = {
        "add":      (a + b,        "+"),
        "subtract": (a - b,        "-"),
        "multiply": (a * b,        "×"),
        "divide":   (a / b if b != 0 else None, "÷"),
        "power":    (a ** b,       "^"),
        "modulo":   (a % b if b != 0 else None, "%"),
    }

    if op not in ops:
        return jsonify({"error": f"Unknown operation '{op}'. Valid: {list(ops.keys())}"}), 400

    result, symbol = ops[op]
    if result is None:
        return jsonify({"error": "Division by zero"}), 400

    return jsonify({
        "a": a, "b": b,
        "operation": op,
        "symbol": symbol,
        "result": round(result, 10),
        "expression": f"{a} {symbol} {b} = {round(result, 10)}",
    })


# ─────────────────────────────────────────────────────────
#  Pipeline Simulator API
# ─────────────────────────────────────────────────────────

PIPELINE_STAGES = [
    {"name": "Code Checkout",      "icon": "📦"},
    {"name": "Install Deps",       "icon": "📥"},
    {"name": "Lint & Format",      "icon": "🔍"},
    {"name": "Unit Tests",         "icon": "🧪"},
    {"name": "Security Scan",      "icon": "🔒"},
    {"name": "Build Docker Image", "icon": "🐳"},
    {"name": "Push to Registry",   "icon": "📤"},
    {"name": "Deploy to K8s",      "icon": "☸️"},
]


@app.route("/api/pipeline/run", methods=["POST"])
def run_pipeline():
    """Simulates a CI/CD pipeline run."""
    _increment_requests()
    data = request.get_json(silent=True) or {}
    branch = str(data.get("branch", "main"))
    if not _BRANCH_RE.match(branch):
        return jsonify({"error": "Invalid branch name"}), 400
    try:
        fail_chance = float(data.get("fail_chance", 0.1))   # 0–1 probability
    except (TypeError, ValueError):
        return jsonify({"error": "fail_chance must be a number"}), 400
    if not 0 <= fail_chance <= 1:
        return jsonify({"error": "fail_chance must be between 0 and 1"}), 400

    stages = []
    failed = False
    for stage in PIPELINE_STAGES:
        if failed:
            status = "skipped"
            duration = 0
        elif _rng.random() < fail_chance:
            status = "failed"
            duration = round(_rng.uniform(0.5, 5.0), 2)
            failed = True
        else:
            status = "passed"
            duration = round(_rng.uniform(0.5, 15.0), 2)

        stages.append({
            "name": stage["name"],
            "icon": stage["icon"],
            "status": status,
            "duration_s": duration,
        })

    overall = "failed" if failed else "passed"
    total_time = round(sum(s["duration_s"] for s in stages), 2)
    run_id = f"run-{_rng.randint(1000, 9999)}"

    return jsonify({
        "run_id": run_id,
        "branch": branch,
        "overall_status": overall,
        "total_time_s": total_time,
        "stages": stages,
        "triggered_at": _iso(_now()),
    })


# ─────────────────────────────────────────────────────────
#  Error handlers
# ─────────────────────────────────────────────────────────

@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Route not found", "code": 404}), 404


@app.errorhandler(500)
def server_error(e):
    return jsonify({"error": "Internal server error", "code": 500}), 500


if __name__ == "__main__":
    # Local development only. In the container gunicorn serves the app (see Dockerfile).
    app.run(host="127.0.0.1", port=5001, debug=os.getenv("FLASK_DEBUG") == "1")