# from task 3 - monitoring module outputs

output "notification_channel" {
  value = google_monitoring_notification_channel.email.id
}

output "log_metric" {
  value = google_logging_metric.app_errors.name
}

output "uptime_check_id" {
  value = google_monitoring_uptime_check_config.app.uptime_check_id
}

output "alert_policies" {
  value = {
    pod_restarts    = google_monitoring_alert_policy.pod_restarts.name
    node_cpu        = google_monitoring_alert_policy.node_cpu.name
    sql_connections = google_monitoring_alert_policy.sql_connections.name
    uptime          = google_monitoring_alert_policy.uptime.name
    firewall_change = google_monitoring_alert_policy.firewall_change.name
  }
}

output "dashboard_id" {
  value = google_monitoring_dashboard.ops.id
}
