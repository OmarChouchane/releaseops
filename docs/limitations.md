# Known limitations

What was not executed, and the deliberate design limits.

**Not executed (written and statically checked only):**
* **GitHub Actions, partly** — the `ci` workflow has run once on GitHub with all four jobs green and opened release PR #6 with the image digest. Not yet exercised: merging that PR, Argo CD deploying the GHCR image from it (`GITOPS_MODE=remote`), `gh attestation verify` on the published image, and the manual `aws-plan` workflow. PRs opened with `GITHUB_TOKEN` do not trigger further workflows.
* **`GITOPS_MODE=remote`** against a real GitHub repository, the private-repo credential Secret, and `DEMO_ALLOW_PUSH` pushes.
* **AWS/EKS** — `terraform validate` only. IAM, quotas, add-on behaviour and costs are unverified.
* Anything on macOS, native Linux, arm64, `/mnt/c` working copies, Terraform other than 1.14.5, Helm other than 4.1.3 (CI and the installer pin newer versions that were not exercised here).

**Design limits (deliberate, see the ADRs):**
* One-node cluster, one MySQL replica, no backups — a demo topology, not production.
* **Spring Boot 3.5.16 is past open-source support**; two `spring-webmvc` CVEs have no fix on the 6.2 line and are accepted in `.trivyignore.yaml` **until 2026-12-31** (features unused, verified by grep). The real fix is the Boot 4 migration.
* The in-cluster git mirror is unauthenticated and exists only for the local demo (ClusterIP + loopback port-forward).
* No Alertmanager: alerts are visible (and were seen firing) in Prometheus/Grafana but notify nobody.
* UIs are plain HTTP on loopback; secrets are Kubernetes Secrets (External Secrets/Vault is the production answer); no admission-time image-signature verification.
* Only the application image is scanned (not the MySQL/Argo CD/Prometheus images, not the IaC).
* `POST /user` with invalid JSON still returns `200 Error parsing JSON` (legacy behaviour, pinned by a test).
* The "likely cause" printed by verification is a labelled heuristic over real diagnostics, not an oracle.
* Traffic-dependent dashboard panels are empty until there is traffic.
