# cm-th-ex
Cloudmile Take-home Exercise: GCP Cloud Operations hands-on homework.

## Documentation

| Doc | Content |
|-----|---------|
| [00-prerequisites.md](docs/00-prerequisites.md) | Workstation, credentials, region, budget, quotas, API bootstrap, remote state bucket |
| [01-task-1-infrastructure.md](docs/01-task-1-infrastructure.md) | Task 1: Terraform platform (VPC, NAT, firewall, private GKE, Cloud SQL, Secret Manager, IAM), architecture diagram |
| [02-task-2-gke-deployment.md](docs/02-task-2-gke-deployment.md) | Task 2: sample app on GKE, Cloud SQL via Auth Proxy, HTTPS Ingress, rolling update, rollback, scaling, HPA |
| [03-task-3-observability.md](docs/03-task-3-observability.md) | Task 3: dashboard, 4 alert policies, email channel, uptime check, log based metric, alert fire and resolve timeline |
| [04-task-4-break-fix-rca.md](docs/04-task-4-break-fix-rca.md) | Task 4: firewall rule blocking LB health checks, symptoms, diagnosis, 5 Whys, fix, preventive controls verified by re-injection |
| [05-task-5-healthcheck.md](docs/05-task-5-healthcheck.md) | Task 5: health check script (pods, HPA, Cloud SQL, endpoint), JSON output, pass and fail runs |
| [06-task-6-cleanup-readiness.md](docs/06-task-6-cleanup-readiness.md) | Task 6: destroy order, `terraform plan -destroy` output, what gets removed and what stays (nothing destroyed yet) |

## Repository layout

```
terraform/bootstrap/   APIs and Terraform state bucket
terraform/platform/    Task 1 platform (modules: network, gke, cloudsql, secrets, iam, registry, ingress, monitoring)
app/                   Task 2 sample app (Python, Dockerfile)
k8s/                   Task 2 Kubernetes manifests
scripts/               Helper and demo scripts
evidence/              Raw command outputs per task
src/                   Screenshots used in the docs
docs/                  Step by step documentation per task
```

## Quick start

```bash
# 1. bootstrap (once): enables APIs, creates the state bucket
#    first run uses local state because the bucket does not exist yet
cd terraform/bootstrap
mv backend.tf backend.tf.off && terraform init && terraform apply
mv backend.tf.off backend.tf && terraform init -migrate-state
rm -f terraform.tfstate terraform.tfstate.backup

# 2. platform
cd ../platform
cp admin.auto.tfvars.example admin.auto.tfvars   # set your public IP
terraform init && terraform plan -out=platform.tfplan && terraform apply platform.tfplan

# 3. connect kubectl
gcloud container clusters get-credentials cm-gke --zone asia-southeast1-a --project cloud-mile-assessment

# 4. app (Task 2)
kubectl apply -f k8s/00-namespace.yaml
scripts/create-app-secret.sh
kubectl apply -f k8s/

# 5. health check (Task 5), prints json, exit 1 if unhealthy
scripts/healthcheck.py

# 6. cleanup (Task 6), plan only unless --destroy is given. do not run before the live defense
scripts/cleanup.sh
```

## AI Usage Log

**Tool:** Claude Code, running gcloud, terraform and kubectl from WSL against the sandbox project.

**How it was used:** Claude drafted the Terraform, the Kubernetes manifests, the scripts and the docs, and ran commands. I reviewed every `terraform plan` before applying it and checked each result against raw output in `evidence/`. I made the design decisions and did the console work (budget alert, Cloudflare DNS, screenshots). Where a first attempt was wrong, the fix is recorded in the docs and tagged in the code with `# from task N - was ...`.

### Prerequisites

| Prompt / Question | Tool Used | Output Accepted? | What You Verified | What You Rejected / Changed |
|---|---|---|---|---|
| Check the workstation tools, gcloud auth, ADC and the active project | Claude Code | Yes | Tool versions, active account, project ACTIVE, billing enabled, ADC token issued (`evidence/prerequisites/`) | Billing account ID redacted, since the repo is public |
| Check the free trial quotas before designing the cluster | Claude Code | Yes | `E2_CPUS` limit of 8 allows at most 3 x 2 vCPU nodes plus 1 surge node (`05-compute-quotas.txt`) | None |
| Enable the APIs and create the Terraform state bucket | Claude Code | Partly | Plan of 13 to add, bucket has versioning, uniform access and public access prevention, no drift plan after the state migration | Done in Terraform (`terraform/bootstrap`) instead of manual gcloud. State created locally first, then moved into the bucket with `init -migrate-state` |

