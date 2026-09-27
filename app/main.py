# from task 2 - sample app for gke, talks to cloud sql through the auth proxy sidecar
# chaos endpoints are for task 3 alerts and task 4 faults, locked behind a flag + token

import json
import logging
import multiprocessing
import os
import signal
import socket
import sys
import threading
import time

import psycopg
from flask import Flask, g, jsonify, render_template, request

APP_VERSION = os.getenv("APP_VERSION", "dev")
POD_NAME = os.getenv("POD_NAME", socket.gethostname())
MESSAGE = os.getenv("APP_MESSAGE", "hello from cm-app")

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "appdb")
DB_USER = os.getenv("DB_USER", "app")
DB_PASSWORD_FILE = os.getenv("DB_PASSWORD_FILE", "/secrets/db/db-password")

CHAOS_ENABLED = os.getenv("CHAOS_ENABLED", "false").lower() == "true"
CHAOS_TOKEN = os.getenv("CHAOS_TOKEN", "")


# json logs to stdout, cloud logging picks up "severity" automatically
class JsonFormatter(logging.Formatter):
    def format(self, record):
        entry = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "version": APP_VERSION,
            "pod": POD_NAME,
        }
        entry.update(getattr(record, "extra_fields", {}))
        return json.dumps(entry)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
log = logging.getLogger("cm-app")
log.addHandler(handler)
log.setLevel(logging.INFO)
log.propagate = False


def log_event(level, message, **fields):
    log.log(level, message, extra={"extra_fields": fields})


# fail on purpose at startup, used to force CrashLoopBackOff from the configmap
if os.getenv("CRASH_ON_START", "false").lower() == "true":
    log_event(logging.CRITICAL, "CRASH_ON_START is true, exiting")
    sys.exit(1)

app = Flask(__name__)


def db_password():
    # read every time so a rotated secret or a broken one shows up straight away
    with open(DB_PASSWORD_FILE) as f:
        return f.read().strip()


def db_connect(timeout=3):
    return psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=db_password(),
        connect_timeout=timeout,
    )


def init_db():
    try:
        with db_connect() as conn:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS visits ("
                " id SERIAL PRIMARY KEY,"
                " pod TEXT NOT NULL,"
                " version TEXT NOT NULL,"
                " ts TIMESTAMPTZ NOT NULL DEFAULT now())"
            )
        log_event(logging.INFO, "db init ok")
    except Exception as e:
        # dont crash, readiness will keep the pod out of the lb until db works
        log_event(logging.WARNING, "db init failed", error=str(e))


def chaos_allowed():
    return CHAOS_ENABLED and CHAOS_TOKEN and request.headers.get("X-Chaos-Token") == CHAOS_TOKEN


def chaos_denied():
    return jsonify(error="chaos endpoints disabled or bad token"), 403


@app.before_request
def start_timer():
    g.start = time.monotonic()


@app.after_request
def access_log(resp):
    latency_ms = round((time.monotonic() - g.start) * 1000, 1)
    # basic hardening, page only loads its own css/js
    resp.headers["Content-Security-Policy"] = "default-src 'self'; frame-ancestors 'none'"
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Referrer-Policy"] = "no-referrer"
    if request.path.startswith("/api/") or request.path in ("/db", "/readyz", "/healthz"):
        resp.headers["Cache-Control"] = "no-store"
    # skip probe and static noise
    if request.path not in ("/healthz", "/readyz") and not request.path.startswith("/static/"):
        level = logging.ERROR if resp.status_code >= 500 else logging.INFO
        log_event(
            level,
            f"{request.method} {request.path} {resp.status_code}",
            path=request.path,
            status=resp.status_code,
            latency_ms=latency_ms,
        )
    return resp


def info():
    return {"message": MESSAGE, "version": APP_VERSION, "pod": POD_NAME}


@app.get("/")
def index():
    # browsers get the page, curl/scripts get json like before
    if request.accept_mimetypes.best_match(["application/json", "text/html"]) == "text/html":
        return render_template("index.html", **info())
    return jsonify(info())


@app.get("/api/info")
def api_info():
    return jsonify(info())


@app.get("/healthz")
def healthz():
    # liveness only, never touches the db so a db blip doesnt restart every pod
    return jsonify(status="ok")


@app.get("/readyz")
def readyz():
    try:
        with db_connect(timeout=2) as conn:
            conn.execute("SELECT 1")
        return jsonify(status="ready")
    except Exception as e:
        log_event(logging.WARNING, "readiness db check failed", error=str(e))
        return jsonify(status="not ready", error=str(e)), 503


@app.get("/db")
def db():
    try:
        with db_connect() as conn:
            conn.execute("INSERT INTO visits (pod, version) VALUES (%s, %s)", (POD_NAME, APP_VERSION))
            now, version = conn.execute("SELECT now(), version()").fetchone()
            visits = conn.execute("SELECT count(*) FROM visits").fetchone()[0]
            conns = conn.execute("SELECT count(*) FROM pg_stat_activity WHERE datname = %s", (DB_NAME,)).fetchone()[0]
        return jsonify(db_time=now.isoformat(), db_version=version, visits=visits, db_connections=conns, pod=POD_NAME)
    except Exception as e:
        log_event(logging.ERROR, "db query failed", error=str(e))
        return jsonify(error=str(e)), 500


# chaos endpoints


@app.get("/error")
def error():
    if not chaos_allowed():
        return chaos_denied()
    log_event(logging.ERROR, "simulated application error", kind="simulated")
    return jsonify(error="simulated error"), 500


@app.get("/slow")
def slow():
    if not chaos_allowed():
        return chaos_denied()
    ms = min(int(request.args.get("ms", 1000)), 10000)
    time.sleep(ms / 1000)
    return jsonify(slept_ms=ms)


def _burn(seconds):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        pass


@app.get("/cpu")
def cpu():
    if not chaos_allowed():
        return chaos_denied()
    seconds = min(int(request.args.get("seconds", 30)), 600)
    # separate process so the web workers and probes stay responsive
    multiprocessing.Process(target=_burn, args=(seconds,), daemon=True).start()
    return jsonify(burning_seconds=seconds)


_hold = []


@app.get("/memory")
def memory():
    if not chaos_allowed():
        return chaos_denied()
    mb = min(int(request.args.get("mb", 100)), 2048)
    _hold.append(bytearray(mb * 1024 * 1024))
    return jsonify(allocated_mb=mb, total_held_mb=sum(len(b) for b in _hold) // (1024 * 1024))


def _hold_connections(n, seconds):
    conns = []
    try:
        for _ in range(n):
            conns.append(db_connect())
        log_event(logging.WARNING, "holding db connections", count=len(conns), seconds=seconds)
        time.sleep(seconds)
    except Exception as e:
        log_event(logging.ERROR, "could not open db connection", opened=len(conns), error=str(e))
        time.sleep(seconds)
    finally:
        for c in conns:
            c.close()


@app.get("/connections")
def connections():
    if not chaos_allowed():
        return chaos_denied()
    n = min(int(request.args.get("n", 10)), 50)
    seconds = min(int(request.args.get("seconds", 300)), 1800)
    threading.Thread(target=_hold_connections, args=(n, seconds), daemon=True).start()
    return jsonify(holding=n, seconds=seconds)


@app.get("/crash")
def crash():
    if not chaos_allowed():
        return chaos_denied()
    log_event(logging.CRITICAL, "crash requested, killing gunicorn master")
    # stop pid 1 (gunicorn master) so the container exits and kubelet restarts it
    threading.Timer(0.5, lambda: os.kill(1, signal.SIGINT)).start()
    return jsonify(crashing=True)


init_db()
