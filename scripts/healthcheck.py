#!/usr/bin/env python3
# from task 5 - health check for cm-app: pods, hpa, cloud sql, app endpoint
# prints json, exit 0 = healthy (warnings allowed), 1 = a check failed, 2 = script could not run
# stdlib only, needs kubectl (pointed at cm-gke) and gcloud in PATH

import argparse
import json
import shutil
import socket
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

MYT = timezone(timedelta(hours=8))
BAD_WAITING = {
    "CrashLoopBackOff",
    "ImagePullBackOff",
    "ErrImagePull",
    "CreateContainerConfigError",
    "CreateContainerError",
    "InvalidImageName",
}


class CheckError(Exception):
    pass


def run(cmd, timeout):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise CheckError(f"timed out after {timeout}s: {' '.join(cmd[:4])} ...")
    if p.returncode != 0:
        raise CheckError(f"{' '.join(cmd[:4])} ... failed: {p.stderr.strip()[:300]}")
    return p.stdout


def run_json(cmd, timeout):
    return json.loads(run(cmd, timeout))


def parse_time(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


# pods


def check_pods(args):
    data = run_json(["kubectl", "-n", args.namespace, "get", "pods", "-l", args.selector, "-o", "json"], args.timeout)
    now = datetime.now(timezone.utc)
    pods, problems, warnings = [], [], []
    ready_count = 0

    terminating = []
    for item in data.get("items", []):
        name = item["metadata"]["name"]
        # pods shutting down (rollout, scale down) are not part of serving capacity
        if item["metadata"].get("deletionTimestamp"):
            terminating.append(name)
            continue
        status = item.get("status", {})
        ready = any(c["type"] == "Ready" and c["status"] == "True" for c in status.get("conditions", []))
        ready_count += ready

        # native sidecars (cloud-sql-proxy) show up under initContainerStatuses
        containers = []
        for cs in status.get("containerStatuses", []) + status.get("initContainerStatuses", []):
            state = cs.get("state", {})
            waiting = state.get("waiting", {}).get("reason")
            last_term = cs.get("lastState", {}).get("terminated", {})
            last_reason = last_term.get("reason")
            last_finished = parse_time(last_term.get("finishedAt"))
            containers.append({
                "name": cs["name"],
                "ready": cs.get("ready", False),
                "restarts": cs.get("restartCount", 0),
                "state": waiting or next(iter(state), "unknown"),
                "last_terminated_reason": last_reason,
            })
            if waiting in BAD_WAITING:
                problems.append(f"{name}/{cs['name']}: {waiting}")
            elif last_finished and now - last_finished < timedelta(minutes=15):
                warnings.append(f"{name}/{cs['name']}: restarted {int((now - last_finished).total_seconds() // 60)} min ago ({last_reason})")

        pods.append({"name": name, "phase": status.get("phase"), "ready": ready, "node": item["spec"].get("nodeName"), "containers": containers})

    # 2+ replicas on one node is still a single point of failure
    ready_nodes = {p["node"] for p in pods if p["ready"]}
    if ready_count >= 2 and len(ready_nodes) == 1:
        warnings.append(f"all {ready_count} ready pods are on one node ({next(iter(ready_nodes))})")

    details = {"ready": ready_count, "total": len(pods), "min_ready": args.min_ready, "nodes": sorted(ready_nodes), "terminating": terminating, "pods": pods}
    if ready_count < args.min_ready:
        return "fail", f"{ready_count}/{len(pods)} pods ready, need at least {args.min_ready}", details, problems + warnings
    if problems:
        return "fail", f"{len(problems)} container(s) in a bad state", details, problems + warnings
    if warnings:
        return "warn", f"{ready_count}/{len(pods)} pods ready, {len(warnings)} warning(s)", details, warnings
    return "pass", f"{ready_count}/{len(pods)} pods ready", details, []


# hpa


def check_hpa(args):
    hpa = run_json(["kubectl", "-n", args.namespace, "get", "hpa", args.hpa, "-o", "json"], args.timeout)
    spec, status = hpa["spec"], hpa.get("status", {})
    conditions = {c["type"]: c for c in status.get("conditions", [])}

    cpu = None
    for m in status.get("currentMetrics", []) or []:
        res = m.get("containerResource") or m.get("resource") or {}
        if res.get("name") == "cpu":
            cpu = res.get("current", {}).get("averageUtilization")

    target = None
    for m in spec.get("metrics", []):
        res = m.get("containerResource") or m.get("resource") or {}
        if res.get("name") == "cpu":
            target = res.get("target", {}).get("averageUtilization")

    details = {
        "min": spec.get("minReplicas"),
        "max": spec.get("maxReplicas"),
        "current": status.get("currentReplicas"),
        "desired": status.get("desiredReplicas"),
        "cpu_utilization_pct": cpu,
        "cpu_target_pct": target,
        "conditions": {k: {"status": v["status"], "reason": v.get("reason")} for k, v in conditions.items()},
    }

    issues = []
    for cond in ("AbleToScale", "ScalingActive"):
        c = conditions.get(cond)
        if not c or c["status"] != "True":
            issues.append(f"{cond}={c['status'] if c else 'missing'} ({(c or {}).get('reason')}): {(c or {}).get('message', '')[:200]}")
    if issues:
        return "fail", "hpa cannot scale", details, issues

    if cpu is None:
        return "fail", "hpa has no current cpu metric", details, ["currentMetrics empty, metrics pipeline or resource requests broken"]

    limited = conditions.get("ScalingLimited")
    if limited and limited["status"] == "True" and limited.get("reason") == "TooManyReplicas":
        return "warn", f"at max replicas ({details['current']}/{details['max']}), cpu {cpu}%", details, ["hpa is capped at maxReplicas"]
    return "pass", f"{details['current']} replicas (min {details['min']}, max {details['max']}), cpu {cpu}% of target {target}%", details, []


# cloud sql


def check_cloudsql(args):
    inst = run_json(["gcloud", "sql", "instances", "describe", args.sql_instance, "--project", args.project, "--format=json"], args.timeout)
    state = inst.get("state")
    details = {
        "instance": args.sql_instance,
        "state": state,
        "database_version": inst.get("databaseVersion"),
        "private_ip": next((ip["ipAddress"] for ip in inst.get("ipAddresses", []) if ip.get("type") == "PRIVATE"), None),
    }
    if state != "RUNNABLE":
        return "fail", f"instance state {state}", details, [f"{args.sql_instance} is {state}"]

    # real query through the app pod and the auth proxy sidecar
    pods = run_json(["kubectl", "-n", args.namespace, "get", "pods", "-l", args.selector, "-o", "json"], args.timeout)
    live = [p for p in pods.get("items", []) if not p["metadata"].get("deletionTimestamp")]
    ready_pods = [
        p["metadata"]["name"]
        for p in live
        if any(c["type"] == "Ready" and c["status"] == "True" for c in p["status"].get("conditions", []))
    ]
    running_pods = [p["metadata"]["name"] for p in live if p["status"].get("phase") == "Running" and p["metadata"]["name"] not in ready_pods]
    candidates = ready_pods + running_pods
    if not candidates:
        return "fail", "no running app pod to test the db connection from", details, ["no pod available"]

    probe = (
        "import json,urllib.request,urllib.error\n"
        "try:\n"
        "  r=urllib.request.urlopen('http://localhost:8080/db',timeout=8); print(json.dumps({'code':r.status,'body':json.loads(r.read())}))\n"
        "except urllib.error.HTTPError as e:\n"
        "  print(json.dumps({'code':e.code,'body':e.read().decode()[:300]}))\n"
    )
    # a pod can go away between listing and exec, so try the next one
    exec_errors = []
    for target in candidates:
        try:
            out = run(["kubectl", "-n", args.namespace, "exec", target, "-c", "app", "--", "python", "-c", probe], args.timeout)
            res = json.loads(out.strip().splitlines()[-1])
            break
        except (CheckError, json.JSONDecodeError, IndexError) as e:
            exec_errors.append(f"{target}: {str(e)[:200]}")
    else:
        return "fail", "could not run the db query from any app pod", details, exec_errors
    body = res.get("body")
    details["tested_from_pod"] = target
    details["query_http_status"] = res.get("code")
    if res.get("code") != 200 or not isinstance(body, dict):
        return "fail", "db query through the auth proxy failed", details, [f"GET /db on {target} returned {res.get('code')}: {str(body)[:200]}"]

    details["db_version"] = body.get("db_version", "").split(" on ")[0]
    details["db_connections"] = body.get("db_connections")
    return "pass", f"{state}, query ok via {target} ({details['db_version']})", details, []


# endpoint


def cert_days_left(host, timeout):
    ctx = ssl.create_default_context()
    with socket.create_connection((host, 443), timeout=timeout) as sock:
        with ctx.wrap_socket(sock, server_hostname=host) as s:
            not_after = s.getpeercert()["notAfter"]
    expires = datetime.fromtimestamp(ssl.cert_time_to_seconds(not_after), timezone.utc)
    return (expires - datetime.now(timezone.utc)).days


def check_endpoint(args):
    url = args.url.rstrip("/") + "/healthz"
    start = time.monotonic()
    try:
        with urllib.request.urlopen(url, timeout=args.timeout) as r:
            code, body = r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        code, body = e.code, e.read().decode()[:200]
    except Exception as e:
        return "fail", f"{url} unreachable", {"url": url}, [str(e)]
    latency_ms = round((time.monotonic() - start) * 1000)

    host = urllib.parse.urlparse(args.url).hostname
    details = {"url": url, "http_status": code, "latency_ms": latency_ms}
    if args.url.startswith("https://"):
        try:
            details["cert_days_left"] = cert_days_left(host, args.timeout)
        except Exception as e:
            return "fail", "tls check failed", details, [str(e)]

    if code != 200 or '"status":"ok"' not in body.replace(" ", ""):
        return "fail", f"{url} returned {code}", details, [body[:200]]
    warnings = []
    if latency_ms > args.max_latency_ms:
        warnings.append(f"latency {latency_ms}ms over {args.max_latency_ms}ms")
    if details.get("cert_days_left", 999) < 14:
        warnings.append(f"certificate expires in {details['cert_days_left']} days")
    if warnings:
        return "warn", f"{code} in {latency_ms}ms", details, warnings
    return "pass", f"{code} in {latency_ms}ms, cert {details.get('cert_days_left')} days left", details, []


CHECKS = [("pods", check_pods), ("hpa", check_hpa), ("cloudsql", check_cloudsql), ("endpoint", check_endpoint)]


def main():
    ap = argparse.ArgumentParser(description="cm-app health check, prints json")
    ap.add_argument("--namespace", default="app")
    ap.add_argument("--selector", default="app=cm-app")
    ap.add_argument("--hpa", default="app")
    ap.add_argument("--min-ready", type=int, default=2, help="ready pods needed (default = hpa minReplicas)")
    ap.add_argument("--project", default="cloud-mile-assessment")
    ap.add_argument("--sql-instance", default="cm-pg")
    ap.add_argument("--url", default="https://cm-app.sokay.my")
    ap.add_argument("--timeout", type=int, default=20, help="seconds per command or request")
    ap.add_argument("--max-latency-ms", type=int, default=1000)
    ap.add_argument("--strict", action="store_true", help="treat warn as failure")
    args = ap.parse_args()

    missing = [t for t in ("kubectl", "gcloud") if not shutil.which(t)]
    if missing:
        print(json.dumps({"overall": "error", "error": f"missing tools: {', '.join(missing)}"}, indent=2))
        return 2

    started = time.monotonic()
    results = []
    for name, fn in CHECKS:
        t0 = time.monotonic()
        try:
            status, summary, details, messages = fn(args)
        except (CheckError, json.JSONDecodeError, KeyError) as e:
            status, summary, details, messages = "fail", "check could not complete", {}, [str(e)[:400]]
        results.append({
            "name": name,
            "status": status,
            "summary": summary,
            "messages": messages,
            "duration_ms": round((time.monotonic() - t0) * 1000),
            "details": details,
        })

    failed = [r["name"] for r in results if r["status"] == "fail"]
    warned = [r["name"] for r in results if r["status"] == "warn"]
    overall = "fail" if failed or (args.strict and warned) else ("warn" if warned else "pass")
    report = {
        "timestamp": datetime.now(MYT).isoformat(timespec="seconds"),
        "target": {"namespace": args.namespace, "hpa": args.hpa, "sql_instance": args.sql_instance, "url": args.url},
        "overall": overall,
        "failed_checks": failed,
        "warning_checks": warned,
        "duration_ms": round((time.monotonic() - started) * 1000),
        "checks": results,
    }
    print(json.dumps(report, indent=2))
    return 1 if overall == "fail" else 0


if __name__ == "__main__":
    sys.exit(main())
