# from task 3 - monitoring module inputs

variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "alert_email" {
  type      = string
  sensitive = true
}

variable "app_domain" {
  type = string
}

variable "app_namespace" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "sql_instance_name" {
  type = string
}

variable "sql_max_connections" {
  description = "max_connections on the instance, db-f1-micro is 25 (SHOW max_connections)."
  type        = number
}
