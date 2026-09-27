# from task 1 - network module inputs

variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "pods_cidr" {
  type = string
}

variable "services_cidr" {
  type = string
}

variable "psa_prefix_length" {
  type = number
}

variable "node_tag" {
  description = "Network tag on GKE nodes, used as firewall target."
  type        = string
}
