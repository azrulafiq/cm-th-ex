# from task 1 - platform outputs, used in task 2 manifests

output "network_name" {
  value = module.network.network_name
}

output "subnet_name" {
  value = module.network.subnet_name
}

output "nat_name" {
  value = module.network.nat_name
}

output "router_name" {
  value = module.network.router_name
}

output "gke_cluster_name" {
  value = module.gke.cluster_name
}

output "gke_cluster_location" {
  value = module.gke.cluster_location
}

output "gke_node_pool" {
  value = module.gke.node_pool_name
}

output "gke_node_service_account" {
  value = module.gke.node_service_account
}

output "gke_get_credentials" {
  description = "Run this to point kubectl at the cluster."
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --zone ${module.gke.cluster_location} --project ${var.project_id}"
}

output "sql_instance_name" {
  value = module.cloudsql.instance_name
}

output "sql_connection_name" {
  description = "For the cloud sql auth proxy."
  value       = module.cloudsql.connection_name
}

output "sql_private_ip" {
  value = module.cloudsql.private_ip
}

output "db_name" {
  value = module.cloudsql.db_name
}

output "db_user" {
  value = module.cloudsql.db_user
}

output "db_password_secret" {
  value = module.secrets.db_password_secret_name
}

output "app_service_account" {
  value = module.iam.app_service_account
}

output "app_ksa" {
  description = "k8s sa that must exist in task 2 with the iam.gke.io/gcp-service-account annotation."
  value       = "${var.app_namespace}/${var.app_ksa_name}"
}

output "artifact_registry_url" {
  value = module.registry.repository_url
}

output "destroy_command" {
  description = "Do not run before the live defense. Set deletion_protection = false and apply first."
  value       = "terraform apply -var=deletion_protection=false && terraform destroy -var=deletion_protection=false"
}

# from task 2 - ingress outputs

output "app_ip_name" {
  value = module.ingress.ip_name
}

output "app_ip_address" {
  description = "Create an A record for app_domain pointing to this."
  value       = module.ingress.ip_address
}

output "app_domain" {
  value = var.app_domain
}

# from task 3 - monitoring outputs

output "monitoring_log_metric" {
  value = module.monitoring.log_metric
}

output "monitoring_uptime_check_id" {
  value = module.monitoring.uptime_check_id
}

output "monitoring_alert_policies" {
  value = module.monitoring.alert_policies
}

output "monitoring_dashboard_id" {
  value = module.monitoring.dashboard_id
}
