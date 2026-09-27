# from task 1 - secret for the db password, kept in our region only
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.name_prefix}-db-password"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  labels = {
    app = "sample-app"
  }
}

# from task 1 - current password version
resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}
