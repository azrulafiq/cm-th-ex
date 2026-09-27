# cm-th-ex
Cloudmile Take-home Exercise: GCP Cloud Operations hands-on homework.

## Documentation

| Doc | Content |
|-----|---------|
| [00-prerequisites.md](docs/00-prerequisites.md) | Workstation, credentials, region, budget, quotas, API bootstrap, remote state bucket |
| [01-task-1-infrastructure.md](docs/01-task-1-infrastructure.md) | Task 1: Terraform platform (VPC, NAT, firewall, private GKE, Cloud SQL, Secret Manager, IAM), architecture diagram |

## Repository layout

```
terraform/bootstrap/   APIs and Terraform state bucket
terraform/platform/    Task 1 platform (modules: network, gke, cloudsql, secrets, iam, registry)
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
```
