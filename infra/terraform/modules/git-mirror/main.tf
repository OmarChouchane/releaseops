terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
  }
}

variable "namespace" { type = string }
variable "image" {
  description = "Image built from deploy/git-mirror (pushed to the local registry by run.sh)."
  type        = string
  validation {
    condition     = length(var.image) > 0
    error_message = "git_mirror_image must be set in local mode (run.sh builds and passes it)."
  }
}

# Throw-away git server inside the kind cluster only (not exposed outside)
# Lets the demo make real commits for Argo CD without touching GitHub
resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "data" {
  metadata {
    name      = "git-data"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "256Mi" }
    }
  }
  wait_until_bound = false # local-path provisioner binds on first use
}

resource "kubernetes_deployment_v1" "git_mirror" {
  metadata {
    name      = "git-mirror"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = { app = "git-mirror" }
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate" # single RWO volume
    }
    selector {
      match_labels = { app = "git-mirror" }
    }
    template {
      metadata {
        labels = { app = "git-mirror" }
      }
      spec {
        automount_service_account_token = false
        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          run_as_group    = 10001
          fs_group        = 10001
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name  = "git"
          image = var.image
          port {
            name           = "http"
            container_port = 8080
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds = 5
          }
          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { memory = "128Mi" }
          }
          security_context {
            # Set explicitly: otherwise runAsNonRoot=false is rendered and Pod Security rejects it
            run_as_non_root            = true
            run_as_user                = 10001
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.data.metadata[0].name
          }
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "git_mirror" {
  metadata {
    name      = "git-mirror"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    selector = { app = "git-mirror" }
    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }
  }
}
