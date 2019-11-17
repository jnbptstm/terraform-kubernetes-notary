resource "kubernetes_persistent_volume_claim" "notary_data" {
  for_each = var.deploy_persistence == true ? {create: true} : {}
  metadata {
    name = "notary-data"
    namespace = var.namespace
  }
  spec {
    storage_class_name = var.storage_class_name
    access_modes = [
      "ReadWriteOnce"
    ]
    resources {
      requests = {
        storage = var.storage_size
      }
    }
  }
  wait_until_bound = false
}

resource "kubernetes_deployment" "notary_db" {
  for_each = var.deploy_persistence == true ? {create: true} : {}
  metadata {
    name = "notary-db"
    namespace = var.namespace
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "notary"
        component = "notary-db"
      }
    }
    strategy {
      type = "Recreate"
    }
    template {
      metadata {
        labels = {
          app = "notary"
          component = "notary-db"
        }
      }
      spec {
        init_container {
          command = [
            "/gomplate",
            "--left-delim",
            "%%",
            "--right-delim",
            "%%",
            "--input-dir",
            "/sql-init-templates",
            "--output-dir",
            "/docker-entrypoint-initdb.d",
          ]
          image = "hairyhenderson/gomplate:v3"
          name = "gomplate"
          env {
            name = "SERVERPASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.server_password.metadata.0.name
                key = "password"
              }
            }
          }
          env {
            name = "SIGNERPASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.signer_password.metadata.0.name
                key = "password"
              }
            }
          }
          volume_mount {
            mount_path = "/docker-entrypoint-initdb.d"
            name = "sql-init"
          }
          volume_mount {
            mount_path = "/sql-init-templates"
            name = "notarysql"
          }
        }
        container {
          args = [
            "mysqld",
            "--innodb_file_per_table",
          ]
          env {
            name = "MYSQL_RANDOM_ROOT_PASSWORD"
            value = "yes"
          }
          image = var.storage_image
          name = "storage"
          port {
            container_port = 3306
            name = "mysql"
          }
          volume_mount {
            mount_path = "/var/lib/mysql"
            name = "notary-data"
          }
          volume_mount {
            mount_path = "/docker-entrypoint-initdb.d"
            name = "sql-init"
          }
          volume_mount {
            mount_path = "/sql-init-templates"
            name = "notarysql"
          }
        }
        volume {
          name = "notary-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.notary_data[each.key].metadata.0.name
          }
        }
        volume {
          name = "notarysql"
          config_map {
            name = "notarysql"
          }
        }
        volume {
          name = "sql-init"
          empty_dir {
            medium = ""
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "notary_db" {
  for_each = var.deploy_persistence == true ? {create: true} : {}
  metadata {
    name = "notary-db"
    namespace = var.namespace
  }
  spec {
    port {
      name = "mysql"
      port = 3306
      target_port = 3306
    }
    selector = {
      app = "notary"
      component = "notary-db"
    }
  }
}

resource "tls_private_key" "ca" {
  algorithm = "ECDSA"
}

resource "tls_self_signed_cert" "ca" {
  key_algorithm = tls_private_key.ca.algorithm
  private_key_pem = tls_private_key.ca.private_key_pem
  subject {
    common_name = "Notary Root CA"
  }
  validity_period_hours = var.cert_validity_period_hours
  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature",
  ]
  is_ca_certificate = true
}

resource "tls_private_key" "server" {
  algorithm = "ECDSA"
}

resource "tls_cert_request" "server" {
  key_algorithm = tls_private_key.server.algorithm
  private_key_pem = tls_private_key.server.private_key_pem
  subject {
    common_name = "notary-server"
  }
  dns_names = ["notary-server"]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem = tls_cert_request.server.cert_request_pem
  ca_key_algorithm = tls_private_key.ca.algorithm
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = var.cert_validity_period_hours
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
  ]
  is_ca_certificate = false
}

resource "tls_private_key" "signer" {
  algorithm = "ECDSA"
}

resource "tls_cert_request" "signer" {
  key_algorithm = tls_private_key.signer.algorithm
  private_key_pem = tls_private_key.signer.private_key_pem
  subject {
    common_name = "notary-signer"
  }
  dns_names = ["notary-signer"]
}

