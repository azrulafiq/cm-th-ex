# from task 1 - iam module outputs

output "app_service_account" {
  value = google_service_account.app.email
}

output "app_ksa_member" {
  value = google_service_account_iam_member.app_wi.member
}
