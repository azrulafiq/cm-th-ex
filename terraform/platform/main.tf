# from task 1 - shared values
locals {
  node_tag = "${var.name_prefix}-gke-node"
}

# from task 1 - vpc, subnet, router, nat, firewall, private services access
module "network" {
  source = "./modules/network"

  name_prefix       = var.name_prefix
  region            = var.region
  subnet_cidr       = var.subnet_cidr
  pods_cidr         = var.pods_cidr
  services_cidr     = var.services_cidr
  psa_prefix_length = var.psa_prefix_length
  node_tag          = local.node_tag
}

# from task 1 - private gke cluster, node pool, node sa
module "gke" {
  source = "./modules/gke"

  project_id          = var.project_id
  name_prefix         = var.name_prefix
  zone                = var.zone
  network_id          = module.network.network_id
  subnet_name         = module.network.subnet_name
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  authorized_networks = var.authorized_networks
  machine_type        = var.node_machine_type
  node_min_count      = var.node_min_count
  node_max_count      = var.node_max_count
  disk_size_gb        = var.node_disk_size_gb
  node_tag            = local.node_tag
  deletion_protection = var.deletion_protection
}

# from task 1 - cloud sql postgres, private ip
module "cloudsql" {
  source = "./modules/cloudsql"

  name_prefix         = var.name_prefix
  region              = var.region
  zone                = var.zone
  network_id          = module.network.network_id
  tier                = var.db_tier
  db_version          = var.db_version
  db_name             = var.db_name
  db_user             = var.db_user
  deletion_protection = var.deletion_protection

  # private ip needs the psa peering up first
  depends_on = [module.network]
}

# from task 1 - db password in secret manager
module "secrets" {
  source = "./modules/secrets"

  name_prefix = var.name_prefix
  region      = var.region
  db_password = module.cloudsql.db_password
}

# from task 1 - least privilege app sa + workload identity binding
module "iam" {
  source = "./modules/iam"

  project_id            = var.project_id
  name_prefix           = var.name_prefix
  db_password_secret_id = module.secrets.db_password_secret_id
  sql_instance_name     = module.cloudsql.instance_name
  workload_pool         = module.gke.workload_pool
  app_namespace         = var.app_namespace
  app_ksa_name          = var.app_ksa_name
}

# from task 1 - artifact registry for the app image
module "registry" {
  source = "./modules/registry"

  name_prefix = var.name_prefix
  region      = var.region
  reader_members = {
    gke-nodes = "serviceAccount:${module.gke.node_service_account}"
  }
}
