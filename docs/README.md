# Documentation

| Read this | When |
|---|---|
| [architecture.md](architecture.md) | How delivery, Terraform, CI, security, verification and monitoring fit together |
| [runbooks/getting-started.md](runbooks/getting-started.md) | Prerequisites, commands, access URLs, cleanup |
| [runbooks/demo-and-rollback.md](runbooks/demo-and-rollback.md) | What the bad-release demo does and how recovery works |
| [runbooks/troubleshooting.md](runbooks/troubleshooting.md) | Something failed |
| [runbooks/remote-mode.md](runbooks/remote-mode.md) | Make Argo CD track your own GitHub repository |
| [application.md](application.md) | The API and running the app without Kubernetes |
| [results.md](results.md) | Measured results and the bugs the runs found |
| [limitations.md](limitations.md) | What was not executed and the deliberate design limits |
| [VERSIONS.md](VERSIONS.md) | Version choices and their sources |
| [CHALLENGE.md](CHALLENGE.md) | The original challenge text |
| [evidence/](evidence/) | Raw results of the recorded runs (reports, verification JSON, SBOM, scanner output) |

## Architecture decision records

| ADR | Decision |
|---|---|
| [0001](adr/0001-local-first-architecture.md) | Local-first on kind; AWS optional and unprovisioned |
| [0002](adr/0002-spring-boot-upgrade.md) | Keep the app; upgrade Boot; minimal, additive changes |
| [0003](adr/0003-container-image.md) | Multi-stage, layered, non-root, digest-pinned image |
| [0004](adr/0004-terraform-boundaries.md) | Terraform boundaries, staging, state |
| [0005](adr/0005-gitops-source-and-release-flow.md) | GitOps flow, release PRs, the in-cluster git mirror |
| [0006](adr/0006-mysql-in-cluster.md) | MySQL StatefulSet (demo) vs managed DB (production) |
| [0007](adr/0007-release-verification.md) | Verification is separate from Argo CD health |
| [0008](adr/0008-observability.md) | Prometheus/Grafana choices and alerts |

New decisions get the next number and the same four parts: context, decision, consequences, status.
