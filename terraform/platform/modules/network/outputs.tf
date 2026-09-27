# from task 1 - network module outputs

output "network_id" {
  value = google_compute_network.vpc.id
}

output "network_name" {
  value = google_compute_network.vpc.name
}

output "subnet_name" {
  value = google_compute_subnetwork.gke.name
}

output "pods_range_name" {
  value = google_compute_subnetwork.gke.secondary_ip_range[0].range_name
}

output "services_range_name" {
  value = google_compute_subnetwork.gke.secondary_ip_range[1].range_name
}

output "router_name" {
  value = google_compute_router.router.name
}

output "nat_name" {
  value = google_compute_router_nat.nat.name
}

output "psa_connection" {
  description = "Used by cloud sql as a dependency so private ip is ready first."
  value       = google_service_networking_connection.psa.id
}
