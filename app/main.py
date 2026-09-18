"""
main.py — the "application" this whole pipeline exists to ship.

Deliberately trivial: a single Flask endpoint that returns its own
version string. The point of this project isn't the app, it's watching
a version-bump flow through CI, into a git commit, and out the other
side as a running pod change — so the app just needs to make that change
visible.

/version returns APP_VERSION, which is baked in at image build time via
a Docker build ARG. Each CI run passes a new value (its git SHA), so
after a deploy you can `curl` the NodePort and see the new SHA appear —
that's your proof the whole pipeline actually worked end to end.
"""
import os

from flask import Flask, jsonify

app = Flask(__name__)

APP_VERSION = os.environ.get("APP_VERSION", "dev")


@app.get("/")
def root():
    return jsonify(message="hello from the k8s CI/CD lab", version=APP_VERSION)


@app.get("/version")
def version():
    return jsonify(version=APP_VERSION)


@app.get("/healthz")
def healthz():
    # Separate from "/" on purpose: this is what the k8s liveness/readiness
    # probes hit in deployment.yaml. Real apps often split "am I alive" from
    # "here is my actual response," since a health check should stay cheap
    # and dependency-free even if the main app logic gets complex later.
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
