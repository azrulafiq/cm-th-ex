# from task 1 - registry module inputs

variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "reader_members" {
  description = "Members that can pull images, eg { gke-nodes = \"serviceAccount:...\" }. Map so keys are known at plan time."
  type        = map(string)
}
