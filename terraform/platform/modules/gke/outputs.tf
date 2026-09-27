# from task 1 - gke module outputs

output "cluster_name" {
  value = google_container_cluster.this.name
}

output "cluster_location" {
  value = google_container_cluster.this.location
}

output "cluster_endpoint" {
  value     = google_container_cluster.this.endpoint
  sensitive = true
}

output "workload_pool" {
  value = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_pool_name" {
  value = google_container_node_pool.primary.name
}

output "node_service_account" {
  value = google_service_account.nodes.email
}
