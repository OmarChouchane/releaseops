#!/usr/bin/env bash
# Bad-release demo: push a bad commit, detect it, git revert, verify, check the data survived.
#   demo.sh [--skip-drift]        DEMO_SCENARIO=bad-config (default) | bad-image
# Safe: MySQL is never touched; an EXIT trap restores the known-good state.
set -uo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/gitops.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitops.sh"

SKIP_DRIFT=0; [[ "${1:-}" == "--skip-drift" ]] && SKIP_DRIFT=1
SCENARIO="${DEMO_SCENARIO:-bad-config}"
RESULT_JSON="$REPORT_DIR/demo-result.json"
EVENTS="$(mktemp)"
BAD_PUSHED=0; REVERT_PUSHED=0; RECOVERED=0
PROBE_PID=""; PROBE_LOG="$(mktemp)"
T0=$SECONDS

ev() { # ev <phase> <status> <detail> -> timeline + console
  jq -nc --arg p "$1" --arg s "$2" --arg d "$3" --arg at "$(now_iso)" --argjson t "$((SECONDS - T0))" \
     '{phase:$p, status:$s, detail:$d, at:$at, elapsedSeconds:$t}' >>"$EVENTS"
  local c="$C_GRN"; [[ "$2" == fail || "$2" == detected ]] && c="$C_YEL"; [[ "$2" == error ]] && c="$C_RED"
  printf '    %s[%s]%s %s\n' "$c" "$2" "$C_OFF" "$3"
}
finish_json() { # finish_json <overall-status>
  jq -n --arg status "$1" --arg scenario "$SCENARIO" --arg mode "$GITOPS_MODE" --arg good "${GOOD_SHA:-}" --arg bad "${BAD_SHA:-}" \
        --arg rev "${REVERT_SHA:-}" --arg digest "${GOOD_DIGEST:-}" --arg at "$(now_iso)" \
        --argjson detect "${DETECT_SECONDS:-null}" --argjson recover "${RECOVER_SECONDS:-null}" \
        --argjson bv "$(cat "$REPORT_DIR/verification-demo-bad-release.json" 2>/dev/null || echo null)" \
        --argjson rv "$(cat "$REPORT_DIR/verification-demo-recovery.json" 2>/dev/null || echo null)" \
        --argjson data "${DATA_JSON:-null}" --argjson drift "${DRIFT_JSON:-null}" --argjson avail "${AVAIL_JSON:-null}" \
        --argjson alert "${ALERT_JSON:-null}" \
        --slurpfile timeline "$EVENTS" \
    '{status:$status, scenario:$scenario, gitopsMode:$mode, finishedAt:$at,
      knownGoodRevision:$good, badRevision:$bad, revertRevision:$rev, knownGoodImageDigest:$digest,
      secondsToDetectFailure:$detect, secondsToRecover:$recover,
      driftSelfHeal:$drift, serviceDuringBadRelease:$avail, prometheusAlert:$alert, dataSurvival:$data,
      badReleaseVerification:(if $bv then {result:$bv.result, summary:$bv.summary, failedChecks:[$bv.checks[]|select(.status=="fail")|{name,detail}], likelyCause:$bv.likelyCause} else null end),
      recoveryVerification:(if $rv then {result:$rv.result, summary:$rv.summary} else null end),
      diagnostics:($bv.diagnostics // null), timeline:$timeline}' >"$RESULT_JSON"
}

# Safety net: never leave the cluster on the bad revision.
restore_on_exit() {
  local rc=$?
  if [[ $BAD_PUSHED -eq 1 && $REVERT_PUSHED -eq 0 ]]; then
    warn "demo interrupted while the bad release was live - restoring the known-good state via Git"
    ( git -C "$WORKCLONE" "${GIT_IDENT[@]}" revert --no-edit "$BAD_SHA" >/dev/null 2>&1 && gitops_push && argocd_refresh \
        && ok "revert pushed; Argo CD will reconcile (check: ./run.sh status)" ) \
      || warn "could not auto-revert. Manually: git revert $BAD_SHA in the GitOps source and push."
  fi
  [[ -n "$PROBE_PID" ]] && kill "$PROBE_PID" 2>/dev/null
  gitops_close 2>/dev/null || true
  finish_json "$([[ $RECOVERED -eq 1 && $rc -eq 0 ]] && echo passed || echo failed)" 2>/dev/null || true
  rm -f "$EVENTS" "$PROBE_LOG"
}
trap restore_on_exit EXIT

api_get_status() { curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${APP_PORT}$1"; }

# ------------------------------------------------------------------ 0. preconditions
step "0/8  preconditions"
cluster_exists || die "no cluster. Run ./run.sh up first"
if [[ "$GITOPS_MODE" == remote ]]; then
  [[ "${DEMO_ALLOW_PUSH:-0}" == 1 ]] || die "GITOPS_MODE=remote: this demo pushes a bad commit AND its revert to $GITOPS_REPO_URL @ $GITOPS_BRANCH. Use a dedicated branch (GITOPS_BRANCH=demo) and confirm with DEMO_ALLOW_PUSH=1."
fi
gitops_open || die "cannot open the GitOps source"
git -C "$WORKCLONE" diff --quiet || die "the GitOps work clone has uncommitted changes ($WORKCLONE)"
"$ROOT/scripts/verify.sh" --label demo-baseline --wait 120 --no-monitoring >/dev/null \
  || die "the system is not healthy to begin with - refusing to start the demo. Run ./run.sh verify"
ev precondition pass "baseline verification passed; demo starts from a healthy system"

# ------------------------------------------------------------------ 1. known good
step "1/8  record the last known-good state"
GOOD_SHA="$(gitops_head)"; GOOD_DIGEST="$(values_get digest)"
[[ -n "$GOOD_DIGEST" ]] || die "no image is pinned yet (run ./run.sh deploy)"
POD_UID_BEFORE="$(k -n "$NS_APP" get pod "${APP_NAME}-mysql-0" -o jsonpath='{.metadata.uid}')"
CANARY="canary-$(date -u +%H%M%S)"
CANARY_LOC="$(curl -si -m 10 -X POST "http://127.0.0.1:${APP_PORT}/user" -H 'Content-Type: application/json' -d "{\"name\":\"$CANARY\"}" | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}')"
[[ -n "$CANARY_LOC" ]] || die "could not create the canary record"
ev known-good record "git ${GOOD_SHA:0:12}, image ${GOOD_DIGEST:0:19}…; canary user '$CANARY' stored at $CANARY_LOC; MySQL pod uid ${POD_UID_BEFORE:0:8}"

# ------------------------------------------------------------------ 2. drift
if [[ $SKIP_DRIFT -eq 0 ]]; then
  step "2/8  drift detection + self-heal (manual change to the cluster)"
  WANT="$(k -n "$NS_APP" get deploy "$APP_NAME" -o jsonpath='{.spec.replicas}')"
  k -n "$NS_APP" scale deploy "$APP_NAME" --replicas=$((WANT + 1)) >/dev/null
  d0=$SECONDS; seen_out=""; healed=""
  while ((SECONDS - d0 < 90)); do
    s="$(k -n "$NS_ARGOCD" get application "$APP_NAME" -o jsonpath='{.status.sync.status}' 2>/dev/null)"
    [[ "$s" == OutOfSync ]] && seen_out=yes
    r="$(k -n "$NS_APP" get deploy "$APP_NAME" -o jsonpath='{.spec.replicas}')"
    [[ "$r" == "$WANT" ]] && { healed=yes; break; }
    sleep 2
  done
  DRIFT_JSON="$(jq -nc --argjson w "$WANT" --argjson s "$((SECONDS - d0))" --arg seen "${seen_out:-no}" --arg healed "${healed:-no}" \
      '{change:"kubectl scale replicas \($w) -> \($w+1)", outOfSyncObserved:($seen=="yes"), selfHealed:($healed=="yes"), secondsToHeal:$s}')"
  [[ -n "$healed" ]] && ev drift pass "replicas $((WANT + 1)) reverted to $WANT by Argo CD in $((SECONDS - d0))s (OutOfSync observed: ${seen_out:-not caught - healed between polls})" \
                     || { ev drift fail "Argo CD did not revert the manual change within 90s"; k -n "$NS_APP" scale deploy "$APP_NAME" --replicas="$WANT" >/dev/null; }
else
  info "drift step skipped (--skip-drift)"
fi

# ------------------------------------------------------------------ 3. bad release
step "3/8  push a deliberately invalid release to Git (scenario: $SCENARIO)"
VALUES="$WORKCLONE/$ENV_VALUES_REL"
case "$SCENARIO" in
  bad-config)
    # A realistic mistake: typo in the database host
    printf '\n# DEMO: deliberately invalid - reverted by the demo\nconfig:\n  database:\n    host: releaseops-mysql-typo\n' >>"$VALUES"
    MSG="release (DEMO, intentionally broken): database host typo" ; EXPECT_FLAG=(--expect-digest "$GOOD_DIGEST") ;;
  bad-image)
    BAD_DIGEST="sha256:$(printf 'deadbeef%.0s' {1..8})"
    values_set_image "$(values_get repository)" "$BAD_DIGEST"
    MSG="release (DEMO, intentionally broken): image digest does not exist" ; EXPECT_FLAG=(--expect-digest "$BAD_DIGEST") ;;
  *) die "unknown DEMO_SCENARIO '$SCENARIO' (bad-config|bad-image)" ;;
