# Release report

Generated 2026-11-08T14:37:09Z from workspace revision `d49d93ba1e43` (with uncommitted changes).

> Every value is read from a result recorded by the scripts that produced it. Anything not executed is marked not-run.

## Artifact

| | |
|---|---|
| Image | `localhost:5001/releaseops/app@sha256:73c121b088f30a2b171a6184b9218fb7f88fac22a95fa8a9b3bdbb199de06b6c` |
| Tag | `d49d93ba1e43-dirty-20261108143220` |
| Digest | `sha256:73c121b088f30a2b171a6184b9218fb7f88fac22a95fa8a9b3bdbb199de06b6c` |
| GitOps commit that pinned it | `f44a0ebd5329e1576a2621b5fb14b474d621b925` |
| Helm chart | releaseops `0.1.0` |
| Kubernetes | v1.36.4 |
| Terraform | Terraform v1.14.5 |

## Build and test

✅ passed — 15 tests, 0 failures, 0 errors, 0 skipped in 58s

## Supply chain

- Vulnerability scan: ✅ passed — 0 critical / 0 high fixable findings remaining; 2 CVE exception(s) accepted in .trivyignore.yaml (each justified and expiring); policy: fail on fixable HIGH/CRITICAL; .trivyignore.yaml entries need a statement and an expiry date
- SBOM: ✅ generated — CycloneDX JSON, 146 components (`reports/out/sbom.cdx.json`)

## GitOps and rollout

- Argo CD: sync **Synced**, health **Healthy**, revision `1bc24f865f1f`, source `http://git-mirror.gitops-mirror.svc.cluster.local:8080/releaseops.git`
- Deployment: 2/2 available, image `localhost:5001/releaseops/app@sha256:73c121b088f30a2b171a6184b9218fb7f88fac22a95fa8a9b3bdbb199de06b6c`

## Release verification

Overall: ✅ passed (12 passed, 0 failed, 0 skipped)

| Check | Result | Detail |
|---|---|---|
| `argocd.sync` | ✅ pass | Synced at revision f44a0ebd5329 (last operation: Succeeded) |
| `argocd.health` | ✅ pass | Healthy |
| `image.expected` | ✅ pass | Deployment and 2 running pod(s) pin sha256:73c121b088f3… |
| `k8s.rollout` | ✅ pass | rollout complete: 2/2 available, all updated (reason=NewReplicaSetAvailable) |
| `k8s.pods` | ✅ pass | 2 app pod(s) and 1 MySQL pod Ready |
| `k8s.restarts` | ✅ pass | 0 container restart(s) since the pods started |
| `app.health` | ✅ pass | status=UP db=UP (pod releaseops-b8d45cfcd-d8tsx) |
| `api.post` | ✅ pass | HTTP 200, created verify-20261108143230-27664 at /user?id=2 |
| `api.get` | ✅ pass | GET /user?id=2 -> "Greetings from Crewmeister, verify-20261108143230-27664!" |
| `db.persistence` | ✅ pass | row id=2 found directly in MySQL with name 'verify-20261108143230-27664' (persisted, not just echoed) |
| `db.migrations` | ✅ pass | 1 successful Flyway migration(s) recorded |
| `monitoring.scrape` | ✅ pass | Prometheus scrapes 2/2 app targets; app_database_up=1 |

## Failure injection (bad release)

- Scenario: `bad-config`; bad revision `0541e8234264`
- Verification of the bad release: **failed** — detected 66s after the commit
  - `argocd.health`: health=Degraded:  Deployment Progressing=False (ProgressDeadlineExceeded)
  - `k8s.rollout`: ProgressDeadlineExceeded: updated=1 available=2/2 total=3
  - `k8s.pods`: pods not Ready: releaseops-7575fb7fd8-j6gv6
- Likely cause (heuristic from real diagnostics): the application cannot connect to MySQL (connection refused / link failure)
- Availability probe (GET /user?id=1 every 0.5s, from before the bad commit until recovery was verified): 316 requests, 316 returned HTTP 200, 0 not OK
- Monitoring: Prometheus alert `ReleaseOpsRolloutStuck` final state during the failure: **firing**
- Drift: kubectl scale replicas 2 -> 3; self-healed=true in 0s

## Recovery (Git revert)

- Known-good `f44a0ebd5329` → revert commit `1bc24f865f1f`; recovered and re-verified in 7s: ✅ passed
- Data survival: record `canary-143423` readable after recovery = true; MySQL pod untouched = true
- Demo overall: ✅ passed
