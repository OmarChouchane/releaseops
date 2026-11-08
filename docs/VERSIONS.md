# Version choices and sources

Researched on **2026-11-08**. Rule applied: *supported and compatible beats newest*. Anything released
in the last few days was not chosen when a slightly older, supported release existed.

How the data was gathered (so you can repeat it): GitHub Releases API (`gh api repos/<org>/<repo>/releases`),
the `endoflife.date` JSON API, the Argo CD docs in its repository, the kind release notes, and web searches
whose results are linked below. I did **not** consult vendor documentation for Docker/BuildKit or MySQL beyond
the facts in this table; where a row says "tag/digest verified", that means I resolved the image digest, not that I
read a support policy.

| Component | Chosen | Why | Source |
|---|---|---|---|
| Java | 17 (Temurin) | Required by the challenge; Spring Boot 3.5 supports it | challenge README |
| Spring Boot | **3.5.16** (was 3.3.5) | 3.3.x went out of OSS support 2025-06-30; 3.5.16 is the last OSS patch of the newest 3.x line that still runs on Java 17 with no code migration. 3.5 itself reached OSS EOL 2026-06-30 – the real long-term answer is Boot 4.x (a migration, out of scope). See [ADR-0002](adr/0002-spring-boot-upgrade.md) | endoflife.date `spring-boot`; [spring.io 3.3.13 notice](https://spring.io/blog/2025/06/19/spring-boot-3-3-13-available-now/) |
| MySQL | **8.4 LTS** (digest-pinned) | LTS line with support through 2032; the Flyway/Connector-J combination in Boot 3.5 is mainstream on 8.4. 9.7 LTS exists; 8.4 chosen as the conservative, widest-tested option. Tested in CI and locally via Testcontainers `mysql:8.4` | endoflife.date `mysql` (tag/digest verified) |
| Kubernetes (kind node) | **1.36.4** (digest-pinned) | Inside Argo CD 3.5's tested range (1.33–1.36); supported until 2027-06; 1.37 is brand new (default of kind 0.33) and outside that tested range | Argo CD `docs/operator-manual/tested-kubernetes-versions.md`; endoflife.date `kubernetes`; kind v0.33.0 release notes |
| kind | **v0.33.0** | Latest release, ships the pinned node images | GitHub releases |
| kubectl | v1.36.x | Within one minor of the server | – |
| Helm | **v4.x** (tested with 4.1.3 locally; CI uses 4.3.1) | Helm 4 is current; charts use only `apiVersion: v2` features, so Helm 3.1x also renders them (not tested) | GitHub releases |
| Terraform | `>= 1.14` (tested with **1.14.5** locally; CI/installer use 1.16.7) | 1.14 is what the author's WSL had; endoflife.date lists 1.15 as EOL since 2026-10-21 so use a newer one when you can | endoflife.date `terraform` |
| Terraform kubernetes provider | **~> 3.3.0** (lock: 3.3.0) | A 3.x release that is 5+ weeks old (3.5.0 was 3 days old) | GitHub releases |
| Terraform helm provider | **~> 3.3.0** (lock: 3.3.0) | Helm provider 3.x syntax (`kubernetes = {}` attribute, list `set`) | GitHub releases |
| Terraform aws provider | ~> 6.68 | ~1 month old 6.x | GitHub releases |
| EKS Terraform module | ~> 21.29 | v21 API (`name`, `kubernetes_version`, `addons`) | GitHub releases; validated with `terraform validate` |
| VPC Terraform module | ~> 6.7 | – | GitHub releases |
| EKS Kubernetes | 1.36 | Standard support to 2027-08 | endoflife.date `amazon-eks` |
| Argo CD | **v3.5.6** via chart `argo-cd` **10.11.6** | 3.5 is supported and is the newest line whose tested matrix includes K8s 1.36; 3.6.0 was released 5 days before this was written | endoflife.date `argo-cd`; GitHub releases of `argoproj/argo-helm`; chart `Chart.yaml` |
| kube-prometheus-stack | **92.9.0** (Prometheus Operator v0.94.1) | Three weeks old; the chart ships several releases per day, so "latest" is a moving target | GitHub releases of `prometheus-community/helm-charts` |
| Trivy | **0.76.0** | Post-incident release (see below) | GitHub releases |
| trivy-action | v0.36.0, pinned by commit SHA | See supply-chain note | GitHub releases |
| Other GitHub Actions | pinned by commit SHA (see `ci.yml` comments for tags) | Tags are mutable | GitHub API |
| registry image | `registry:2` by digest | Local registry for digest-based releases | – |

## Supply-chain note: why every action is pinned by SHA

In March 2026 the `aquasecurity/trivy-action` repository had 76 of its 77 version tags force-pushed to
malicious commits; only `v0.35.0` (protected by GitHub immutable releases) was unaffected, and a malicious
Trivy `v0.69.4` binary was published ([Legit Security write-up](https://www.legitsecurity.com/blog/the-trivy-supply-chain-compromise-what-happened-and-playbooks-to-respond),
[GHSA-69fq-xp46-6x23](https://osv.dev/vulnerability/GHSA-69fq-xp46-6x23)). I only had the search-result summaries
of those pages, not the full text. Consequences in this repository: all third-party Actions are referenced by
full commit SHA (Dependabot keeps them current), the Trivy *binary* is pinned to 0.76.0 (released after the
incident), and the local scanner runs from a version-pinned container image. A tag such as `@v0.36.0` would have
been a mutable reference.

## What is deliberately *not* current

* **Spring Boot 4.x** – supported, but a major migration (Jackson 3, modularised starters). Not worth the risk
  to an application whose job here is to be a faithful workload.
* **Kubernetes 1.37 / Argo CD 3.6** – released days ago; revisit after a patch release.
* **Terraform 1.14** is what was available in the author's WSL; the configuration uses nothing newer than 1.14.
