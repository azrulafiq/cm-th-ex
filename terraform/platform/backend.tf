# from task 1 - remote state in gcs, separate prefix from bootstrap
terraform {
  backend "gcs" {
    bucket = "cloud-mile-assessment-tfstate"
    prefix = "platform"
  }
}
