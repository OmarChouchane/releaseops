#!/usr/bin/env bash
# Builds reports/out/release-report.{json,md} from recorded results; missing input = not-run, never a pass.
set -uo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

jf() { # jf <file> -> file content or a not-run marker
  [[ -s "$1" ]] && cat "$1" || echo '{"status":"not-run"}'
}

CHART_VERSION="$(awk '/^version:/{print $2}' "$CHART_DIR/Chart.yaml")"
APP_LIVE=null; K8S_VERSION=null; DEP_LIVE=null
if cluster_exists && k version >/dev/null 2>&1; then
  APP_LIVE="$(k -n "$NS_ARGOCD" get application "$APP_NAME" -o json 2>/dev/null | jq -c '{syncStatus:.status.sync.status, healthStatus:.status.health.status, revision:.status.sync.revision, source:.spec.source.repoURL, targetRevision:.spec.source.targetRevision, lastOperation:.status.operationState.phase}' 2>/dev/null || echo null)"
  K8S_VERSION="$(k version -o json 2>/dev/null | jq -c '{server:.serverVersion.gitVersion}' || echo null)"
  DEP_LIVE="$(k -n "$NS_APP" get deploy "$APP_NAME" -o json 2>/dev/null | jq -c '{image:.spec.template.spec.containers[0].image, desired:.spec.replicas, available:(.status.availableReplicas // 0), updated:(.status.updatedReplicas // 0), conditions:[.status.conditions[]? | {type,status,reason}]}' || echo null)"
fi
[[ -n "$APP_LIVE" ]] || APP_LIVE=null; [[ -n "$DEP_LIVE" ]] || DEP_LIVE=null

VERIF="$REPORT_DIR/verification-baseline.json"; [[ -s "$VERIF" ]] || VERIF="$REPORT_DIR/verification-release.json"
OUT="$REPORT_DIR/release-report.json"

jq -n \
  --arg at "$(now_iso)" --arg rev "$(git_rev)" --argjson dirty "$(git_dirty)" --arg chart "$CHART_VERSION" \
  --arg tf "$(terraform version 2>/dev/null | head -1)" --arg helm "$(helm version --short 2>/dev/null)" \
  --argjson build "$(jf "$STATE_DIR/build.json")" --argjson scan "$(jf "$STATE_DIR/scan.json")" \
  --argjson sbom "$(jf "$STATE_DIR/sbom.json")" --argjson image "$(jf "$STATE_DIR/image.json")" \
  --argjson verification "$(jf "$VERIF")" --argjson demo "$(jf "$REPORT_DIR/demo-result.json")" \
  --argjson argocd "$APP_LIVE" --argjson k8s "$K8S_VERSION" --argjson deployment "$DEP_LIVE" \
  '{generatedAt:$at,
    note:"Every value is read from a result recorded by the scripts that produced it. Anything not executed is marked not-run.",
    source:{workspaceRevision:$rev, uncommittedChanges:$dirty},
    tooling:{terraform:$tf, helm:$helm, kubernetes:$k8s},
    image:{repository:$image.repository, tag:$image.tag, digest:$image.digest, reference:$image.reference, publishedTo:$image.registry, gitopsCommit:$image.gitopsCommit},
    helmChart:{name:"releaseops", version:$chart},
    build:$build, vulnerabilityScan:$scan, sbom:$sbom,
    argocd:$argocd, kubernetesRollout:$deployment,
    releaseVerification:(if $verification.status=="not-run" then $verification else
        {result:$verification.result, summary:$verification.summary, checks:[$verification.checks[]|{name,status,detail}]} end),
    failureInjection:(if $demo.status=="not-run" then $demo else {scenario:$demo.scenario, badRevision:$demo.badRevision, secondsToDetectFailure:$demo.secondsToDetectFailure, badReleaseVerification:$demo.badReleaseVerification, serviceDuringBadRelease:$demo.serviceDuringBadRelease, prometheusAlert:$demo.prometheusAlert, driftSelfHeal:$demo.driftSelfHeal} end),
    recovery:(if $demo.status=="not-run" then $demo else {knownGoodRevision:$demo.knownGoodRevision, revertRevision:$demo.revertRevision, secondsToRecover:$demo.secondsToRecover, recoveryVerification:$demo.recoveryVerification, dataSurvival:$demo.dataSurvival, overall:$demo.status} end)}' >"$OUT"

