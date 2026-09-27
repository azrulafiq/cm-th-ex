# from task 1 - bootstrap inputs

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Default region, also used as the state bucket location."
  type        = string
  default     = "asia-southeast1"
}

variable "services" {
  description = "APIs required by the platform."
  type        = set(string)
  default = [
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
}
