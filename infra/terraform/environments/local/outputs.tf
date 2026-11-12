output "namespaces" {
  description = "Namespaces managed by Terraform."
  value = {
    app        = var.app_namespace
    argocd     = var.argocd_namespace
    monitoring = var.monitoring_namespace
  }
}

output "gitops_repo_url" {
  description = "Repository URL Argo CD is tracking (as seen from inside the cluster)."
  value       = local.repo_url
}

output "gitops_mode" {
  value = var.gitops_mode
}

output "db_secret_name" {
  description = "Secret holding the generated MySQL credentials (consumed by the Helm chart via secret.existingSecret)."
  value       = module.app_secret.name
}

output "argocd_admin_password_command" {
  description = "Argo CD generates its initial admin password; this prints it."
  value       = "kubectl --context ${var.kube_context} -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "grafana_admin_user" {
  value = module.monitoring.grafana_admin_user
}

output "grafana_admin_password" {
  description = "Generated Grafana admin password. Read with: terraform output -raw grafana_admin_password"
  value       = module.monitoring.grafana_admin_password
  sensitive   = true
}
