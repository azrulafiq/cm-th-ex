# from task 1 - app sa, pods use this through workload identity
resource "google_service_account" "app" {
  account_id   = "${var.name_prefix}-app"
  display_name = "Sample app workload service account"
}

# from task 1 - app can read only the db password secret, nothing else
resource "google_secret_manager_secret_iam_member" "app_db_password" {
  secret_id = var.db_password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}

# from task 1 - cloud sql client for the auth proxy, limited to our instance only
resource "google_project_iam_member" "app_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.app.email}"

  condition {
    title      = "only-${var.sql_instance_name}"
    expression = "resource.name == \"projects/${var.project_id}/instances/${var.sql_instance_name}\" && resource.type == \"sqladmin.googleapis.com/Instance\""
  }
}

# from task 1 - workload identity, lets the k8s sa act as the app gsa
resource "google_service_account_iam_member" "app_wi" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.workload_pool}[${var.app_namespace}/${var.app_ksa_name}]"
}
