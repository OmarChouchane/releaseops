output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Run this to get a kubeconfig for the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "ecr_repository_url" {
  description = "Set image.repository in deploy/environments/aws/values.yaml to this."
  value       = aws_ecr_repository.app.repository_url
}

output "github_ci_role_arn" {
  description = "Set as the repository variable AWS_ROLE_ARN for .github/workflows/aws-plan.yml."
  value       = try(aws_iam_role.github_ci[0].arn, null)
}

output "estimated_monthly_cost_note" {
  value = var.private_nodes ? "EKS control plane (~US$73) + ${var.node_desired_size}x nodes + 1 NAT gateway (~US$33) + EBS. Destroy when not in use." : "EKS control plane (~US$73) + ${var.node_desired_size}x nodes + EBS; no NAT gateway. Destroy when not in use."
}
