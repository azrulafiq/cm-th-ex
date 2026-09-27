#!/usr/bin/env bash
# from task 4 - watch the public endpoint and lb backend health during the fault, one line per sample
# stops when /tmp/task4-stop exists or after MAX_MINUTES
set -uo pipefail

URL="${URL:-https://cm-app.sokay.my/healthz}"
BS="${BS:-k8s1-75b98460-app-app-80-a291f78d}"
PROJECT="${PROJECT:-cloud-mile-assessment}"
MAX_MINUTES="${MAX_MINUTES:-60}"

rm -f /tmp/task4-stop
end=$(( $(date +%s) + MAX_MINUTES * 60 ))
i=0
echo "time(MYT)           http  latency   lb_backend_health"
while [ ! -f /tmp/task4-stop ] && [ "$(date +%s)" -lt "$end" ]; do
  code_time="$(curl -s -o /dev/null -m 10 -w '%{http_code} %{time_total}s' "$URL")"
  health="-"
  # backend health every 30s, it is a slower api call
  if [ $((i % 3)) -eq 0 ]; then
    health="$(gcloud compute backend-services get-health "$BS" --global --project "$PROJECT" \
      --format='value(status.healthStatus[].healthState)' 2>/dev/null | tr ';\n' '  ')"
  fi
  printf '%s  %s  %s\n' "$(TZ=Asia/Kuala_Lumpur date +%FT%T)" "$code_time" "$health"
  i=$((i + 1))
  sleep 10
done
echo "watch stopped $(TZ=Asia/Kuala_Lumpur date +%FT%T)"
