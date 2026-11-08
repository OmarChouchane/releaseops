terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
  }
}

variable "namespaces" {
  description = "Map of namespace name => { enforce = Pod Security Standard level }."
  type        = map(object({ enforce = string }))
}

resource "kubernetes_namespace_v1" "this" {
  for_each = var.namespaces

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = each.value.enforce
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }
}

output "names" {
  value = { for k, v in kubernetes_namespace_v1.this : k => v.metadata[0].name }
}
