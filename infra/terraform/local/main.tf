locals {
  git_mirror_namespace = "gitops-mirror"
  git_mirror_url       = "http://git-mirror.${local.git_mirror_namespace}.svc.cluster.local:8080/releaseops.git"
  repo_url             = var.gitops_mode == "local" ? local.git_mirror_url : var.gitops_repo_url
}

# ---------------------------------------------------------------------------------------------
# Ownership boundaries (docs/adr/0004-terraform-boundaries.md)
#  Terraform owns: namespaces, DB Secret, Argo CD, AppProject/Application, monitoring, git mirror
#  Argo CD owns:   everything the app Helm chart renders in the releaseops namespace
# So the two never fight over a resource.
# ---------------------------------------------------------------------------------------------

module "namespaces" {
  source = "./modules/namespaces"
  namespaces = {
    (var.app_namespace)        = { enforce = "restricted" }
    (var.argocd_namespace)     = { enforce = "baseline" }
    (var.monitoring_namespace) = { enforce = "baseline" }
  }
}

module "app_secret" {
  source    = "./modules/app-secret"
  namespace = module.namespaces.names[var.app_namespace]
  name      = "${var.app_name}-db"
}

module "git_mirror" {
  source    = "./modules/git-mirror"
  count     = var.gitops_mode == "local" ? 1 : 0
  namespace = local.git_mirror_namespace
  image     = var.git_mirror_image
}

module "argocd" {
  source = "./modules/argocd"

  namespace     = module.namespaces.names[var.argocd_namespace]
  chart_version = var.argocd_chart_version
  node_port     = var.argocd_node_port
  app_name      = var.app_name
  app_namespace = module.namespaces.names[var.app_namespace]
  environment   = var.environment
  repo_url      = local.repo_url
  revision      = var.gitops_revision
  repo_username = var.gitops_repo_username
  repo_password = var.gitops_repo_password

  # The git mirror must exist before Argo CD fetches from it
  depends_on = [module.git_mirror]
}

module "monitoring" {
  source = "./modules/monitoring"

  namespace            = module.namespaces.names[var.monitoring_namespace]
  chart_version        = var.kube_prometheus_stack_chart_version
  grafana_node_port    = var.grafana_node_port
  prometheus_node_port = var.prometheus_node_port
}
