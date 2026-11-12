variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "name" {
  description = "Prefix for all resources."
  type        = string
  default     = "releaseops"
}

variable "kubernetes_version" {
  description = "EKS control-plane version (standard support through 2027-08 for 1.36 at time of writing)."
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones. EKS requires at least 2."
  type        = number
  default     = 2
  validation {
    condition     = var.az_count >= 2
    error_message = "EKS needs subnets in at least two availability zones."
  }
}

# ------------------------------------------------------------------ cost levers
variable "private_nodes" {
  description = <<-EOT
    true  = worker nodes in private subnets behind ONE NAT gateway (~US$33/month + data) - the
            production-shaped layout.
    false = worker nodes in public subnets with public IPs and NO NAT gateway - cheapest, fine for a
            short-lived demo, NOT recommended for production (nodes are directly addressable; security
            groups are the only barrier).
  EOT
  type        = bool
  default     = false
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "use_spot_nodes" {
  description = "Spot capacity (~70% cheaper) - acceptable for a stateless demo, nodes can be reclaimed."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------ access
variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the PUBLIC Kubernetes API endpoint, e.g. [\"203.0.113.7/32\"]. Required (no default) so the apply forces a decision; 0.0.0.0/0 is rejected."
  type        = list(string)
  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && !contains(var.api_allowed_cidrs, "0.0.0.0/0")
    error_message = "Provide at least one CIDR and do not use 0.0.0.0/0."
  }
}

# ------------------------------------------------------------------ CI (OIDC, no stored keys)
variable "github_repository" {
  description = "owner/repo allowed to assume the CI role through GitHub OIDC (e.g. \"OmarChouchane/releaseops\"). Empty disables the CI role."
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "Only workflow runs on this branch may push images."
  type        = string
  default     = "main"
}

variable "ecr_keep_images" {
  type    = number
  default = 20
}
