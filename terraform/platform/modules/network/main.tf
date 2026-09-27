# from task 1 - custom vpc, no auto subnets
resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# from task 1 - subnet for gke nodes, secondary ranges for pods and services
resource "google_compute_subnetwork" "gke" {
  name          = "${var.name_prefix}-gke-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  # private nodes still need to reach google apis (artifact registry, logging etc)
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# from task 1 - cloud router for nat
resource "google_compute_router" "router" {
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# from task 1 - cloud nat so private nodes can go out to internet
resource "google_compute_router_nat" "nat" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# from task 1 - allow google lb and health check ranges to reach nodes/pods
resource "google_compute_firewall" "allow_health_checks" {
  name      = "${var.name_prefix}-allow-health-checks"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  # from task 4 - was 1000, a manual deny at priority 100 cut off the lb (502 for ~10 min)
  # 0 = highest, lowest number wins so only a deny also at 0 can override this now
  priority = 0

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = [var.node_tag]

  allow {
    protocol = "tcp"
  }
}

# from task 1 - allow internal traffic between nodes, pods and services
resource "google_compute_firewall" "allow_internal" {
  name      = "${var.name_prefix}-allow-internal"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
}

# from task 1 - reserved range for private services access (cloud sql private ip)
resource "google_compute_global_address" "psa_range" {
  name          = "${var.name_prefix}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.psa_prefix_length
  network       = google_compute_network.vpc.id
}

# from task 1 - peering to google managed services for cloud sql
resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]

  # removing this peering usually fails on destroy while cloud sql is still being cleaned up
  deletion_policy = "ABANDON"
}
