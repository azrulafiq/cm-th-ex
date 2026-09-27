# from task 2 - static global ip for the https ingress, dns a record points here
resource "google_compute_global_address" "app" {
  name         = "${var.name_prefix}-app-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}
