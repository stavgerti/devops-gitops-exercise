import html
import os
import socket

from flask import Flask

app = Flask(__name__)

MESSAGE = os.environ.get("APP_MESSAGE", "Hello from the GitOps exercise!")
VERSION = os.environ.get("APP_VERSION", "dev")
# Kubernetes sets HOSTNAME to the pod name; POD_NAME (Downward API) wins if set.
POD_NAME = os.environ.get("POD_NAME") or socket.gethostname()


@app.get("/")
def index():
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>GitOps exercise</title></head>
<body style="font-family: sans-serif; margin: 3rem">
  <h1>{html.escape(MESSAGE)}</h1>
  <p>Version: <b>{html.escape(VERSION)}</b></p>
  <p>Served by pod: <b>{html.escape(POD_NAME)}</b></p>
</body></html>
"""


@app.get("/healthz")
def healthz():
    return "ok", 200
