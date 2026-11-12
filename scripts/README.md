# Scripts

The automation behind [`run.sh`](../run.sh). Run scripts through `./run.sh`, not directly.

| Folder | Scripts | Purpose |
|---|---|---|
| `setup/` | `doctor.sh`, `install-tools.sh`, `cluster.sh`, `infra.sh` | Prerequisites, CLI tools, kind cluster and registry, Terraform |
| `release/` | `release.sh`, `report.sh` | Test, build, scan, SBOM, push, pin the digest; build the release report |
| `verify/` | `verify.sh`, `monitor-check.sh`, `demo.sh`, `status.sh` | Release verification, monitoring proof, bad-release demo, status |
| `lib/` | `common.sh`, `gitops.sh` | Shared configuration and helpers, sourced by the others |
| `ci/` | `update-image-pin.sh` | Used by the GitHub Actions release PR job |

## Conventions

- `set -uo pipefail`, quoted variables, `shellcheck -S warning` clean.
- Configuration comes from environment variables with defaults in `lib/common.sh`.
- Scripts only touch resources named `releaseops*` and use a dedicated kubeconfig (`.releaseops/kubeconfig`).
- Each step records what happened in `.releaseops/*.json`; reports are built from those files.
