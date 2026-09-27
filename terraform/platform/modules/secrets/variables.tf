# from task 1 - secrets module inputs

variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}
