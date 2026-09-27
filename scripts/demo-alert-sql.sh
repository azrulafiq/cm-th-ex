#!/usr/bin/env bash
# from task 3 - fire and resolve the cloud sql connections alert, plus some app errors for the log metric
set -uo pipefail

NS=app
PROJECT=cloud-mile-assessment
HOST="https://cm-app.sokay.my"
HOLD_N="${HOLD_N:-20}"
HOLD_SECONDS="${HOLD_SECONDS:-360}"
WATCH_MINUTES="${WATCH_MINUTES:-14}"

ts() { date -u +%FT%TZ; }

TOKEN="$(kubectl -n $NS get secret app-chaos -o jsonpath='{.data.token}' | base64 -d)"
POD="$(kubectl -n $NS get pod -l app=cm-app -o jsonpath='{.items[0].metadata.name}')"

# sum of num_backends over the last 2 minutes, latest point per database
backends() {
  local tok now ago
  tok="$(gcloud auth print-access-token)"
  now="$(date -u +%FT%TZ)"
  ago="$(date -u -d '-2 min' +%FT%TZ)"
  curl -s -G -H "Authorization: Bearer $tok" "https://monitoring.googleapis.com/v3/projects/$PROJECT/timeSeries" \
    --data-urlencode 'filter=metric.type="cloudsql.googleapis.com/database/postgresql/num_backends"' \
    --data-urlencode "interval.startTime=$ago" --data-urlencode "interval.endTime=$now" |
    python3 -c 'import json,sys
d=json.load(sys.stdin); parts={}
for s in d.get("timeSeries",[]):
    parts[s["metric"]["labels"]["database"]]=int(s["points"][0]["value"]["int64Value"])
print("total=%d %s" % (sum(parts.values()), parts))'
}

echo "## $(ts) baseline"
echo "num_backends: $(backends)"
echo

echo "## $(ts) send 10 x GET /error through the https lb (log based metric + 5xx rate)"
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{http_code} " -H "X-Chaos-Token: $TOKEN" "$HOST/error"
done
echo
echo

echo "## $(ts) hold $HOLD_N db connections for ${HOLD_SECONDS}s from pod $POD"
kubectl -n $NS exec "$POD" -c app -- python -c "import urllib.request,sys;r=urllib.request.Request('http://localhost:8080/connections?n=$HOLD_N&seconds=$HOLD_SECONDS',headers={'X-Chaos-Token':sys.argv[1]});print(urllib.request.urlopen(r).read().decode())" "$TOKEN" 2>&1
echo

end=$(( $(date +%s) + WATCH_MINUTES * 60 ))
while [ "$(date +%s)" -lt "$end" ]; do
  sleep 30
  echo "$(ts) num_backends: $(backends)  readyz: $(curl -s -o /dev/null -w "%{http_code}" "$HOST/readyz")"
done
echo
echo "## $(ts) done (connections released at hold start + ${HOLD_SECONDS}s)"
