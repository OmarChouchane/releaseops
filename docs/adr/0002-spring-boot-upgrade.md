# ADR-0002: Keep the application, upgrade its framework patch line, add only what operations need

**Status:** accepted

## Context
The supplied app is Spring Boot **3.3.5**. That line left open-source support on 2025-06-30. The POM also pinned
`jackson-databind:2.15.0`, overriding the (newer) version Spring Boot manages. The `prometheus` actuator endpoint
was listed in the configuration but no registry was on the classpath, so `/actuator/prometheus` could not work.
`GET /user?id=<unknown>` threw a `NullPointerException` (HTTP 500). Tests required a MySQL on `localhost`.

## Decision
Smallest set of changes that makes the service deployable and observable, with the contract preserved:

| Change | Why | Contract impact |
|---|---|---|
| Boot 3.3.5 → **3.5.16** | Supported dependencies; still Java 17; no code migration | none |
| Removed `jackson-databind:2.15.0` pin | It downgraded a managed dependency | none |
| Added `micrometer-registry-prometheus` | Makes the already-configured endpoint real | additive |
| Actuator probes (`liveness`/`readiness`), readiness includes `db`, liveness does not | Correct Kubernetes probes; a DB outage must not restart pods | additive |
| Optional separate management port (`MANAGEMENT_SERVER_PORT`) | Keeps actuator out of the public Service; **unset by default → original behaviour** | none |
| `Location: /user?id=<id>` header on `POST /user` | Lets clients/verification read back the record they created (the body has no id) | additive |
| Unknown id → **404** (was 500 via NPE) | Obvious defect | 500→404 on a failure path |
| Graceful shutdown, Flyway connect retries, 3s Hikari timeout | App and MySQL start together in Kubernetes; fail fast, not hang | none |
| `app_database_up` gauge | A real "database health" metric from the app's point of view | additive |

### What the vulnerability gate found (first real scan, 2026-11-08)
After moving to Boot 3.5.16 the image scan **failed the release** with 13 fixable HIGH/CRITICAL findings:

| Component (as managed by Boot 3.5.16) | Findings | Resolution |
|---|---|---|
| `tomcat-embed-core` 10.1.55 | 5 critical, 1 high | **Fixed**: `<tomcat.version>10.1.59</tomcat.version>` (same minor line) |
| `jackson-core`/`jackson-databind` 2.21.4 | 5 high | **Fixed**: `<jackson-bom.version>2.21.7</jackson-bom.version>` |
| `spring-webmvc` 6.2.19 | 2 critical (CVE-2026-47884 XsltView, CVE-2026-47890 SSE + views) | **No OSS fix on the 6.2 line** (6.2.19 is the last release; the fix is in 7.0.9 = Boot 4). Features not used by this REST-only app (verified by grep). Recorded as two **expiring, individually justified** entries in `.trivyignore.yaml` (expire 2026-12-31) – not a blanket ignore. |

The honest long-term fix is the Boot 4.x migration; the exceptions expire so that decision cannot be forgotten.
The overrides should be dropped as soon as Boot's own managed versions include the fixes (the scan will say when).

**Kept on purpose:** `POST /user` with invalid JSON still answers **HTTP 200 `Error parsing JSON`**. That is
questionable API design, but changing it would silently change behaviour someone may depend on. It is pinned by a
characterisation test and listed under *Known limitations*.

## Consequences
+ 15 automated tests (unit + black-box contract tests against a real MySQL via Testcontainers) protect the contract.
− Boot 3.5 is itself past OSS support (2026-06-30). The honest long-term step is Boot 4.x, deliberately left out.
