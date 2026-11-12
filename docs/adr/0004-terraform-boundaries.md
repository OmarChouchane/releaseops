# ADR-0004: Terraform boundaries and staged provisioning

**Status:** accepted

## Context
Terraform must "interact with the Kubernetes cluster". Argo CD must own the application. Two controllers must never
manage the same object, and Terraform providers must not depend on resources created in the same configuration
(the classic *provider initialisation cycle*).

## Decision
**Stage 0 – shell** (`scripts/setup/cluster.sh`): create/reuse the kind cluster and the local registry. A cluster can not
be both created by Terraform *and* used by that Terraform's kubernetes/helm providers in the same run without
cycles, so it is created first and Terraform connects to it by a static kubeconfig path + pinned context
(`kind-releaseops`; it can not act on any other cluster).

**Stages 1–4 – one Terraform root** (`infra/terraform/environments/local`) with small modules:

| Module | Owns |
|---|---|
| `namespaces` | `releaseops`, `argocd`, `monitoring` with Pod Security labels (`enforce` baseline/restricted) |
| `app-secret` | Random MySQL credentials in a Kubernetes Secret – **the only place they exist** |
| `git-mirror` | (local mode) in-cluster git server, see ADR-0005 |
| `argocd` | `argo-cd` Helm release, then `AppProject` + `Application` |
| `monitoring` | `kube-prometheus-stack`, random Grafana admin password |

**Argo CD owns** everything the application chart renders inside the `releaseops` namespace. Terraform never
renders that chart; Argo CD has `CreateNamespace=false` and an `AppProject` that forbids cluster-scoped resources,
so the namespace and Secret can only ever be changed by Terraform.

**`AppProject`/`Application` are installed via a tiny local Helm chart** (`helm_release`), not `kubernetes_manifest`.
`kubernetes_manifest` needs the CRD to exist at *plan* time, which breaks a first-time `apply`; a Helm release
defers that to apply time, after the `argo-cd` release (explicit `depends_on`) has installed the CRDs.

**State**: local backend, path chosen by `run.sh` (`-backend-config=path=`) inside the git-ignored `.releaseops/`
directory, mode `0600`. The state contains generated passwords – it is a secret. For anything shared use a remote
encrypted backend with locking (the AWS root has the S3 block ready, commented).

**Versions**: providers pinned `~> x.y.0` + committed `.terraform.lock.hcl` with hashes for five platforms.

## Consequences
+ A first `apply` works in one pass; `terraform destroy` removes only what Terraform created.
+ Credentials never touch Git or rendered manifests.
− Two moving parts (script + Terraform) instead of one; documented, and `./run.sh setup` hides it.
− `random_password` values live in a local state file – acceptable for a laptop, not for a team.
