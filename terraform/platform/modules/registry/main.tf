# from task 1 - docker repo for the app image (used in task 2)
resource "google_artifact_registry_repository" "app" {
  repository_id = "${var.name_prefix}-app"
  location      = var.region
  format        = "DOCKER"
  description   = "Sample app images"

  # keep it small, only last 10 versions
  cleanup_policies {
    id     = "keep-last-10"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "2592000s"
    }
  }
}

# from task 1 - nodes can only pull from this repo, not project wide
resource "google_artifact_registry_repository_iam_member" "readers" {
  for_each = var.reader_members

  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.reader"
  member     = each.value
}
