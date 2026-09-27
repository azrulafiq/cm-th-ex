# from task 1 - secrets module outputs

output "db_password_secret_id" {
  description = "Full resource id, used for iam binding."
  value       = google_secret_manager_secret.db_password.id
}

output "db_password_secret_name" {
  description = "Short secret name."
  value       = google_secret_manager_secret.db_password.secret_id
}