esac
# Probe the API (2 req/s) from before the bad commit until recovery
( while :; do
    code="$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:${APP_PORT}/user?id=1")" || code=000
    echo "$code" >>"$PROBE_LOG"; sleep 0.5
  done ) &
PROBE_PID=$!
# Short progress deadline so the failure shows in about a minute
printf '\n# DEMO: short progress deadline so the failure is reported quickly\nprogressDeadlineSeconds: 60\n' >>"$VALUES"
gw add "$ENV_VALUES_REL"; gw commit -q -m "$MSG"; BAD_SHA="$(gitops_head)"; gitops_push; BAD_PUSHED=1
BAD_AT=$SECONDS
git -C "$WORKCLONE" --no-pager diff --stat "$GOOD_SHA" "$BAD_SHA" | sed 's/^/      /'
argocd_refresh
ev bad-release pushed "bad revision ${BAD_SHA:0:12} on top of known-good ${GOOD_SHA:0:12}"

# ------------------------------------------------------------------ 4/5. detect + explain
step "4/8  Argo CD observes it; release verification must FAIL"
if "$ROOT/scripts/verify.sh" --label demo-bad-release --wait 180 --no-monitoring --expect-revision "$BAD_SHA" "${EXPECT_FLAG[@]}"; then
  ev detection error "verification PASSED for a deliberately broken release - the failure injection did not work"
  die "unexpected: the bad release passed verification"
