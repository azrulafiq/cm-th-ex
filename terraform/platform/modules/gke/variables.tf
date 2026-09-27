# from task 1 - gke module inputs

variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "zone" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnet_name" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "machine_type" {
  type = string
}

variable "node_min_count" {
  type = number
}

variable "node_max_count" {
  type = number
}

variable "disk_size_gb" {
  type = number
}

variable "node_tag" {
  type = string
}

variable "deletion_protection" {
  type = bool
}
