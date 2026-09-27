locals {
  sql_database_id = "${var.project_id}:${var.sql_instance_name}"
  # 80% of max_connections (25 on db-f1-micro, checked with SHOW max_connections)
  sql_conn_threshold = floor(var.sql_max_connections * 0.8)

  app_container_filter = "resource.type=\"k8s_container\" AND resource.label.cluster_name=\"${var.cluster_name}\" AND resource.label.namespace_name=\"${var.app_namespace}\" AND resource.label.container_name=\"app\""
  # only the https url map (k8s2-um-*), not the http redirect map (k8s2-rm-*)
  lb_filter = "resource.type=\"https_lb_rule\" AND resource.label.url_map_name=monitoring.regex.full_match(\"k8s2-um-.*-${var.app_namespace}-app-.*\")"
}

# from task 3 - email channel for all alerts
resource "google_monitoring_notification_channel" "email" {
  display_name = "${var.name_prefix} alerts email"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

# from task 3 - log based metric, counts app logs with severity ERROR or worse
resource "google_logging_metric" "app_errors" {
  name        = "${var.name_prefix}-app-errors"
  description = "Application log entries with severity >= ERROR in the app namespace."
  # logging query language uses resource.labels (monitoring filters use resource.label)
  # from task 4 - gunicorn writes its own [INFO] lines (boot, shutdown) to stderr and gke marks stderr as ERROR,
  # so every pod start/stop counted ~9 fake errors. skip those, real [ERROR]/[CRITICAL] gunicorn lines still count
  filter = "resource.type=\"k8s_container\" AND resource.labels.cluster_name=\"${var.cluster_name}\" AND resource.labels.namespace_name=\"${var.app_namespace}\" AND resource.labels.container_name=\"app\" AND severity>=ERROR AND NOT textPayload:\"[INFO]\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key         = "path"
      value_type  = "STRING"
      description = "Request path from the app json log"
    }
  }

  label_extractors = {
    path = "EXTRACT(jsonPayload.path)"
  }
}

# from task 3 - uptime check on the public https endpoint
resource "google_monitoring_uptime_check_config" "app" {
  display_name = "${var.name_prefix} app https healthz"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path           = "/healthz"
    port           = 443
    use_ssl        = true
    validate_ssl   = true
    request_method = "GET"
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.app_domain
    }
  }

  content_matchers {
    content = "\"status\":\"ok\""
    matcher = "CONTAINS_STRING"
  }
}

# from task 3 - alert: pod restarts / crashloop
resource "google_monitoring_alert_policy" "pod_restarts" {
  display_name = "${var.name_prefix} app pod restarting (CrashLoopBackOff)"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "more than 2 container restarts in 5 min"
    condition_threshold {
      filter          = "metric.type=\"kubernetes.io/container/restart_count\" AND resource.type=\"k8s_container\" AND resource.label.cluster_name=\"${var.cluster_name}\" AND resource.label.namespace_name=\"${var.app_namespace}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 2
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.pod_name", "resource.label.container_name"]
      }
      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content = chomp(<<-EOT
      Container in namespace `${var.app_namespace}` restarted more than 2 times in 5 minutes. Usually CrashLoopBackOff.

      Check:
      - `kubectl -n ${var.app_namespace} get pods`
      - `kubectl -n ${var.app_namespace} describe pod <pod>` (Last State, Reason, Exit Code, OOMKilled)
      - `kubectl -n ${var.app_namespace} logs <pod> -c <container> --previous`
      - recent changes: `kubectl -n ${var.app_namespace} rollout history deploy/app`, configmap `app-config` (CRASH_ON_START)
    EOT
    )
  }
}

# from task 3 - alert: node cpu over 80% for 5 min
resource "google_monitoring_alert_policy" "node_cpu" {
  display_name = "${var.name_prefix} gke node cpu above 80% for 5 min"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "node cpu allocatable utilization > 0.8 for 5 min"
    condition_threshold {
      filter          = "metric.type=\"kubernetes.io/node/cpu/allocatable_utilization\" AND resource.type=\"k8s_node\" AND resource.label.cluster_name=\"${var.cluster_name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content = chomp(<<-EOT
      A GKE node in `${var.cluster_name}` has used more than 80% of its allocatable CPU for 5 minutes.

      Check:
      - `kubectl top nodes` and `kubectl top pods -A --sort-by=cpu`
      - `kubectl -n ${var.app_namespace} get hpa app` (is the HPA at max?)
      - node pool autoscaler max (3 nodes, limited by the E2 CPU quota)
    EOT
    )
  }
}

