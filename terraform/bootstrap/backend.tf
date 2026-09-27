# from task 1 - bootstrap state in gcs, added after bucket was created then ran init -migrate-state
terraform {
  backend "gcs" {
    bucket = "cloud-mile-assessment-tfstate"
    prefix = "bootstrap"
  }
}
