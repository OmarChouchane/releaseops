variable "kubeconfig_path" {
  description = "Path to the kubeconfig of the kind cluster (written by scripts/cluster.sh)."
  type        = string
}

variable "kube_context" {
  description = "kubectl context of the kind cluster. Pinned so Terraform can never act on another cluster."
  type        = string
  default     = "kind-releaseops"
}

variable "app_namespace" {
  type    = string
  default = "releaseops"
}

variable "argocd_namespace" {
  type    = string
  default = "argocd"
}

variable "monitoring_namespace" {
  type    = string
  default = "monitoring"
}

variable "app_name" {
  description = "Helm release name == Argo CD Application name. Must match the Argo CD Application."
  type        = string
  default     = "releaseops"
}

variable "environment" {
  description = "Directory name under deploy/environments/ holding the values Argo CD applies."
  type        = string
  default     = "local"
}

# ------------------------------------------------------------------ GitOps source
variable "gitops_mode" {
  description = <<-EOT
    local  - Argo CD tracks an in-cluster git mirror seeded from your workspace. Works before
             the repository is published; lets the demo commit/revert without touching GitHub.
    remote - Argo CD tracks gitops_repo_url (your public GitHub repository).
  EOT
  type        = string
  default     = "local"
  validation {
    condition     = contains(["local", "remote"], var.gitops_mode)
    error_message = "gitops_mode must be \"local\" or \"remote\"."
  }
}

variable "gitops_repo_url" {
  description = "Repository Argo CD tracks when gitops_mode = remote, e.g. https://github.com/<you>/<repo>.git"
  type        = string
  default     = ""
  validation {
    condition     = var.gitops_mode != "remote" || can(regex("^https://", var.gitops_repo_url))
    error_message = "gitops_repo_url (https://...) is required when gitops_mode = \"remote\"."
  }
}

variable "gitops_revision" {
  description = "Branch (or tag/SHA) Argo CD tracks."
  type        = string
  default     = "main"
}

variable "gitops_repo_username" {
  description = "Only for a PRIVATE remote repository (read-only deploy credentials)."
  type        = string
  default     = ""
}

variable "gitops_repo_password" {
  description = "Only for a PRIVATE remote repository: a read-only token. Stored in Terraform state - keep it out of Git."
  type        = string
  default     = ""
  sensitive   = true
}

variable "git_mirror_image" {
  description = "Image of the in-cluster git mirror (built by run.sh and pushed to the local registry). Required in local mode."
  type        = string
  default     = ""
}

# ------------------------------------------------------------------ chart versions
variable "argocd_chart_version" {
  description = "argo-cd Helm chart (argo-helm). 10.11.6 ships Argo CD v3.5.6, which supports Kubernetes 1.33-1.36."
  type        = string
  default     = "10.11.6"
}

variable "kube_prometheus_stack_chart_version" {
  type    = string
  default = "92.9.0"
}

# ------------------------------------------------------------------ NodePorts (match scripts/cluster.sh)
variable "argocd_node_port" {
  type    = number
  default = 30081
}

variable "grafana_node_port" {
  type    = number
  default = 30300
}

variable "prometheus_node_port" {
  type    = number
  default = 30900
}
