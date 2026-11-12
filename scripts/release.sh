#!/usr/bin/env bash
# Local equivalent of the CI pipeline: test -> build -> scan -> SBOM -> push (digest) -> pin in Git.
# Subcommands: test | build | scan | sbom | publish | pin | all
# Every step records what REALLY happened in .releaseops/*.json; reports are built from those files.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/gitops.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitops.sh"

BUILD_JSON="$STATE_DIR/build.json"
IMAGE_JSON="$STATE_DIR/image.json"
SCAN_JSON="$STATE_DIR/scan.json"
SBOM_JSON="$STATE_DIR/sbom.json"
LOCAL_IMAGE="releaseops-app:local"

cmd_test() {
  step "maven tests (unit + Testcontainers/MySQL integration)"
  local start=$SECONDS rc=0
  (cd "$ROOT" && ./mvnw -B -ntp verify) >"$STATE_DIR/maven.log" 2>&1 || rc=$?
  # Totals come from surefire's XML, not from scraping console output.
  local t=0 f=0 e=0 s=0 x
  for x in "$ROOT"/target/surefire-reports/TEST-*.xml; do
    [[ -f "$x" ]] || continue
    t=$((t + $(grep -o 'tests="[0-9]*"' "$x" | head -1 | tr -dc 0-9)))
    f=$((f + $(grep -o 'failures="[0-9]*"' "$x" | head -1 | tr -dc 0-9)))
    e=$((e + $(grep -o 'errors="[0-9]*"' "$x" | head -1 | tr -dc 0-9)))
    s=$((s + $(grep -o 'skipped="[0-9]*"' "$x" | head -1 | tr -dc 0-9)))
  done
  jq -n --arg st "$([[ $rc -eq 0 ]] && echo passed || echo failed)" --argjson t "$t" --argjson f "$f" --argjson e "$e" --argjson s "$s" \
        --argjson d "$((SECONDS - start))" --arg at "$(now_iso)" --arg rev "$(git_rev)" \
     '{status:$st, tests:$t, failures:$f, errors:$e, skipped:$s, durationSeconds:$d, finishedAt:$at, gitRevision:$rev, log:".releaseops/maven.log"}' >"$BUILD_JSON"
  if [[ $rc -ne 0 ]]; then tail -40 "$STATE_DIR/maven.log" >&2; die "tests failed ($f failures, $e errors) - see $STATE_DIR/maven.log"; fi
  ok "tests passed: $t run, $f failures, $e errors, $s skipped"
}

cmd_build() {
  step "docker build $LOCAL_IMAGE"
  local rev; rev="$(git_rev)$([[ "$(git_dirty)" == true ]] && echo -dirty || true)"
  DOCKER_BUILDKIT=1 docker build -q -t "$LOCAL_IMAGE" --build-arg VERSION="$rev" --build-arg REVISION="$(git_rev)" "$ROOT" >/dev/null
  ok "built $LOCAL_IMAGE ($(docker image inspect "$LOCAL_IMAGE" --format '{{.Size}}' | awk '{printf "%.0f MB", $1/1e6}'))"
}

trivy() { # trivy <args...>: pinned scanner image; cache volume is project-scoped
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v releaseops-trivy-cache:/root/.cache \
    -v "$REPORT_DIR:/out" -v "$ROOT/.trivyignore.yaml:/work/.trivyignore.yaml:ro" -w /work "$TRIVY_IMAGE" "$@"
}

cmd_scan() {
  step "trivy: vulnerability scan (HIGH,CRITICAL, fixable only)"
  [[ -f "$ROOT/.trivyignore.yaml" ]] || echo 'vulnerabilities: []' >"$ROOT/.trivyignore.yaml"
  trivy image --quiet --ignorefile /work/.trivyignore.yaml --format json --output /out/trivy-image.json --severity HIGH,CRITICAL --ignore-unfixed "$LOCAL_IMAGE" >/dev/null
  local crit high
  crit="$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$REPORT_DIR/trivy-image.json")"
  high="$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$REPORT_DIR/trivy-image.json")"
  local excepted; excepted="$(grep -c '^  - id:' "$ROOT/.trivyignore.yaml" || true)"
  jq -n --arg st "$([[ $((crit + high)) -eq 0 ]] && echo passed || echo failed)" --argjson c "$crit" --argjson h "$high" --argjson ex "${excepted:-0}" \
        --arg tool "$TRIVY_IMAGE" --arg at "$(now_iso)" \
     '{status:$st, tool:$tool, policy:"fail on fixable HIGH/CRITICAL; .trivyignore.yaml entries need a statement and an expiry date",
       critical:$c, high:$h, acceptedExceptions:$ex, finishedAt:$at, report:"reports/out/trivy-image.json"}' >"$SCAN_JSON"
  if [[ $((crit + high)) -ne 0 ]]; then
    trivy image --quiet --ignorefile /work/.trivyignore.yaml --severity HIGH,CRITICAL --ignore-unfixed "$LOCAL_IMAGE" >&2 || true
    die "scan failed: $crit critical, $high high fixable vulnerabilities"
  fi
  ok "no fixable HIGH/CRITICAL vulnerabilities left (${excepted:-0} justified, expiring exception(s) in .trivyignore.yaml)"
}

