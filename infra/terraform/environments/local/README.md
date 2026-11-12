# Terraform: local environment (kind)

Root configuration for the local cluster. The cluster itself is created by `scripts/setup/cluster.sh`;
Terraform connects to it through a static kubeconfig path and a pinned context.

## What it manages

Namespaces with Pod Security labels, the generated database Secret, Argo CD, the Argo CD
`AppProject` and `Application`, kube-prometheus-stack and, in local mode, the in-cluster git mirror.
Everything the app Helm chart renders belongs to Argo CD. See [ADR-0004](../../../../docs/adr/0004-terraform-boundaries.md).

Modules are in [`../../modules/`](../../modules/).

## Use

Normally through the CLI, which wires kubeconfig, state and variables:

```bash
./run.sh setup          # cluster + terraform apply + Argo CD + monitoring
```

Direct use (state path must match `scripts/setup/infra.sh`):

```bash
terraform -chdir=infra/terraform/environments/local init -backend-config="path=$PWD/.releaseops/terraform.tfstate"
```

## State and secrets

State is a local file in the git-ignored `.releaseops/` directory (mode 0600). It contains generated
passwords, so treat it as a secret. Use an encrypted, locked remote backend for anything shared.

## Checks

```bash
terraform fmt -check -recursive
terraform init -backend=false && terraform validate
```

Providers are pinned to `~> 3.3.0` and `.terraform.lock.hcl` is committed for five platforms.