# from task 3 - alert: cloud sql connections over 80% of max_connections
resource "google_monitoring_alert_policy" "sql_connections" {
  display_name = "${var.name_prefix} cloud sql connections above 80%"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "num_backends > ${local.sql_conn_threshold} (80% of max_connections ${var.sql_max_connections})"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/postgresql/num_backends\" AND resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${local.sql_database_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = local.sql_conn_threshold
      duration        = "60s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.database_id"]
      }
      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content = chomp(<<-EOT
      Cloud SQL `${var.sql_instance_name}` has more than ${local.sql_conn_threshold} connections (80% of max_connections ${var.sql_max_connections}). New connections will soon be refused.

      Check:
      - `SELECT datname, usename, state, count(*) FROM pg_stat_activity GROUP BY 1,2,3;`
      - app pods holding connections (`kubectl -n ${var.app_namespace} logs deploy/app -c app | grep "holding db connections"`)
      - number of app replicas (`kubectl -n ${var.app_namespace} get hpa app`)
    EOT
    )
  }
}

# from task 3 - alert: uptime check failing
resource "google_monitoring_alert_policy" "uptime" {
  display_name = "${var.name_prefix} app uptime check failing"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "https://${var.app_domain}/healthz failing from more than 1 region"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.app.uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "60s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }
      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content = chomp(<<-EOT
      `https://${var.app_domain}/healthz` is failing from more than one checker region.

      Check:
      - `curl -v https://${var.app_domain}/healthz`
      - `kubectl -n ${var.app_namespace} get pods,ingress` and the LB backend health in the console
      - `kubectl -n ${var.app_namespace} describe ingress app`, managed certificate status, dns a record
    EOT
    )
  }
}