resource "tls_locally_signed_cert" "signer" {
  cert_request_pem = tls_cert_request.signer.cert_request_pem
  ca_key_algorithm = tls_private_key.ca.algorithm
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = var.cert_validity_period_hours
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
  ]
  is_ca_certificate = false
}

resource "kubernetes_deployment" "notary_server" {
  depends_on = ["kubernetes_job.notary_server_migrate"]
  metadata {
    name = "notary-server"
    namespace = var.namespace
  }
  spec {
    replicas = var.server_replicas
    selector {
      match_labels = {
        app = "notary"
        component = "notary-server"
      }
    }
    strategy {
      rolling_update {
        max_unavailable = 0
      }
    }
    template {
      metadata {
        labels = {
          app = "notary"
          component = "notary-server"
        }
      }
      spec {
        init_container {
          command = [
            "/gomplate",
            "--left-delim",
            "%%",
            "--right-delim",
            "%%",
            "--input-dir",
            "/config-template",
            "--output-dir",
            "/config",
          ]
          image = "hairyhenderson/gomplate:v3"
          name = "gomplate"
          env {
            name = "PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.server_password.metadata.0.name
                key = "password"
              }
            }
          }
          volume_mount {
            mount_path = "/config"
            name = "config-rendered"
          }
          volume_mount {
            mount_path = "/config-template"
            name = "config-template"
          }
        }
        container {
          command = [
            "notary-server",
            "-config=/config/server-config.json",
          ]
          image = "notary:${var.server_image_version}"
          name = "server"
          port {
            container_port = var.server_port
            name = "https"
          }
          volume_mount {
            mount_path = "/config"
            name = "config-rendered"
          }
          volume_mount {
            mount_path = "/tls"
            name = "tls"
          }
        }
        volume {
          name = "config-template"
          config_map {
            name = kubernetes_config_map.notary_config.metadata.0.name
          }
        }
        volume {
          name = "tls"
          secret {
            secret_name = kubernetes_secret.notary_tls.metadata.0.name
          }
        }
        volume {
          name = "config-rendered"
          empty_dir {
            medium = ""
          }
        }
      }
    }
  }
}