### Task 1: Infrastructure as Code

| Prompt / Question | Tool Used | Output Accepted? | What You Verified | What You Rejected / Changed |
|---|---|---|---|---|
| Write the Task 1 platform in Terraform as modules (network, gke, cloudsql, secrets, iam, registry) with GCS remote state | Claude Code | Yes | Plan of 24 to add, apply, `output -json`, `state list`, gcloud describe for every resource (`evidence/task-1/platform/`) | None |
| Make the service accounts least privilege | Claude Code | Partly | IAM policy output: node SA uses `container.defaultNodeServiceAccount`, `cm-app` can read only one secret, Workload Identity binding exists for `app/app-ksa` only | Node SA gets registry read on the `cm-app` repo only, not project wide. `cloudsql.client` restricted with an IAM condition to instance `cm-pg` |
| Set up Cloud SQL with a private IP | Claude Code | Partly | `ipv4Enabled: false`, private IP `10.172.80.3`, `ENCRYPTED_ONLY` | Edition set to Enterprise, because PG16 defaults to Enterprise Plus, which has no `db-f1-micro` tier. Noted that the generated password also ends up in Terraform state |
| The autoscaler went straight to 3 nodes and one pod stayed Pending. Why? | Claude Code | Partly | `kubectl describe nodes`: GKE system pods used 82% to 100% of the 940m CPU an e2-medium node can give to pods | Machine type changed from `e2-medium` to `e2-standard-2` (same vCPU quota). After the change: 41% to 47% CPU requested, nothing Pending |
| Why does `terraform plan` show a change on the cluster when nothing changed? | Claude Code | Yes | The GKE API returns `enable_components` in a different order from the code | Reordered the list in code to match the API. Final plan is clean (`08-plan-no-drift.txt`) |

### Task 2: GKE Deployment and Operations

| Prompt / Question | Tool Used | Output Accepted? | What You Verified | What You Rejected / Changed |
|---|---|---|---|---|
| Suggest a small app that can also produce the Task 3 alerts and the Task 4 faults | Claude Code | Partly | Local docker smoke test: `/healthz` 200, `/readyz` 503 with no DB, `/error` 403 without the token | Chaos endpoints locked behind a ConfigMap flag plus a token held in a Kubernetes Secret, which a script generates so it is never committed |
| Connect the app to Cloud SQL using the Auth Proxy and Workload Identity | Claude Code | Yes | `/db` from inside the pod returned PostgreSQL 16.15 and the visit count went up. CSI mount present. Proxy logs show connections accepted (`08-cloudsql-connectivity.txt`) | None |
| Expose the app over HTTPS on my own domain | Claude Code | Partly | ManagedCertificate Active, HTTP returns a 301 redirect, `openssl s_client` shows the Google cert for `cm-app.sokay.my` (`13-https-ingress.txt`) | Static IP moved into Terraform (`ingress` module). I created the Cloudflare record as DNS only, because a proxied record blocks the Google managed cert |
| Show a rolling update, a rollback and scaling | Claude Code | Partly | Pod versions in curl output, `rollout history`, HPA events scaling 2 to 6 to 2 (`09` to `12`) | Manual scaling done through HPA `minReplicas`, because `kubectl scale` gets overwritten by the HPA. `replicas` left out of the Deployment. HPA scales on the app container CPU only, so the proxy sidecar is ignored |
| Make the root page an interactive web UI | Claude Code | Yes | v3 rolled out, curl still gets JSON, CSP and security headers present (`14-ui-update-v3.txt`) | CSS and JS kept in separate files so a strict `default-src 'self'` policy works |

### Task 3: Observability and Alerting

