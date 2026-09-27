#!/usr/bin/env bash
# from task 2 - scale up/down demo, manual (hpa min) then automatic (cpu load via /cpu)
set -uo pipefail

NS=app
OUT_DIR="${1:-evidence/task-2}"

ts() { date -u +%FT%TZ; }
run() { echo "\$ $*"; "$@" 2>&1; echo; }
snap() { echo "## $(ts) $1"; run kubectl -n $NS get hpa app; run kubectl -n $NS get pods -l app=cm-app -o wide; }

# part 1 - manual scale through the hpa, kubectl scale on the deployment would get undone by the hpa
{
  snap "manual: start"
  echo "## $(ts) manual: scale up, hpa minReplicas 2 -> 4"
  run kubectl -n $NS patch hpa app -p '{"spec":{"minReplicas":4}}'
  kubectl -n $NS wait --for=condition=available deploy/app --timeout=180s >/dev/null
  sleep 30
  snap "manual: after scale up"
  echo "## $(ts) manual: scale down, hpa minReplicas 4 -> 2 (scale down stabilization 120s)"
  run kubectl -n $NS patch hpa app -p '{"spec":{"minReplicas":2}}'
  sleep 180
  snap "manual: after scale down"
} > "$OUT_DIR/11-scale-manual.txt" 2>&1

# part 2 - hpa autoscaling from cpu load
TOKEN="$(kubectl -n $NS get secret app-chaos -o jsonpath='{.data.token}' | base64 -d)"
{
  snap "hpa: start"
  echo "## $(ts) hpa: burn cpu for 240s on every pod via /cpu"
  for p in $(kubectl -n $NS get pod -l app=cm-app -o jsonpath='{.items[*].metadata.name}'); do
    echo "\$ kubectl -n $NS exec $p -c app -- (GET /cpu?seconds=240 with X-Chaos-Token)"
    kubectl -n $NS exec "$p" -c app -- python -c "import urllib.request,sys;r=urllib.request.Request('http://localhost:8080/cpu?seconds=240',headers={'X-Chaos-Token':sys.argv[1]});print(urllib.request.urlopen(r).read().decode())" "$TOKEN" 2>&1
  done
  echo
  for i in $(seq 1 24); do
    sleep 20
    echo "## $(ts) hpa: t+$((i * 20))s"
    kubectl -n $NS get hpa app --no-headers 2>&1
    kubectl -n $NS top pods -l app=cm-app --containers 2>&1 | grep -E "NAME| app " || true
    echo
  done
  run kubectl -n $NS describe hpa app
  snap "hpa: end"
} > "$OUT_DIR/12-scale-hpa.txt" 2>&1

echo "done"
