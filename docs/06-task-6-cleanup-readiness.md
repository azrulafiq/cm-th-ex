# 06. Task 6: Cleanup Readiness

Nothing has been destroyed. The environment stays up for the live defense. This document gives the destroy commands, the output of `terraform plan -destroy`, and a note on what will be removed and what will be left behind.

All times in this document are MYT (UTC+8).

## Summary

| Brief requirement | Provided | Evidence |
|-------------------|----------|----------|
| `terraform destroy` command or cleanup script | [scripts/cleanup.sh](../scripts/cleanup.sh) (plan only by default) and the manual command sequence below | |
| Output of `terraform plan -destroy` | Platform: 34 to destroy. Bootstrap: 14 to destroy | [01-plan-destroy-platform.txt](../evidence/task-6/01-plan-destroy-platform.txt), [02-plan-destroy-bootstrap.txt](../evidence/task-6/02-plan-destroy-bootstrap.txt) |
| Short note on what will be removed | Below | |

## Plan output

```bash
cd terraform/platform  && terraform plan -destroy     # Plan: 0 to add, 0 to change, 34 to destroy.
cd terraform/bootstrap && terraform plan -destroy     # Plan: 0 to add, 0 to change, 14 to destroy.
```

Both ran at about 19:40 with exit code 0. `plan -destroy` only reads state and the API; no saved plan file was written, so nothing can be applied from it by accident.

## What will be removed

### Platform (`terraform/platform`, 34 resources)

| Area | Resources |
|------|-----------|
| Network | VPC `cm-vpc`, subnet `cm-gke-subnet`, Cloud Router `cm-router`, Cloud NAT `cm-nat`, firewall rules `cm-allow-health-checks` and `cm-allow-internal`, private services access range `cm-psa-range` and its peering |
| GKE | Cluster `cm-gke`, node pool `cm-pool` (and its VMs and disks), node service account `cm-gke-nodes` and its role |
| Cloud SQL | Instance `cm-pg` (with its backups), database `appdb`, user `app`, generated password |
| Secrets | Secret `cm-db-password` and its version |
| IAM | App service account `cm-app`, its Cloud SQL client binding (instance condition), secret accessor binding, Workload Identity binding |
| Registry | Artifact Registry `cm-app` (all images v1 to v6) and its reader binding |
| Ingress | Global static IP `cm-app-ip` (`8.232.93.111`) |
| Monitoring | Dashboard, 5 alert policies, uptime check, log based metric `cm-app-errors`, email notification channel |

### Bootstrap (`terraform/bootstrap`, 14 resources, optional)

| Resource | Effect on destroy |
|----------|-------------------|
| 13 `google_project_service` entries | Only removed from Terraform state. `disable_on_destroy = false`, so the APIs stay enabled and nothing else in the project breaks |
| State bucket `cloud-mile-assessment-tfstate` | Deleted, but only after it is emptied (it has `force_destroy = false` and versioning). The script does this with `--include-bootstrap` |

### Removed by GKE, not by Terraform

Deleting the Kubernetes app first makes GKE remove what it created for the Ingress: the external HTTPS load balancer (URL maps, target proxies, forwarding rules, backend service, health check), the NEGs, the `k8s-fw-l7-*` firewall rule and the Google managed certificate. Deleting the cluster removes the `gke-cm-gke-*` firewall rules.

### Outside Terraform

| Item | How it is removed |
|------|-------------------|
| Connectivity Test `lb-hc-to-app-pod` (Task 4) | `gcloud network-management connectivity-tests delete lb-hc-to-app-pod` (in the script) |
| Cloudflare DNS record `cm-app.sokay.my A 8.232.93.111` | **Manual, in Cloudflare.** After the static IP is released it could be given to another customer, so a record left pointing at it is a subdomain takeover risk |

## What stays

| Item | Why |
|------|-----|
| GCP project `cloud-mile-assessment` | Kept on purpose (sandbox rule: do not delete the project) |
| Enabled APIs | `disable_on_destroy = false` |
| Logs in the `_Default` log bucket | Kept until the bucket's 30 day retention |
| Cloud SQL name `cm-pg` | Reserved by Google for about a week after deletion, so a rebuild in that window needs a different name |
| Budget alert | Set up in the Billing console, not part of Terraform |
| Local files | `admin.auto.tfvars` (gitignored); with `--include-bootstrap`, the bootstrap state moves to a local `terraform.tfstate` (gitignored) |

## Destroy order and why

Running `terraform destroy` on its own would fail. The script [scripts/cleanup.sh](../scripts/cleanup.sh) handles the order:

| Step | Command | Why |
|------|---------|-----|
| 1 | `kubectl delete -f k8s/` and wait until no `k8s1-*` NEGs and no `k8s2-*` forwarding rules are left | Lets GKE delete the Ingress load balancer and NEGs cleanly. If the cluster is deleted first these can be left behind and block deleting the VPC |
| 2 | `gcloud network-management connectivity-tests delete lb-hc-to-app-pod` | Created by hand in Task 4 |
| 3 | `terraform -chdir=terraform/platform apply -var=deletion_protection=false` | GKE and Cloud SQL have deletion protection on. `destroy` cannot change it, so it has to be switched off with an apply first |
| 4 | `terraform -chdir=terraform/platform destroy -var=deletion_protection=false` | Removes the 34 platform resources |
| 4a | If step 4 fails on the VPC: `gcloud compute networks peerings delete servicenetworking-googleapis-com --network=cm-vpc`, then destroy again | The private services peering is set to `deletion_policy = "ABANDON"` because deleting it through the API commonly fails while Cloud SQL is still being cleaned up |
| 5 (optional) | Move bootstrap state to local, `gcloud storage rm --recursive --all-versions gs://cloud-mile-assessment-tfstate/**`, `terraform -chdir=terraform/bootstrap destroy` | The bootstrap state lives in the bucket it deletes, and the bucket must be empty (all versions) |
| 6 | List networks, firewall rules, addresses, SQL instances, clusters | Confirm nothing is left |

## Commands

```bash
# plan only (default), changes nothing
scripts/cleanup.sh

# after the live defense: app + platform, keep APIs and the state bucket
scripts/cleanup.sh --destroy

# everything including the state bucket
scripts/cleanup.sh --destroy --include-bootstrap
```

Safety in the script:
- With no flags it only runs the two `plan -destroy` commands.
- `--destroy` asks you to type the project ID before doing anything.
- The Terraform apply and destroy steps are interactive (no `-auto-approve`), so each shows its plan and waits for `yes`.
- Unknown options exit with code 2.

Manual equivalent of the core step:

```bash
cd terraform/platform
terraform apply   -var=deletion_protection=false
terraform destroy -var=deletion_protection=false
```

This is also exposed as the Terraform output `destroy_command`.

## Evidence index

| File | Content |
|------|---------|
| [01-plan-destroy-platform.txt](../evidence/task-6/01-plan-destroy-platform.txt) | `terraform plan -destroy` for the platform, 34 to destroy |
| [02-plan-destroy-bootstrap.txt](../evidence/task-6/02-plan-destroy-bootstrap.txt) | `terraform plan -destroy` for the bootstrap, 14 to destroy |
