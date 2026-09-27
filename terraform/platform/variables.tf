# from task 1 - platform inputs

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the subnet, NAT, Cloud SQL and registry."
  type        = string
  default     = "asia-southeast1"
}

variable "zone" {
  description = "Zone for the GKE cluster and Cloud SQL instance."
  type        = string
  default     = "asia-southeast1-a"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "cm"
}

# network

variable "subnet_cidr" {
  description = "Primary range for the subnet (GKE nodes)."
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary range for GKE pods."
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range for GKE services."
  type        = string
  default     = "10.30.0.0/20"
}

variable "psa_prefix_length" {
  description = "Prefix length of the range reserved for private services access (Cloud SQL)."
  type        = number
  default     = 20
}

# gke

variable "authorized_networks" {
  description = "CIDRs allowed to reach the GKE control plane. Set in a gitignored *.auto.tfvars file."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

# from task 1 - was e2-medium, only 940m cpu allocatable and gke system pods took 82-100% of it
variable "node_machine_type" {
  description = "Machine type for GKE nodes."
  type        = string
  default     = "e2-standard-2"
}

variable "node_min_count" {
  description = "Min nodes for the autoscaler."
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Max nodes for the autoscaler. 3 x e2-standard-2 plus 1 surge node fits the 8 E2 vCPU trial quota."
  type        = number
  default     = 3
}

variable "node_disk_size_gb" {
  description = "Boot disk size per node."
  type        = number
  default     = 50
}

# cloud sql

variable "db_tier" {
  description = "Cloud SQL machine tier."
  type        = string
  default     = "db-f1-micro"
}

variable "db_version" {
  description = "Cloud SQL database version."
  type        = string
  default     = "POSTGRES_16"
}

variable "db_name" {
  description = "Application database name."
  type        = string
  default     = "appdb"
}

variable "db_user" {
  description = "Application database user."
  type        = string
  default     = "app"
}

# app workload identity

variable "app_namespace" {
  description = "Kubernetes namespace of the application."
  type        = string
  default     = "app"
}

variable "app_ksa_name" {
  description = "Kubernetes service account the application pods run as."
  type        = string
  default     = "app-ksa"
}

# safety

variable "deletion_protection" {
  description = "Block terraform destroy on GKE and Cloud SQL. Set false only right before cleanup."
  type        = bool
  default     = true
}

# from task 2 - app domain for the managed cert
variable "app_domain" {
  description = "Public hostname for the app, A record must point to the ingress ip."
  type        = string
  default     = "cm-app.sokay.my"
}

# from task 3 - alerting inputs

variable "alert_email" {
  description = "Email for alert notifications. Set in the gitignored admin.auto.tfvars."
  type        = string
  sensitive   = true
}

variable "sql_max_connections" {
  description = "max_connections on the Cloud SQL tier, used for the 80% alert (db-f1-micro = 25)."
  type        = number
  default     = 25
}