fi
DETECT_SECONDS=$((SECONDS - BAD_AT))
ev detection detected "failure detected ${DETECT_SECONDS}s after the bad commit"

# 4b. Wait (bounded) for the Prometheus alert to FIRE
PROM="http://127.0.0.1:${PROMETHEUS_PORT}"
if curl -fsS -m 5 "$PROM/-/ready" >/dev/null 2>&1; then
  step "4b/8  waiting for the Prometheus alert ReleaseOpsRolloutStuck to fire (bounded: 150s)"
  a0=$SECONDS; astate=""
  while ((SECONDS - a0 < 150)); do
    astate="$(curl -sS -m 5 "$PROM/api/v1/alerts" | jq -r '[.data.alerts[]? | select(.labels.alertname=="ReleaseOpsRolloutStuck") | .state] | first // ""')"
    [[ "$astate" == firing ]] && break
    sleep 5
  done
  ALERT_JSON="$(jq -nc --arg s "${astate:-not-seen}" --argjson t "$((SECONDS - a0))" '{alert:"ReleaseOpsRolloutStuck", finalState:$s, secondsWaited:$t}')"
  if [[ "$astate" == firing ]]; then ev alert pass "ReleaseOpsRolloutStuck is FIRING in Prometheus (${SECONDS}s into the demo; waited $((SECONDS - a0))s)"
  else ev alert fail "ReleaseOpsRolloutStuck did not reach 'firing' within 150s (state: ${astate:-not seen})"; fi
