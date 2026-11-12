# Changelog

All notable changes are recorded here. Format: [Keep a Changelog](https://keepachangelog.com/),
versioning: [SemVer](https://semver.org/) once releases are tagged.

## [Unreleased]

### Added
- Containerised application (multi-stage, non-root, digest-pinned base images).
- Helm chart with MySQL, probes, NetworkPolicy, PodMonitor, alert rules and Grafana dashboard.
- Terraform for the local kind cluster (namespaces, secrets, Argo CD, monitoring, git mirror) and an
  optional, validate-only AWS EKS configuration.
- Argo CD GitOps flow; images referenced by digest; rollback by `git revert`.
- GitHub Actions CI: tests, validation, Trivy gate, SBOM, provenance, release pull request.
- Release verification (12 checks), bad-release demo and JSON/Markdown release reports.
- `./run.sh` command-line entry point.

### Changed
- Repository layout: Terraform split into `infra/terraform/modules` and `infra/terraform/environments/{local,aws}`;
  scripts grouped into `setup/`, `release/`, `verify/`, `lib/`, `ci/`; git-mirror image moved to `deploy/git-mirror`.
- README shortened to an entry point; details moved to `docs/` (architecture, runbooks, results, limitations).
- CI also lints Dockerfiles (hadolint), workflows (actionlint) and the rendered chart (kubeconform).
- Spring Boot 3.3.5 to 3.5.16 (Tomcat and Jackson overridden to patched versions).
- `POST /user` returns a `Location` header; an unknown user returns 404.

### Fixed
- Release step no longer stops silently on a clean git checkout.
- Grafana memory limit raised after out-of-memory kills.
