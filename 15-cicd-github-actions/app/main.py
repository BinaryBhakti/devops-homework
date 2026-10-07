"""Calculator API — the Session 16 calculator, exposed over HTTP so it can be deployed."""

import os

from flask import Flask, jsonify, request

from app.calculator import OPERATIONS, calculate

APP_VERSION = os.getenv("APP_VERSION", "dev")
GIT_SHA = os.getenv("GIT_SHA", "local")


def create_app() -> Flask:
    app = Flask(__name__)

    @app.get("/")
    def index():
        return jsonify(
            app="hw15-calculator",
            message="Hello from the Session 16 CI/CD pipeline",
            version=APP_VERSION,
            git_sha=GIT_SHA,
            operations=list(OPERATIONS),
        )

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    @app.get("/api/<op>")
    def api(op: str):
        try:
            a = float(request.args["a"])
            b = float(request.args["b"])
        except KeyError as missing:
            return jsonify(error=f"missing query parameter {missing}"), 400
        except ValueError:
            return jsonify(error="a and b must be numbers"), 400
        try:
            result = calculate(op, a, b)
        except ValueError as err:
            return jsonify(error=str(err)), 400
        return jsonify(operation=op, a=a, b=b, result=result)

    return app


app = create_app()

if __name__ == "__main__":  # pragma: no cover - local dev only
    app.run(host="127.0.0.1", port=8000)
