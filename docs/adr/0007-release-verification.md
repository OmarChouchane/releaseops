# ADR-0007: Release verification is separate from Argo CD health

**Status:** accepted

## Problem
"Argo CD says *Healthy*" means: the resources it manages passed Kubernetes-level health assessments. It does not
mean the business function works. A Deployment can be Healthy while the API returns wrong data, the database is
unreachable (if readiness did not include it), or the *wrong image* is running. Conversely, Argo CD does not undo a
bad release – it applies whatever Git contains.

## Decision
`scripts/verify.sh` is the acceptance gate. A release is verified only if **all** of these pass:

1. `argocd.sync` – Application `Synced` to the expected Git revision, no operation in flight
2. `argocd.health` – Application `Healthy` (early exit if `Degraded`)
3. `image.expected` – Deployment *and* each running pod use the expected digest (`imageID`)
4. `k8s.rollout` – updated = available = desired; fails early on `ProgressDeadlineExceeded`
5. `k8s.pods` – every app pod Ready, MySQL Ready
6. `k8s.restarts` – no restart loop
7. `app.health` – actuator health UP **including** the `db` component (via `kubectl exec`, since the management port is not in the Service)
8. `api.post` – `POST /user` through the Service: 200, exact greeting, `Location` header
9. `api.get` – `GET /user?id=<new id>` returns what was written
10. `db.persistence` – the row is read **directly from MySQL** (not just echoed by the API)
11. `db.migrations` – Flyway history has successful entries
12. `monitoring.scrape` – Prometheus sees every replica up and `app_database_up == 1` (reported as *skipped* if Prometheus is unreachable – never as a pass)

Output: a table, `verification-<label>.json`, and on failure **real diagnostics** (Argo conditions, Deployment
conditions, pod container states, events, filtered application logs) plus a *labelled-as-heuristic* likely cause.

## Properties
* Exit code is the contract (`0` verified, `1` failed) – usable from CI.
* Skips are listed and counted separately; a skipped check is never rendered as success.
* The API check goes through the NodePort Service – the path real clients take – not through a pod.

## Alternatives rejected
* **Argo Rollouts / analysis templates**: valuable for canary/blue-green, but a second controller, more CRDs and
  memory. The simpler design is complete and demonstrates the gap Rollouts would close; it is not a prerequisite.
* **Relying on `argocd app wait --health`**: reproduces exactly the gap described above.
* **Helm test hooks**: run inside the release, not as an independent observer of the whole pipeline.

## Consequences
The probes (liveness excludes the DB, readiness includes it) and `maxUnavailable: 0` make a bad release *safe* (old
pods keep serving) in addition to *detected*; verification makes it *visible*; Git revert makes it *recoverable*.
