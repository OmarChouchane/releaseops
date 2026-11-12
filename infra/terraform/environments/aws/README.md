# Optional: EKS on AWS

> **Status: validated offline only. Never applied.** `terraform init -backend=false`, `terraform validate` and
> `terraform fmt -check` pass (see CI job *validate*). No AWS account was used, so IAM permissions, service quotas,
> add-on behaviour and costs below are **unverified in a live environment**.

## What it creates
| Resource | Notes |
|---|---|
| VPC (2 AZs) | Public + private subnets. **No NAT gateway by default** (`private_nodes=false`): nodes sit in public subnets with public IPs – cheapest, demo-grade. Set `private_nodes=true` for the production layout with a single NAT (~US$33/month + data). |
| EKS cluster `1.36` | Public API endpoint **restricted to `api_allowed_cidrs`** (required, `0.0.0.0/0` rejected), private endpoint on, envelope encryption by the module default, creator gets admin via an EKS *access entry* (no `aws-auth` ConfigMap). |
| Managed node group | `t3.medium` ×2 (on-demand; `use_spot_nodes=true` for ~70% cheaper), AL2023. |
| Add-ons | CoreDNS, kube-proxy, VPC CNI, **Pod Identity agent**, **EBS CSI** (so the MySQL PVC works) with a Pod Identity role. |
| ECR `releaseops/app` | `IMMUTABLE` tags, scan on push, lifecycle keeps 20 images. |
| GitHub OIDC (optional) | Set `github_repository`; creates a role that **only** `repo:<owner>/<repo>:ref:refs/heads/main` can assume, with push rights to that one ECR repository. No long-lived keys. |

## Cost awareness
EKS control plane ≈ US$0.10/h (≈ US$73/month) before nodes. Two `t3.medium` ≈ US$60/month. Run it for the duration
of a demo and `terraform destroy`. Prices vary by region – check the AWS calculator; these numbers are approximate
and not measured here.

## Use
```bash
cd infra/terraform/environments/aws
terraform init
terraform plan  -var 'api_allowed_cidrs=["<your-ip>/32"]'      # review!
terraform apply -var 'api_allowed_cidrs=["<your-ip>/32"]'      # only when you accept the cost
$(terraform output -raw configure_kubectl)
```
Then install Argo CD (same chart `argo-cd`) and an Application pointing at `deploy/environments/aws/values.yaml`
(same Helm chart as the local environment). That second stage is intentionally a separate Terraform root/run: a
kubernetes/helm provider can only be configured once the cluster exists (see ADR-0004).

## Remote state
Uncomment the `backend "s3"` block in `versions.tf` after creating a private, versioned, encrypted bucket.
State contains secrets; never commit it.

## CI
`.github/workflows/aws-plan.yml` is a manual, plan-only workflow using OIDC. It is a no-op until
`vars.AWS_ROLE_ARN` is set.
