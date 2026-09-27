#!/usr/bin/env bash
# from task 2 - create the app-chaos k8s secret with a random token, so nothing secret is committed
set -euo pipefail

NAMESPACE="${NAMESPACE:-app}"

# keep the existing token if the secret is already there
if kubectl -n "$NAMESPACE" get secret app-chaos >/dev/null 2>&1; then
  echo "secret app-chaos already exists in $NAMESPACE, leaving it"
  exit 0
fi

TOKEN="$(openssl rand -hex 16)"
kubectl -n "$NAMESPACE" create secret generic app-chaos --from-literal=token="$TOKEN"
echo "created secret app-chaos in $NAMESPACE"
echo "get the token with: kubectl -n $NAMESPACE get secret app-chaos -o jsonpath='{.data.token}' | base64 -d"
