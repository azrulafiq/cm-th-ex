# from task 2 - ingress module outputs

output "ip_name" {
  description = "Used in the ingress annotation kubernetes.io/ingress.global-static-ip-name."
  value       = google_compute_global_address.app.name
}

output "ip_address" {
  value = google_compute_global_address.app.address
}