resource "kubernetes_job" "notary_server_migrate" {
  metadata {
    name = "notary-server-migrate"
    namespace = var.namespace
  }
  spec {
    completions = 1
    parallelism = 1
    backoff_limit = 100
    template {
      metadata {
        labels = {
          app = "notary"
          component = "notary-server-migrate"
        }
      }
      spec {
        init_container {
          command = [
            "/gomplate",
            "--left-delim",
            "%%",
            "--right-delim",
            "%%",
            "--in",
            var.server_storage_db_url,
            "--out",
            "/migrate-configuration/db-url",
          ]
          image = "hairyhenderson/gomplate:v3"
          name = "gomplate"
          env {
            name = "PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.server_password.metadata.0.name
                key = "password"
              }
            }
          }
          volume_mount {
            mount_path = "/migrate-configuration"
            name = "migrate-configuration"
          }
        }
        container {
          command = [
            "sh",
            "-c",
            "/migrate -path=/migrations/server/${var.storage_flavor} -database=${var.storage_flavor}://$(cat /migrate-configuration/db-url) up"
          ]
          image = "migrate/migrate:${var.migrate_version}"
          name = "migrate"
          volume_mount {
            mount_path = "/migrations/server/${var.storage_flavor}"
            name = "migrations-server"
          }
          volume_mount {
            mount_path = "/tls"
            name = "tls"
          }
          volume_mount {
            mount_path = "/migrate-configuration"
            name = "migrate-configuration"
          }
        }
        restart_policy = "OnFailure"
        volume {
          name = "migrations-server"
          config_map {
            name = kubernetes_config_map.notary_migrations_server.metadata.0.name
          }
        }
        volume {
          name = "tls"
          secret {
            secret_name = kubernetes_secret.notary_tls.metadata.0.name
          }
        }
        volume {
          name = "migrate-configuration"
          empty_dir {
            medium = ""
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "notary_signer" {
  depends_on = ["kubernetes_job.notary_signer_migrate"]
  metadata {
    name = "notary-signer"
    namespace = var.namespace
  }
  spec {
    replicas = var.signer_replicas
    selector {
      match_labels = {
        app = "notary"
        component = "notary-signer"
      }
    }
    strategy {
      rolling_update {
        max_unavailable = 0
      }
    }
    template {
      metadata {
        labels = {
          app = "notary"
          component = "notary-signer"
        }
      }
      spec {
        init_container {
          command = [
            "/gomplate",
            "--left-delim",
            "%%",
            "--right-delim",
            "%%",
            "--input-dir",
            "/config-template",
            "--output-dir",
            "/config",
          ]
          image = "hairyhenderson/gomplate:v3"
          name = "gomplate"
          env {
            name = "PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.signer_password.metadata.0.name
                key = "password"
              }
            }
          }
          volume_mount {
            mount_path = "/config"
            name = "config-rendered"
          }
          volume_mount {
            mount_path = "/config-template"
            name = "config-template"
          }
        }
        container {
          command = [
            "notary-signer",
            "-config=/config/signer-config.json",
          ]
          image = "notary:${var.signer_image_version}"
          name = "signer"
          env {
            name = "NOTARY_SIGNER_${upper(var.signer_default_alias)}"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.signer_alias.metadata.0.name
                key = "alias-secret"
              }
            }
          }
          port {
            container_port = var.signer_port
            name = "https"
          }
          volume_mount {
            mount_path = "/config"
            name = "config-rendered"
          }
          volume_mount {
            mount_path = "/tls"
            name = "tls"
          }
        }
        volume {
          name = "config-template"
          config_map {
            name = kubernetes_config_map.notary_config.metadata.0.name
          }
        }
        volume {
          name = "tls"
          secret {
            secret_name = kubernetes_secret.notary_tls.metadata.0.name
          }
        }
        volume {
          name = "config-rendered"
          empty_dir {
            medium = ""
          }
        }
      }
    }
  }
}

resource "kubernetes_job" "notary_signer_migrate" {
  metadata {
    name = "notary-signer-migrate"
    namespace = var.namespace
  }
  spec {
    completions = 1
    parallelism = 1
    backoff_limit = 100
    template {
      metadata {
        labels = {
          app = "notary"
          component = "notary-signer-migrate"
        }
      }
      spec {
        init_container {
          command = [
            "/gomplate",
            "--left-delim",
            "%%",
            "--right-delim",
            "%%",
            "--in",
            var.signer_storage_db_url,
            "--out",
            "/migrate-configuration/db-url",
          ]
          image = "hairyhenderson/gomplate:v3"
          name = "gomplate"
          env {
            name = "PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.signer_password.metadata.0.name
                key = "password"
              }
            }
          }
          volume_mount {
            mount_path = "/migrate-configuration"
            name = "migrate-configuration"
          }
        }
        container {
          command = [
            "sh",
            "-c",
            "/migrate -path=/migrations/signer/${var.storage_flavor} -database=${var.storage_flavor}://$(cat /migrate-configuration/db-url) up"
          ]
          image = "migrate/migrate:${var.migrate_version}"
          name = "migrate"
          volume_mount {
            mount_path = "/migrations/signer/${var.storage_flavor}"
            name = "migrations-signer"
          }
          volume_mount {
            mount_path = "/tls"
            name = "tls"
          }
          volume_mount {
            mount_path = "/migrate-configuration"
            name = "migrate-configuration"
          }
        }
        restart_policy = "OnFailure"
        volume {
          name = "migrations-signer"
          config_map {
            name = kubernetes_config_map.notary_migrations_signer.metadata.0.name
          }
        }
        volume {
          name = "tls"
          secret {
            secret_name = kubernetes_secret.notary_tls.metadata.0.name
          }
        }
        volume {
          name = "migrate-configuration"
          empty_dir {
            medium = ""
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "notary_signer" {
  metadata {
    name = "notary-signer"
    namespace = var.namespace
  }
  spec {
    port {
      name = "https"
      port = var.signer_port
      target_port = var.signer_port
    }
    selector = {
      app = "notary"
      component = "notary-signer"
    }
  }
}