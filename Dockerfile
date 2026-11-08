# syntax=docker/dockerfile:1.7

# Base images are pinned by digest (the tag is kept for humans). Dependabot's docker
# ecosystem proposes updates for both. See docs/adr/0003-container-image.md.

############################
# Stage 1: build
############################
FROM eclipse-temurin:17-jdk-alpine@sha256:efefbce46b0d79073a3a676d91ac6c4bf370d348af18e388bbf7482543d7866a AS build
WORKDIR /workspace

# Dependencies first: this layer (and the BuildKit cache mount) only invalidates when the
# pom or the wrapper changes, not on every source edit.
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN --mount=type=cache,target=/root/.m2 ./mvnw -B -ntp -q dependency:go-offline

COPY src/ src/
# Tests run in CI (and via `./run.sh test`) *before* the image is built, against a real MySQL
# via Testcontainers, which is not available inside `docker build`.
RUN --mount=type=cache,target=/root/.m2 ./mvnw -B -ntp -q -DskipTests package \
 && java -Djarmode=tools -jar target/*.jar extract --layers --launcher --destination /extract

############################
# Stage 2: runtime
############################
FROM eclipse-temurin:17-jre-alpine@sha256:e2ba4e947bd5e236a9866fbdda03e4936036cb9e9d16ea0d84d103d6634a5c21 AS runtime

ARG VERSION=dev
ARG REVISION=unknown
LABEL org.opencontainers.image.title="releaseops-app" \
      org.opencontainers.image.description="Crewmeister challenge user API (Spring Boot)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}"

# Fixed, unprivileged, shell-less identity. Numeric so Kubernetes runAsNonRoot can verify it.
RUN addgroup -g 10001 -S app && adduser -u 10001 -S -G app -H -h /app -s /sbin/nologin app
WORKDIR /app

# Least-changing layers first. Each COPY is a separate layer, so a source-only change
# rebuilds only the tiny `application` layer.
COPY --from=build --chown=10001:10001 /extract/dependencies/ ./
COPY --from=build --chown=10001:10001 /extract/spring-boot-loader/ ./
COPY --from=build --chown=10001:10001 /extract/snapshot-dependencies/ ./
COPY --from=build --chown=10001:10001 /extract/application/ ./

USER 10001:10001
EXPOSE 8080

# - MaxRAMPercentage: size the heap from the container limit instead of the host's RAM.
# - ExitOnOutOfMemoryError: die and let the orchestrator restart, rather than limp on.
# - exec form + JarLauncher: java is PID 1, so SIGTERM reaches Spring's graceful shutdown.
ENV TZ=UTC
ENTRYPOINT ["java", \
  "-XX:MaxRAMPercentage=70.0", \
  "-XX:+ExitOnOutOfMemoryError", \
  "-Djava.security.egd=file:/dev/urandom", \
  "org.springframework.boot.loader.launch.JarLauncher"]

# Used by `docker run`/Compose. Kubernetes ignores HEALTHCHECK and uses its own probes.
# Readiness (includes the database) is the right signal for "can serve traffic".
HEALTHCHECK --interval=15s --timeout=3s --start-period=60s --retries=3 \
  CMD wget -q -O /dev/null "http://127.0.0.1:${MANAGEMENT_SERVER_PORT:-8080}/actuator/health/readiness" || exit 1
