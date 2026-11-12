# Terraform modules

Reusable modules, consumed by the root configurations in [`../environments/`](../environments/).

| Module | Purpose |
|---|---|
| `namespaces` | Namespaces with Pod Security `enforce` labels |
| `app-secret` | Random database credentials in a Kubernetes Secret (never in Git) |
| `argocd` | Argo CD, plus a small chart that installs the `AppProject` and `Application` after the CRDs exist |
| `monitoring` | kube-prometheus-stack sized for a laptop, with a generated Grafana password |
| `git-mirror` | Throw-away in-cluster git server for the local demo (local mode only) |

Conventions: every module declares its inputs with types and descriptions, validates what it can, and has no
provisioners. A module is added here only when more than one environment could use it or when it isolates a clear
ownership boundary.
