#!/usr/bin/env bash
# from task 6 - tear down everything in the right order. DO NOT run before the live defense.
#
#   scripts/cleanup.sh                                  plan only (terraform plan -destroy), changes nothing
#   scripts/cleanup.sh --destroy                        destroy app + platform, keeps bootstrap (apis, state bucket)
#   scripts/cleanup.sh --destroy --include-bootstrap    also empty and delete the state bucket
#
# the gcp project itself is never deleted.
set -euo pipefail

PROJECT="cloud-mile-assessment"
ZONE="asia-southeast1-a"
CLUSTER="cm-gke"
STATE_BUCKET="gs://${PROJECT}-tfstate"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_PLATFORM="$ROOT/terraform/platform"
TF_BOOTSTRAP="$ROOT/terraform/bootstrap"

DESTROY=false
INCLUDE_BOOTSTRAP=false
for arg in "$@"; do
  case "$arg" in
    --destroy) DESTROY=true ;;
    --include-bootstrap) INCLUDE_BOOTSTRAP=true ;;
    *) echo "unknown option: $arg"; exit 2 ;;
  esac
done

step() { printf '\n== %s  %s\n' "$(TZ=Asia/Kuala_Lumpur date +%T)" "$*"; }

# plan only by default
if [ "$DESTROY" != true ]; then
  step "plan only, nothing will be changed"
  terraform -chdir="$TF_PLATFORM" plan -destroy
  terraform -chdir="$TF_BOOTSTRAP" plan -destroy
  echo
  echo "to really destroy: $0 --destroy [--include-bootstrap]"
  exit 0
fi

read -r -p "type the project id ($PROJECT) to confirm destroy: " answer
[ "$answer" = "$PROJECT" ] || { echo "not confirmed, stopping"; exit 1; }

# 1. app first. deleting the ingress makes gke remove the lb, negs, k8s-fw-l7 firewall rule and managed cert.
#    if the cluster goes first those are left behind and block the vpc delete.
step "1. delete kubernetes app (namespace app)"
gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT"
kubectl delete -f "$ROOT/k8s/" --ignore-not-found --wait=true

step "   wait for gke to remove the load balancer and negs"
for _ in $(seq 1 60); do
  negs="$(gcloud compute network-endpoint-groups list --project "$PROJECT" --format='value(name)' --filter='name~^k8s1-' | wc -l)"
  fwd="$(gcloud compute forwarding-rules list --project "$PROJECT" --global --format='value(name)' --filter='name~^k8s2-' | wc -l)"
  [ "$negs" -eq 0 ] && [ "$fwd" -eq 0 ] && break
  echo "   negs=$negs forwarding_rules=$fwd, waiting..."
  sleep 10
done

# 2. things created outside terraform
step "2. delete resources created outside terraform"
gcloud network-management connectivity-tests delete lb-hc-to-app-pod --project "$PROJECT" --quiet || true

# 3. deletion protection is on for gke and cloud sql, it has to be switched off with an apply first
step "3. turn off deletion protection (apply)"
terraform -chdir="$TF_PLATFORM" apply -var=deletion_protection=false

# 4. destroy the platform. the private services peering is set to ABANDON in terraform,
#    if the vpc delete then fails because the peering still exists, remove it and retry once.
step "4. terraform destroy platform"
if ! terraform -chdir="$TF_PLATFORM" destroy -var=deletion_protection=false; then
  step "   destroy failed, removing the servicenetworking peering and retrying"
  gcloud compute networks peerings delete servicenetworking-googleapis-com --network=cm-vpc --project "$PROJECT" --quiet || true
  terraform -chdir="$TF_PLATFORM" destroy -var=deletion_protection=false
fi

# 5. optional: bootstrap. its own state lives in the bucket it would delete, so move state to local first,
#    then empty the bucket (versioning keeps old copies) so force_destroy=false does not block it.
if [ "$INCLUDE_BOOTSTRAP" = true ]; then
  step "5. bootstrap: move state to local, empty the bucket, destroy"
  mv "$TF_BOOTSTRAP/backend.tf" "$TF_BOOTSTRAP/backend.tf.off"
  terraform -chdir="$TF_BOOTSTRAP" init -migrate-state -force-copy
  gcloud storage rm --recursive --all-versions "$STATE_BUCKET/**" || true
  terraform -chdir="$TF_BOOTSTRAP" destroy
  echo "   bootstrap state is now local (terraform/bootstrap/terraform.tfstate, gitignored); delete it when done"
fi

# 6. what is left
step "6. leftovers check"
gcloud compute networks list --project "$PROJECT"
gcloud compute firewall-rules list --project "$PROJECT"
gcloud compute addresses list --project "$PROJECT"
gcloud sql instances list --project "$PROJECT"
gcloud container clusters list --project "$PROJECT"

cat <<'EOF'

manual follow ups:
- delete the cloudflare dns record cm-app.sokay.my (A 8.232.93.111), the ip is released and could be reused by someone else
- cloud sql instance name cm-pg stays reserved for about a week
- logs stay in the _Default log bucket until retention (30 days)
- the project cloud-mile-assessment is kept on purpose
EOF
