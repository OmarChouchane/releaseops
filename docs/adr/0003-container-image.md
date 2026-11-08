# ADR-0003: Container image

**Status:** accepted

## Decision
Multi-stage `Dockerfile`:

* **Build stage** `eclipse-temurin:17-jdk-alpine` – dependencies resolved in their own layer with a BuildKit cache
  mount, so a source edit does not re-download Maven artifacts.
* **Runtime stage** `eclipse-temurin:17-jre-alpine` – JRE only, no compiler, no Maven, no shell for the app user.
* Spring Boot **layered extraction** (`java -Djarmode=tools extract --layers`): dependencies / loader / snapshot / application
  are separate layers; a code change rebuilds a few KB, not 50 MB.
* **Non-root**: numeric `10001:10001` (so Kubernetes can verify `runAsNonRoot`), `nologin` shell, no home dir.
* **Base images pinned by digest** (tag kept in the same line for humans); Dependabot's `docker` ecosystem proposes bumps.
* JVM: `MaxRAMPercentage=70` (heap follows the container limit), `ExitOnOutOfMemoryError` (die and be restarted
  rather than limp), `java` is PID 1 via exec-form `ENTRYPOINT` so SIGTERM reaches Spring's graceful shutdown.
* `HEALTHCHECK` uses busybox `wget` against the readiness endpoint for plain `docker run`; Kubernetes ignores it.
* `.dockerignore` keeps `.git`, state, Terraform files and docs out of the build context.

## Alternatives considered
* **Distroless Java 17**: smaller attack surface (no shell, no busybox). Rejected for now because `kubectl exec ... wget`
  is used by the verification and a shell-less image makes incident debugging harder; Alpine + Trivy scan gating is
  a reasonable middle ground. Revisit with ephemeral debug containers.
* **Buildpacks / Jib**: good, but a visible Dockerfile is what the challenge asks for and is easier to review.

## Consequences
Alpine uses musl libc; the app has no native dependencies, so this is safe. Tests are *not* run inside `docker build`
(Testcontainers needs a Docker daemon); they run in CI and `./run.sh test` before the image is built.
