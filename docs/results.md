# Results

Measured results from the runs on the author's machine. Raw evidence is in [evidence/](evidence/).

> **Note on the layout.** These runs used the earlier folder layout. Terraform was later split into `infra/terraform/modules` and `infra/terraform/environments/*`, and the scripts were grouped into `scripts/{setup,release,verify,lib,ci}/`. Since then CI is green and `./run.sh validate`, `terraform validate` and the link and path checks pass. A full `./run.sh up` on the new layout has not been completed yet.

Everything here was produced on **one machine**, with the code exactly as delivered (the final clean-room run: `up` then `demo`): Windows 10 + WSL2 Ubuntu 24.04, Docker Desktop 28.3.2 (16 CPUs, 7.7 GiB visible), kind v0.33.0 / Kubernetes 1.36.4, Helm 4.1.3, Terraform 1.14.5, from a WSL-native working copy. Raw evidence is committed in [`docs/evidence/`](evidence/) (release report, per-check verification JSON, demo result, SBOM, scanner report).

| Check | Command | Result |
|---|---|---|
| Unit + integration tests | `./run.sh test` (inside `up`) | **15 passed, 0 failed** (4 controller unit, 2 metric unit, 8 black-box API/actuator contract tests on real MySQL 8.4, 1 context test) |
| Image | `docker build` | builds; **122 MB**; runs as uid 10001; answers the API; `docker stop` triggers Spring graceful shutdown (log-verified); Docker `HEALTHCHECK` reports healthy |
| Vulnerability scan | Trivy 0.76.0, HIGH/CRITICAL, fixable only | First scan **failed the release** (13 findings). After patching Tomcat and Jackson: **0 remaining**, 2 documented/expiring exceptions ([ADR-0002](adr/0002-spring-boot-upgrade.md)) |
| SBOM | Trivy CycloneDX | 146 components ([docs/evidence/sbom.cdx.json](evidence/sbom.cdx.json)) |
| Helm | `helm lint --strict`, `helm template` | clean; deployed to kind and running under `restricted` Pod Security |
| Terraform (local) | `fmt -check`, `validate`, **`apply`** | clean; first apply from zero: **15 resources added**; re-apply converges (2 benign changes) |
| Terraform (AWS) | `fmt -check`, `validate` | clean — **never planned or applied** |
| Shell | `bash -n`, `shellcheck -S warning` (v0.10.0) | clean on every script |
| Workflows | `actionlint` 1.7.7 | clean on all three workflows; the `ci` workflow also ran on GitHub (run 42503262735: validate, tests, image build + Trivy gate + SBOM + GHCR push, release PR #6 — all green) |
| NetworkPolicy | a non-app pod connecting to MySQL:3306 | **BLOCKED** (the app itself connects normally) |
| `./run.sh up` from a clean slate | cluster, registry and Terraform state deleted first (Trivy cache kept) | **exit 0 in 425 s**. The first success took five clean-room attempts; each failure was a real bug, all fixed (below). The run reported here is a sixth, on the final code |

**Release verification** on the clean-room run — `RELEASE VERIFIED  12 passed, 0 skipped`
(Argo sync, Argo health, image digest on the Deployment *and* the pods, rollout, pods Ready, 0 restarts, actuator + DB, `POST /user`, `GET /user`, row read directly from MySQL, Flyway, Prometheus scraping 2/2 replicas).

**Monitoring** (`./run.sh monitor`): of 24 dashboard queries, 18 returned data and 6 were valid but empty at that moment (traffic-dependent panels before any traffic); 0 invalid. All 6 alert rules loaded. Grafana imported the dashboard, and a query through its `prometheus` datasource returned `app_database_up = 1`.

**Failure demonstration** (`./run.sh demo`, scenario `bad-config`, run right after the clean-room `up` of the final code):

| t | Event |
|---|---|
| 6 s | known-good `f44a0ebd5329` recorded; canary user created |
| 7 s | `kubectl scale` 2→3: Argo CD marked it `OutOfSync` and **self-healed in 0 s** |
| 7 s | bad commit `0541e8234264` pushed (database host typo) |
| 73 s | `verify` **FAILED** (3 checks: `argocd.health` Degraded, `k8s.rollout` ProgressDeadlineExceeded, `k8s.pods` new pod not Ready) → detected **66 s** after the commit. Diagnostics showed `releaseops-mysql-typo: Name does not resolve` |
| 163 s | Prometheus alert `ReleaseOpsRolloutStuck` was **FIRING** |
| 164 s | `git revert` → `1bc24f865f1f` pushed |
| 170 s | Argo CD reconciled; `verify` **passed** (11 passed + 1 skipped) — 7 s after the revert |
| throughout | availability probe: **316/316 requests returned HTTP 200** across the failure and the recovery |
| end | canary user still readable; MySQL pod UID unchanged (never restarted) |

The same demo was also run twice before (repeatability: a second execution on the same cluster is safe) and once with `DEMO_SCENARIO=bad-image` (`ErrImagePull`/`ImagePullBackOff`; 205/205 probe requests OK; recovered).

### What the clean-room runs found (and what changed)
Running the documented one-liner from zero exposed these; none showed up when testing the pieces separately.
1. `restricted` Pod Security rejected the git-mirror pod — the Terraform provider renders `runAsNonRoot: false` unless it is set explicitly.
2. A background `kubectl port-forward` started through a shell function was orphaned (wrong `$!`), so the next step found its port busy.
3. Verification counted a `Terminating` pod of the *failed* ReplicaSet as "not Ready" right after a rollback.
4. Flyway gave up after ~50 s, but MySQL needs ~90 s to initialise a fresh volume → the app restarted once on first boot. Retries now cover ~2.5 min (inside the 180 s startup probe).
5. A 90 s progress deadline (tuned for the demo) was shorter than a legitimate first boot → Argo CD reported `Degraded`. The default is back to 180 s; only the *bad* release carries the short one.
6. Verification probed the API endpoint before waiting for readiness, so on a first boot it measured "pods not up yet".
7. After a *second* release of identical source, the image check failed falsely: the runtime reported the previous index digest for the same platform image (rebuilds get new provenance metadata, so the index digest changes while the image does not). The check now requires every live pod to be created from the expected digest **and** the runtime image to be that digest or provably the same platform image (verified against the registry); a wrong digest still fails (tested).

### Second check: a fresh clone from GitHub

After publishing, the repository was cloned again into a new directory in WSL (commit `b9ce86a`) and run on a slow
connection (12 Nov 2026). What that proved, and what it did not:

* **Proved** — the clone keeps the executable bits; Terraform created the cluster, Argo CD and the monitoring stack;
  the 15 tests passed on the clean checkout; the image built (122 MB); Argo CD deployed the public GHCR image from
  release PR #6 (`sha256:1c570c57…`); and `./run.sh demo` passed **twice** on that cluster:

  | Demo run | Detected | Alert `ReleaseOpsRolloutStuck` | Recovered after `git revert` | Requests | Data |
  |---|---|---|---|---|---|
  | 1 | 68 s | FIRING | 7 s | 341 / 341 returned 200 | canary kept, MySQL pod untouched |
  | 2 | 68 s | FIRING (172 s into the demo) | 7 s | 334 / 334 returned 200 | canary kept, MySQL pod untouched |

* **Not completed there** — a full `./run.sh up` from that clone did not run to its end: the Trivy vulnerability
  database download was too slow on that connection, so the scan, the push to the local registry and the final
  12-check verification were not reached in that clone. The 12/12 result above (806 s) comes from the earlier run.
* **Bugs this check found and fixed** — the release step stopped silently on a *clean* git checkout (it only worked on
  a working copy with uncommitted changes); Grafana was killed for running out of memory at a 384 Mi limit (now
  768 Mi); and on a very slow connection the 15-minute Helm timeout can expire (re-running `./run.sh up` recovers).