cmd_sbom() {
  step "trivy: SBOM (CycloneDX)"
  trivy image --quiet --format cyclonedx --output /out/sbom.cdx.json "$LOCAL_IMAGE" >/dev/null
  jq -n --arg f "reports/out/sbom.cdx.json" --argjson n "$(jq '.components | length' "$REPORT_DIR/sbom.cdx.json")" --arg at "$(now_iso)" \
     '{status:"generated", format:"CycloneDX JSON", file:$f, components:$n, finishedAt:$at}' >"$SBOM_JSON"
  ok "SBOM with $(jq .components "$SBOM_JSON") components -> reports/out/sbom.cdx.json"
}

cmd_publish() {
  need docker
  local rev tag out digest repo; repo="$(registry_ref)"
  rev="$(git_rev)$([[ "$(git_dirty)" == true ]] && echo -dirty || true)"
  tag="${rev}-$(date -u +%Y%m%d%H%M%S)"
  step "pushing $repo:$tag"
  docker tag "$LOCAL_IMAGE" "$repo:$tag"
  out="$(docker push "$repo:$tag" 2>&1)" || { echo "$out" >&2; die "push failed - is the registry up? (./run.sh doctor)"; }
  digest="$(grep -o 'digest: sha256:[a-f0-9]\{64\}' <<<"$out" | tail -1 | awk '{print $2}')"
  [[ -n "$digest" ]] || die "could not determine the pushed digest"
  jq -n --arg r "$repo" --arg t "$tag" --arg d "$digest" --arg rev "$(git_rev)" --arg at "$(now_iso)" \
     '{repository:$r, tag:$t, digest:$d, reference:($r+"@"+$d), gitRevision:$rev, publishedAt:$at, registry:"local (kind) registry"}' >"$IMAGE_JSON"
  ok "immutable reference: $repo@$digest"
}

cmd_pin() { # commit the new digest to the GitOps source; Argo CD does the rest
  [[ -f "$IMAGE_JSON" ]] || die "nothing published yet (run: ./run.sh release)"
  local repo digest
  repo="$(jq -r .repository "$IMAGE_JSON")"; digest="$(jq -r .digest "$IMAGE_JSON")"
  step "GitOps: pin $repo@${digest:0:19}… in $ENV_VALUES_REL"
  gitops_open
  trap gitops_close EXIT
  values_set_image "$repo" "$digest"
  if gw diff --quiet; then ok "desired state already pins this digest"; else
    gw add "$ENV_VALUES_REL"
    gw commit -q -m "release: pin app image ${digest:0:19} (workspace $(git_rev))"
    gitops_push
    ok "committed $(gitops_head | cut -c1-12) to the GitOps source"
  fi
  jq --arg c "$(gitops_head)" '. + {gitopsCommit:$c}' "$IMAGE_JSON" >"$IMAGE_JSON.tmp" && mv "$IMAGE_JSON.tmp" "$IMAGE_JSON"
  argocd_refresh
}

cmd_all() {
  [[ "${SKIP_TESTS:-0}" == 1 ]] && warn "SKIP_TESTS=1: tests NOT run (recorded as skipped in the report)" \
    && jq -n --arg at "$(now_iso)" '{status:"skipped", reason:"SKIP_TESTS=1", finishedAt:$at}' >"$BUILD_JSON" || cmd_test
  cmd_build
  cmd_scan
  cmd_sbom
  cmd_publish
  cmd_pin
}

case "${1:-all}" in
  test) cmd_test ;; build) cmd_build ;; scan) cmd_scan ;; sbom) cmd_sbom ;;
  publish) cmd_publish ;; pin) cmd_pin ;; all) cmd_all ;;
  *) die "usage: release.sh test|build|scan|sbom|publish|pin|all" ;;
esac
