terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
  }
}

variable "namespace" { type = string }
variable "chart_version" { type = string }
variable "node_port" { type = number }
variable "app_name" { type = string }
variable "app_namespace" { type = string }
variable "environment" { type = string }
variable "repo_url" { type = string }
variable "revision" { type = string }
variable "repo_username" {
  type    = string
  default = ""
}
variable "repo_password" {
  type      = string
  default   = ""
  sensitive = true
}

# --------------------------------------------------------------------------- Argo CD itself
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = var.namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version

  atomic          = true
  wait            = true
  timeout         = 600
  cleanup_on_fail = true

  values = [yamlencode({
    # Components a single-cluster demo does not need are off to save memory:
    dex           = { enabled = false } # no SSO
    notifications = { enabled = false }
    # This chart version has no `enabled` switch for the ApplicationSet controller; the demo
    # does not use ApplicationSets, so it is scaled to zero.
    applicationSet = { replicas = 0 }
    configs = {
      params = {
        # TLS is terminated nowhere on localhost; the UI is bound to 127.0.0.1 by the kind port mapping.
        "server.insecure" = true
      }
      cm = {
        # Poll Git every ~30s so the demo reacts quickly (default 120s + 60s jitter).
        "timeout.reconciliation"        = "30s"
        "timeout.reconciliation.jitter" = "10s"
        # Track ownership with annotations (the Argo CD 3.x default, made explicit here).
        "application.resourceTrackingMethod" = "annotation"
      }
    }
    server = {
      service = {
        type         = "NodePort"
        nodePortHttp = var.node_port
      }
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
    }
    controller = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
    repoServer = {
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "512Mi" }
      }
    }
    redis = {
      resources = {
        requests = { cpu = "25m", memory = "32Mi" }
        limits   = { memory = "128Mi" }
      }
    }
  })]
}

# Credentials for a private remote repository. Not created for the (default) public/local source.
resource "kubernetes_secret_v1" "repo_credentials" {
  count = var.repo_password != "" ? 1 : 0

  metadata {
    name      = "releaseops-repo"
    namespace = var.namespace
    labels    = { "argocd.argoproj.io/secret-type" = "repository" }
  }
  data = {
    type     = "git"
    url      = var.repo_url
    username = var.repo_username
    password = var.repo_password
  }
  depends_on = [helm_release.argocd]
}

# --------------------------------------------------------------------------- GitOps root objects
# AppProject + Application live in a tiny local chart, installed AFTER Argo CD. Using a Helm release
# (instead of kubernetes_manifest) means Terraform does not need the Argo CD CRDs at *plan* time, so
# a first-time `terraform apply` works in a single pass.
resource "helm_release" "gitops_bootstrap" {
  name      = "gitops-bootstrap"
  namespace = var.namespace
  chart     = "${path.module}/chart"

  atomic          = true
  wait            = true
  cleanup_on_fail = true

  values = [yamlencode({
    appName      = var.app_name
    appNamespace = var.app_namespace
    environment  = var.environment
    repoURL      = var.repo_url
    revision     = var.revision
  })]

  depends_on = [helm_release.argocd, kubernetes_secret_v1.repo_credentials]
}

output "application_name" {
  value = var.app_name
}