| Prompt / Question | Tool Used | Output Accepted? | What You Verified | What You Rejected / Changed |
|---|---|---|---|---|
| Build the dashboard, the 4 alert policies, the uptime check, the log based metric and the email channel in Terraform | Claude Code | Partly | First apply failed with `Field not found: 'label'` (`02-tf-apply-monitoring.txt`) | Log metric filter changed to `resource.labels` (Logging syntax, not the Monitoring syntax). Reapplied cleanly (`04`) |
| Why is the plan not clean after the apply? | Claude Code | Partly | API adds `targetAxis` to the dashboard and strips the trailing newline from the alert docs. Plan returns exit 0 after the fix (`07-tf-plan-no-drift.txt`) | Set `targetAxis` explicitly and wrapped the alert docs in `chomp()` |
| What threshold is 80% of Cloud SQL connections? | Claude Code | Yes | `SHOW max_connections` returned 25, so the threshold is 20, calculated in Terraform | Demo holds 20 connections, not the 22 the app user can reach, so readiness checks keep working and the alert test does not cause an outage |
| Fire and resolve one alert, with a timeline | Claude Code | Yes | Firing and recovered emails, alert open 18:04:35 and closed 18:09:42 MYT, Monitoring API samples (`09-alert-sql-connections-timeline.txt`) | None |
| Check that the log based metric captures real errors | Claude Code | Partly | 20 ERROR entries and matching metric series (`10-log-metric-evidence.txt`) | Excluded gunicorn `[INFO]` lines from the metric. GKE labels them ERROR because they go to stderr, so every pod start and stop was being counted as an app error |

### Task 4: Break / Fix / RCA

| Prompt / Question | Tool Used | Output Accepted? | What You Verified | What You Rejected / Changed |
|---|---|---|---|---|
| Pick a fault from the approved menu that tests the monitoring end to end | Claude Code | Yes | Chose 1b (firewall blocking health checks). It is on the approved list and not on the "do not choose" list | None |
| Capture the before state and a way to watch the outage | Claude Code | Partly | Before state all healthy, Connectivity Test REACHABLE (`01-before-state.txt`) | Added `networkmanagement.googleapis.com` to the bootstrap Terraform so the Connectivity Test could run. Added a watcher script (`task4-watch.sh`) |
| Diagnose the 502s | Claude Code | Yes | Pods Ready while the LB backends were UNHEALTHY, the audit log shows the firewall insert, the Connectivity Test names the deny rule (`04-diagnosis.txt`). Ran the health check myself during the fault (`05-healthcheck-during-fault-user-run.txt`) | None |
| Suggest preventive controls | Claude Code | Partly | Re-injected the same deny rule: every sample 200, backends HEALTHY (`10`, `11`). The firewall change alert fired (`13-alerts-api.txt`) | Health check allow rule moved from priority 1000 to 0. New alert on firewall changes, excluding GKE's own service agent. Access restrictions and a hierarchical firewall policy not implemented (single user sandbox, no organization) |

### Task 5: Automation Script

| Prompt / Question | Tool Used | Output Accepted? | What You Verified | What You Rejected / Changed |
|---|---|---|---|---|
| Write a Python health check for pods, HPA, Cloud SQL and the endpoint, with JSON output and a non-zero exit code on failure | Claude Code | Yes | Pass run with exit 0 (`08-run-pass.txt`), fail run with exit 1 (`10-run-fail-scale-to-zero.txt`) | Standard library only, so it needs no pip install |
| The first run passed but both pods were on one node. Is that a problem? | Claude Code | Partly | Warn run (`01-run-warn-single-node.txt`). The autoscaler had shrunk the pool to 1 node | Added a single node warning to the script. Node pool minimum raised from 1 to 2 in Terraform, plus a one time resize |
| Why did a rollout put both new pods on the same node? | Claude Code | Partly | Pods one per node after the change (`07-topology-spread-fix.txt`) | Topology spread changed from `ScheduleAnyway` to `DoNotSchedule`, with `matchLabelKeys: [pod-template-hash]` and `nodeTaintsPolicy: Honor` |
| The script failed during a rollout even though the app was fine | Claude Code | Partly | Race reproduced (`03a`), then a pass during a rolling restart (`09-run-during-rollout.txt`) | Script now skips terminating pods and tries the next pod if exec fails |
| How do we show the failing case? | Claude Code | Yes | All 4 checks failed with clear reasons, recovery took about 1 minute | Scaled to zero here, not in Task 4, because the brief bans it as a Task 4 fault |

### Task 6: Cleanup Readiness

| Prompt / Question | Tool Used | Output Accepted? | What You Verified | What You Rejected / Changed |
|---|---|---|---|---|
| Produce the destroy plan without destroying anything | Claude Code | Yes | `plan -destroy`: platform 34, bootstrap 14, both exit 0, no saved plan file (`evidence/task-6/`) | Nothing destroyed before the live defense |
| Write a cleanup script that runs in the right order | Claude Code | Partly | Read the script: it only plans by default, and `--destroy` asks for the project ID and has no `-auto-approve` | Delete the Kubernetes app before the cluster so GKE removes the LB and NEGs. Turn off deletion protection with an apply before destroy. Remove the Cloudflare record by hand to avoid a subdomain takeover |
