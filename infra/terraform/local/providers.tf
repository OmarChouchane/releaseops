# Both providers talk to a cluster that ALREADY exists (created by scripts/cluster.sh), via a
# static kubeconfig path. That is what avoids the classic provider-initialisation cycle where a
# provider is configured from the output of a resource in the same configuration.

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}