else
  ALERT_JSON='{"alert":"ReleaseOpsRolloutStuck","finalState":"skipped","reason":"Prometheus not reachable"}'
  ev alert skipped "Prometheus not reachable at $PROM - alert not checked"
fi

step "5/8  diagnosis"
CAUSE="$(jq -r '.likelyCause // "unknown"' "$REPORT_DIR/verification-demo-bad-release.json")"
ev diagnosis info "$CAUSE"

# ------------------------------------------------------------------ 6/7. recover through Git
step "6/8  roll back with Git (revert the bad commit)"
REC_AT=$SECONDS
gw revert --no-edit "$BAD_SHA" >/dev/null || die "git revert failed"
REVERT_SHA="$(gitops_head)"; gitops_push; argocd_refresh
REVERT_PUSHED=1
ev rollback pushed "revert commit ${REVERT_SHA:0:12} restores the desired state of ${GOOD_SHA:0:12}"

step "7/8  Argo CD reconciles the known-good state; verify again"
if "$ROOT/scripts/verify.sh" --label demo-recovery --wait 300 --no-monitoring --expect-revision "$REVERT_SHA" --expect-digest "$GOOD_DIGEST"; then
  RECOVERED=1; RECOVER_SECONDS=$((SECONDS - REC_AT))
  kill "$PROBE_PID" 2>/dev/null; PROBE_PID=""
  total=$(wc -l <"$PROBE_LOG"); okc=$(grep -c '^200$' "$PROBE_LOG" || true)
  AVAIL_JSON="$(jq -nc --argjson t "$total" --argjson o "$okc" '{probe:"GET /user?id=1 every 0.5s from just before the bad commit until recovery was verified", requests:$t, http200:$o, notOk:($t-$o), note:"maxUnavailable=0: the previous ReplicaSet keeps serving while the new pods are not Ready"}')"
  if [[ "$okc" == "$total" && "$total" -gt 0 ]]; then ev availability pass "$okc/$total probe requests returned HTTP 200 across the bad release and the recovery (no user-visible downtime)"
  else ev availability fail "$((total - okc)) of $total probe requests were not HTTP 200 during the bad release/recovery"; fi
  ev recovery pass "all checks pass again ${RECOVER_SECONDS}s after the revert"
else
  ev recovery fail "verification still failing after the revert - see output above"; exit 1
fi

# ------------------------------------------------------------------ 8. data survival
step "8/8  data survival"
body="$(curl -s -m 10 "http://127.0.0.1:${APP_PORT}${CANARY_LOC}")"
POD_UID_AFTER="$(k -n "$NS_APP" get pod "${APP_NAME}-mysql-0" -o jsonpath='{.metadata.uid}')"
ok_canary=false; [[ "$body" == "Greetings from Crewmeister, ${CANARY}!" ]] && ok_canary=true
same_pod=false; [[ "$POD_UID_BEFORE" == "$POD_UID_AFTER" ]] && same_pod=true
DATA_JSON="$(jq -nc --arg n "$CANARY" --arg loc "$CANARY_LOC" --argjson ok "$ok_canary" --argjson same "$same_pod" \
   '{canaryUser:$n, canaryLocation:$loc, readableAfterRecovery:$ok, mysqlPodUntouched:$same}')"
if $ok_canary && $same_pod; then ev data pass "record '$CANARY' created BEFORE the bad release is still readable; the MySQL pod was never restarted"
else ev data fail "canary readable=$ok_canary, mysqlPodUntouched=$same_pod (body: $body)"; exit 1; fi

echo; printf '%s✔ DEMO COMPLETE%s  detected in %ss, recovered in %ss, no data lost.  Evidence: reports/out/demo-result.json\n' "$C_GRN" "$C_OFF" "$DETECT_SECONDS" "$RECOVER_SECONDS"
exit 0
