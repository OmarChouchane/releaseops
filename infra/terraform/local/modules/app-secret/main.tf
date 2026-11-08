terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    random     = { source = "hashicorp/random" }
  }
}

variable "namespace" { type = string }
variable "name" { type = string }

# Alphanumeric only: the values end up in JDBC settings and shell probes.
resource "random_password" "mysql_root" {
  length  = 32
  special = false
}

resource "random_password" "mysql_app" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "db" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "releaseops"
    }
  }
  type = "Opaque"
  # Key names are the contract with the Helm chart (templates/deployment.yaml, mysql.yaml).
  data = {
    "mysql-user"          = "app"
    "mysql-password"      = random_password.mysql_app.result
    "mysql-root-password" = random_password.mysql_root.result
  }
}

output "name" {
  value = kubernetes_secret_v1.db.metadata[0].name
}
