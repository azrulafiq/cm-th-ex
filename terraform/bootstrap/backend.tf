# Added after the first apply created the bucket. State was then moved here
# with: terraform init -migrate-state
terraform {
  backend "gcs" {
    bucket = "cloud-mile-assessment-tfstate"
    prefix = "bootstrap"
  }
}
