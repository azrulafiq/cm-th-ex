# One-time bootstrap: enables project APIs and creates the GCS bucket that
# holds remote state for this and the main Terraform configuration.

resource "google_project_service" "this" {
  for_each = var.services

  service = each.value

  # Keep APIs enabled if this config is ever destroyed, so other
  # configurations in the project are not broken.
  disable_on_destroy = false
}

resource "google_storage_bucket" "tfstate" {
  name     = "${var.project_id}-tfstate"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  # Keep the last 10 noncurrent state versions for recovery.
  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.this]
}
