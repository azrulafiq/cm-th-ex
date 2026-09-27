# from task 1 - dedicated node sa, not the default compute sa (that one has editor)
resource "google_service_account" "nodes" {
  account_id   = "${var.name_prefix}-gke-nodes"
  display_name = "GKE node pool service account"
}

# from task 1 - google's minimal role for gke nodes (logging, monitoring, metadata)
resource "google_project_iam_member" "nodes_default" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# from task 1 - private gke cluster, zonal so it fits the free tier mgmt fee
resource "google_container_cluster" "this" {
  name     = "${var.name_prefix}-gke"
  location = var.zone

  network    = var.network_id
  subnetwork = var.subnet_name

  # manage nodes in our own node pool below
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # nodes get no public ip, control plane keeps public endpoint but locked to authorized networks
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  # dataplane v2, gives network policy support
  datapath_provider = "ADVANCED_DATAPATH"

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  # secret manager csi add-on, used in task 2 to mount the db secret
  secret_manager_config {
    enabled = true
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  # kube state metrics (pod, deployment, hpa) for the task 3 alerts
  # order must match what the api returns or plan shows a diff every time
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "HPA", "POD", "DEPLOYMENT"]
    managed_prometheus {
      enabled = true
    }
  }

  # only for the temp default pool, so it doesnt use the default compute sa
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    disk_type       = "pd-balanced"
    disk_size_gb    = var.disk_size_gb
  }

  lifecycle {
    # default pool gets removed right after create, ignore its config
    ignore_changes = [node_config]
  }
}

# from task 1 - main node pool with autoscaling
resource "google_container_node_pool" "primary" {
  name     = "${var.name_prefix}-pool"
  cluster  = google_container_cluster.this.id
  location = var.zone

  initial_node_count = var.node_min_count

  autoscaling {
    min_node_count = var.node_min_count
    max_node_count = var.node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # 1 extra node during upgrade, no node taken down first
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.machine_type
    disk_type    = "pd-balanced"
    disk_size_gb = var.disk_size_gb
    image_type   = "COS_CONTAINERD"

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    tags = [var.node_tag]

    labels = {
      pool = "primary"
    }

    # pods use workload identity, not the node sa
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  lifecycle {
    # autoscaler changes the count, dont fight it
    ignore_changes = [initial_node_count]
  }
}