# ------------------------------------------------------------------ Markdown
jq -r '
def badge(s): if s=="passed" or s=="pass" or s=="generated" then "✅ \(s)" elif s=="not-run" or s=="skipped" then "⚪ \(s)" else "❌ \(s)" end;
"# Release report\n",
"Generated \(.generatedAt) from workspace revision `\(.source.workspaceRevision)`\(if .source.uncommittedChanges then " (with uncommitted changes)" else "" end).\n",
"> \(.note)\n",
"## Artifact\n",
"| | |\n|---|---|",
"| Image | `\(.image.reference // "not-run")` |",
"| Tag | `\(.image.tag // "not-run")` |",
"| Digest | `\(.image.digest // "not-run")` |",
"| GitOps commit that pinned it | `\(.image.gitopsCommit // "n/a")` |",
"| Helm chart | releaseops `\(.helmChart.version)` |",
"| Kubernetes | \(.tooling.kubernetes.server // "n/a") |",
"| Terraform | \(.tooling.terraform) |\n",
"## Build and test\n",
"\(badge(.build.status)) — \(if .build.tests then "\(.build.tests) tests, \(.build.failures) failures, \(.build.errors) errors, \(.build.skipped) skipped in \(.build.durationSeconds)s" else (.build.reason // "no data") end)\n",
"## Supply chain\n",
"- Vulnerability scan: \(badge(.vulnerabilityScan.status)) — \(if .vulnerabilityScan.critical != null then "\(.vulnerabilityScan.critical) critical / \(.vulnerabilityScan.high) high fixable findings remaining; \(.vulnerabilityScan.acceptedExceptions // 0) CVE exception(s) accepted in .trivyignore.yaml (each justified and expiring); policy: \(.vulnerabilityScan.policy)" else "no data" end)",
"- SBOM: \(badge(.sbom.status)) — \(if .sbom.components then "\(.sbom.format), \(.sbom.components) components (`\(.sbom.file)`)" else "no data" end)\n",
"## GitOps and rollout\n",
"- Argo CD: sync **\(.argocd.syncStatus // "n/a")**, health **\(.argocd.healthStatus // "n/a")**, revision `\((.argocd.revision // "n/a")[0:12])`, source `\(.argocd.source // "n/a")`",
"- Deployment: \(.kubernetesRollout.available // "n/a")/\(.kubernetesRollout.desired // "n/a") available, image `\(.kubernetesRollout.image // "n/a")`\n",
"## Release verification\n",
(if .releaseVerification.checks then
  "Overall: \(badge(.releaseVerification.result)) (\(.releaseVerification.summary.passed) passed, \(.releaseVerification.summary.failed) failed, \(.releaseVerification.summary.skipped) skipped)\n",
  "| Check | Result | Detail |\n|---|---|---|",
  (.releaseVerification.checks[] | "| `\(.name)` | \(badge(.status)) | \(.detail | gsub("\n";" ") | .[0:160]) |")
else "⚪ not-run" end),
"\n## Failure injection (bad release)\n",
(if .failureInjection.scenario then
  "- Scenario: `\(.failureInjection.scenario)`; bad revision `\(.failureInjection.badRevision[0:12])`",
  "- Verification of the bad release: **\(.failureInjection.badReleaseVerification.result)** — detected \(.failureInjection.secondsToDetectFailure)s after the commit",
  (.failureInjection.badReleaseVerification.failedChecks[]? | "  - `\(.name)`: \(.detail | gsub("\n";" ") | .[0:200])"),
  "- Likely cause (heuristic from real diagnostics): \(.failureInjection.badReleaseVerification.likelyCause // "n/a")",
  "- Availability probe (GET /user?id=1 every 0.5s, from before the bad commit until recovery was verified): \(.failureInjection.serviceDuringBadRelease.requests) requests, \(.failureInjection.serviceDuringBadRelease.http200) returned HTTP 200, \(.failureInjection.serviceDuringBadRelease.notOk) not OK",
  (if .failureInjection.prometheusAlert then "- Monitoring: Prometheus alert `\(.failureInjection.prometheusAlert.alert)` final state during the failure: **\(.failureInjection.prometheusAlert.finalState)**" else empty end),
  (if .failureInjection.driftSelfHeal then "- Drift: \(.failureInjection.driftSelfHeal.change); self-healed=\(.failureInjection.driftSelfHeal.selfHealed) in \(.failureInjection.driftSelfHeal.secondsToHeal)s" else empty end)
else "⚪ not-run (`./run.sh demo`)" end),
"\n## Recovery (Git revert)\n",
(if .recovery.revertRevision then
  "- Known-good `\(.recovery.knownGoodRevision[0:12])` → revert commit `\(.recovery.revertRevision[0:12])`; recovered and re-verified in \(.recovery.secondsToRecover)s: \(badge(.recovery.recoveryVerification.result))",
  "- Data survival: record `\(.recovery.dataSurvival.canaryUser)` readable after recovery = \(.recovery.dataSurvival.readableAfterRecovery); MySQL pod untouched = \(.recovery.dataSurvival.mysqlPodUntouched)",
  "- Demo overall: \(badge(.recovery.overall))"
else "⚪ not-run" end)
' "$OUT" >"$REPORT_DIR/release-report.md"

ok "reports written: reports/out/release-report.json, reports/out/release-report.md"