# from task 4 - alert on any manual firewall change (the task 4 outage was a firewall rule added outside terraform)
# gke's own service agent manages the k8s-fw-* / gke-* rules, leave those out
resource "google_monitoring_alert_policy" "firewall_change" {
  display_name = "${var.name_prefix} vpc firewall rule changed"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "firewall insert / patch / update / delete in audit log"
    condition_matched_log {
      filter = "logName=\"projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Factivity\" AND protoPayload.serviceName=\"compute.googleapis.com\" AND protoPayload.methodName=~\"compute\\.firewalls\\.(insert|patch|update|delete)\" AND NOT protoPayload.authenticationInfo.principalEmail=~\"container-engine-robot\""
      label_extractors = {
        rule   = "EXTRACT(protoPayload.resourceName)"
        method = "EXTRACT(protoPayload.methodName)"
        actor  = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    auto_close = "1800s"
  }

  documentation {
    mime_type = "text/markdown"
    content = chomp(<<-EOT
      A VPC firewall rule was created, changed or deleted outside GKE. Firewall rules for `cm-vpc` should only change through Terraform.

      Check:
      - `gcloud compute firewall-rules list --filter=network:cm-vpc --sort-by=priority`
      - is it in terraform? `terraform -chdir=terraform/platform state list | grep firewall`
      - is the app still reachable? `scripts/healthcheck.py`
      - a deny on 35.191.0.0/16 or 130.211.0.0/22 cuts off the load balancer (task 4 incident)
    EOT
    )
  }
}

# from task 3 - ops dashboard
# targetAxis set and zero x/y positions left out on purpose, the api adds/drops them and plan shows a diff otherwise
resource "google_monitoring_dashboard" "ops" {
  dashboard_json = jsonencode({
    displayName = "${var.name_prefix} ops dashboard"
    mosaicLayout = {
      columns = 48
      tiles = [
        {
          width = 24, height = 16
          widget = {
            title = "GKE node CPU (allocatable utilization)"
            xyChart = {
              dataSets = [{
                plotType   = "LINE"
                targetAxis = "Y1"
                timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"kubernetes.io/node/cpu/allocatable_utilization\" AND resource.type=\"k8s_node\" AND resource.label.cluster_name=\"${var.cluster_name}\""
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_MEAN", crossSeriesReducer = "REDUCE_MEAN", groupByFields = ["resource.label.node_name"] }
                } }
              }]
              thresholds = [{ value = 0.8, label = "alert 80%" }]
              yAxis      = { scale = "LINEAR" }
            }
          }
        },
        {
          xPos = 24, width = 24, height = 16
          widget = {
            title = "GKE node memory (allocatable utilization)"
            xyChart = {
              dataSets = [{
                plotType   = "LINE"
                targetAxis = "Y1"
                timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"kubernetes.io/node/memory/allocatable_utilization\" AND resource.type=\"k8s_node\" AND resource.label.cluster_name=\"${var.cluster_name}\""
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_MEAN", crossSeriesReducer = "REDUCE_SUM", groupByFields = ["resource.label.node_name"] }
                } }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        },
        {
          yPos = 16, width = 24, height = 16
          widget = {
            title = "App container CPU (cores) per pod"
            xyChart = {
              dataSets = [{
                plotType   = "LINE"
                targetAxis = "Y1"
                timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"kubernetes.io/container/cpu/core_usage_time\" AND ${local.app_container_filter}"
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE", crossSeriesReducer = "REDUCE_SUM", groupByFields = ["resource.label.pod_name"] }
                } }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        },
        {
          xPos = 24, yPos = 16, width = 24, height = 16
          widget = {
            title = "App container memory used per pod"
            xyChart = {
              dataSets = [{
                plotType   = "LINE"
                targetAxis = "Y1"
                timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"kubernetes.io/container/memory/used_bytes\" AND ${local.app_container_filter}"
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_MEAN", crossSeriesReducer = "REDUCE_SUM", groupByFields = ["resource.label.pod_name"] }
                } }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        },
        {
          yPos = 32, width = 24, height = 16
          widget = {
            title = "Pod restarts (per minute)"
            xyChart = {
              dataSets = [{
                plotType   = "STACKED_BAR"
                targetAxis = "Y1"
                timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"kubernetes.io/container/restart_count\" AND resource.type=\"k8s_container\" AND resource.label.cluster_name=\"${var.cluster_name}\" AND resource.label.namespace_name=\"${var.app_namespace}\""
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_DELTA", crossSeriesReducer = "REDUCE_SUM", groupByFields = ["resource.label.pod_name", "resource.label.container_name"] }
                } }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        },
        {
          xPos = 24, yPos = 32, width = 24, height = 16
          widget = {
            title = "Cloud SQL connections (num_backends)"
            xyChart = {
              dataSets = [{
                plotType   = "LINE"
                targetAxis = "Y1"
                timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"cloudsql.googleapis.com/database/postgresql/num_backends\" AND resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${local.sql_database_id}\""
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_MEAN", crossSeriesReducer = "REDUCE_SUM", groupByFields = ["metric.label.database"] }
                } }
              }]
              thresholds = [{ value = local.sql_conn_threshold, label = "alert 80%" }]
              yAxis      = { scale = "LINEAR" }
            }
          }
        },
        {
          yPos = 48, width = 24, height = 16
          widget = {
            title = "LB latency p50 / p95 / p99 (ms)"
            xyChart = {
              dataSets = [for p in ["50", "95", "99"] : {
                plotType       = "LINE"
                targetAxis     = "Y1"
                legendTemplate = "p${p}"
                timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"loadbalancing.googleapis.com/https/total_latencies\" AND ${local.lb_filter}"
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_DELTA", crossSeriesReducer = "REDUCE_PERCENTILE_${p}" }
                } }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        },
        {
          xPos = 24, yPos = 48, width = 24, height = 16
          widget = {
            title = "LB requests per second by response class"
            xyChart = {
              dataSets = [{
                plotType   = "STACKED_AREA"
                targetAxis = "Y1"
                timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" AND ${local.lb_filter}"
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE", crossSeriesReducer = "REDUCE_SUM", groupByFields = ["metric.label.response_code_class"] }
                } }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        },
        {
          yPos = 64, width = 24, height = 16
          widget = {
            title = "Error rate (5xx / all requests)"
            xyChart = {
              dataSets = [{
                plotType   = "LINE"
                targetAxis = "Y1"
                timeSeriesQuery = { timeSeriesFilterRatio = {
                  numerator = {
                    filter      = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" AND ${local.lb_filter} AND metric.label.response_code_class=500"
                    aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE", crossSeriesReducer = "REDUCE_SUM" }
                  }
                  denominator = {
                    filter      = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" AND ${local.lb_filter}"
                    aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE", crossSeriesReducer = "REDUCE_SUM" }
                  }
                } }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        },
        {
          xPos = 24, yPos = 64, width = 24, height = 16
          widget = {
            title = "App error logs per minute (log based metric)"
            xyChart = {
              dataSets = [{
                plotType   = "STACKED_BAR"
                targetAxis = "Y1"
                timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.app_errors.name}\" AND resource.type=\"k8s_container\""
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_DELTA", crossSeriesReducer = "REDUCE_SUM", groupByFields = ["metric.label.path"] }
                } }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        },
        {
          yPos = 80, width = 48, height = 12
          widget = {
            title = "Uptime check pass ratio by region"
            xyChart = {
              dataSets = [{
                plotType   = "LINE"
                targetAxis = "Y1"
                timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.app.uptime_check_id}\""
                  aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_FRACTION_TRUE", crossSeriesReducer = "REDUCE_MEAN", groupByFields = ["metric.label.checker_location"] }
                } }
              }]
              yAxis = { scale = "LINEAR" }
            }
          }
        },
      ]
    }
  })
}
