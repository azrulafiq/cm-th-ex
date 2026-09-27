# from task 1 - iam module inputs

variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "db_password_secret_id" {
  type = string
}

variable "sql_instance_name" {
  type = string
}

variable "workload_pool" {
  description = "From the gke module, so the binding waits until the pool exists."
  type        = string
}

variable "app_namespace" {
  type = string
}

variable "app_ksa_name" {
  type = string
}
