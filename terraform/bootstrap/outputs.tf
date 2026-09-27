output "tfstate_bucket" {
  description = "GCS bucket for Terraform remote state."
  value       = google_storage_bucket.tfstate.name
}

output "enabled_services" {
  description = "APIs enabled by this configuration."
  value       = sort([for s in google_project_service.this : s.service])
}
