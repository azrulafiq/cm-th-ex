# from task 1 - app db password, goes to secret manager (note: also ends up in tf state)
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "-_"
}

# from task 1 - postgres with private ip only, no public ip
resource "google_sql_database_instance" "this" {
  name             = "${var.name_prefix}-pg"
  region           = var.region
  database_version = var.db_version

  deletion_protection = var.deletion_protection

  settings {
    # pg16 defaults to enterprise plus, shared core tiers need enterprise
    edition           = "ENTERPRISE"
    tier              = var.tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = true

    deletion_protection_enabled = var.deletion_protection

    location_preference {
      zone = var.zone
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled    = true
      start_time = "18:00" # 2am myt
      backup_retention_settings {
        retained_backups = 7
      }
    }

    # sun 3am myt = sat 19:00 utc
    maintenance_window {
      day  = 6
      hour = 19
    }

    insights_config {
      query_insights_enabled = true
    }
  }
}

# from task 1 - app database
resource "google_sql_database" "app" {
  name     = var.db_name
  instance = google_sql_database_instance.this.name
}

# from task 1 - app db user
resource "google_sql_user" "app" {
  name     = var.db_user
  instance = google_sql_database_instance.this.name
  password = random_password.db.result
}
