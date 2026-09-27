# from task 1 - turn on the apis the platform needs
resource "google_project_service" "this" {
  for_each = var.services

  service = each.value

  # keep apis on even if this gets destroyed
  disable_on_destroy = false
}

# from task 1 - gcs bucket for remote state
resource "google_storage_bucket" "tfstate" {
  name     = "${var.project_id}-tfstate"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  # only keep last 10 old state versions
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
