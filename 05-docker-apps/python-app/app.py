import os
import platform
import socket

from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def hello():
    return f"""<!doctype html>
<html>
<head><meta charset="utf-8"><title>Python Hello World</title>
<style>
  body{{font-family:system-ui,-apple-system,sans-serif;display:grid;place-items:center;
       min-height:100vh;margin:0;background:#1b1b1f;color:#f5f5f5}}
  .card{{background:#26262b;padding:3rem 4rem;border-radius:14px;text-align:center;
        border:1px solid #3a3a42}}
  h1{{margin:0 0 .5rem;font-size:2.5rem;color:#4b8bbe}}
  p{{margin:.25rem 0;color:#a5a5b0}}
  code{{background:#15151a;padding:.15rem .45rem;border-radius:5px;color:#ffd43b}}
</style></head>
<body><div class="card">
  <h1>Hello World</h1>
  <p>Python + Flask running in Docker</p>
  <p>Python <code>{platform.python_version()}</code> &middot;
     container <code>{socket.gethostname()}</code></p>
</div></body></html>"""


@app.route("/health")
def health():
    return jsonify(status="ok", app="python")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
