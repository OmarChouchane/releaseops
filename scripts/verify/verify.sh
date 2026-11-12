#!/usr/bin/env bash
# Release verification: passes only if EVERY check passes (skips are never passes).
#   verify.sh [--label NAME] [--wait SECONDS] [--expect-digest sha256:...] [--expect-revision GIT_SHA]
#             [--no-monitoring]
# Exit 0 = all passed, 1 = at least one failed. JSON: reports/out/verification-<label>.json
set -uo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

LABEL="release"; WAIT=240; EXPECT_DIGEST=""; EXPECT_REV=""; MONITORING=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2 ;;
    --wait) WAIT="$2"; shift 2 ;;
    --expect-digest) EXPECT_DIGEST="$2"; shift 2 ;;
    --expect-revision) EXPECT_REV="$2"; shift 2 ;;
    --no-monitoring) MONITORING=0; shift ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ -z "$EXPECT_DIGEST" && -f "$STATE_DIR/image.json" ]] && EXPECT_DIGEST="$(jq -r .digest "$STATE_DIR/image.json")"

DEADLINE=$((SECONDS + WAIT))
RUN_ID="$(date -u +%Y%m%d%H%M%S)-$RANDOM"
OUT_JSON="$REPORT_DIR/verification-${LABEL}.json"
CHECKS="$(mktemp)"; trap 'rm -f "$CHECKS"; [[ -n "${PF_PID:-}" ]] && kill "$PF_PID" 2>/dev/null' EXIT
FAILED=0; PASSED=0; SKIPPED=0
SELECTOR="app.kubernetes.io/instance=${APP_NAME},app.kubernetes.io/component=app"
MYSQL_SELECTOR="app.kubernetes.io/instance=${APP_NAME},app.kubernetes.io/component=mysql"

remaining() { local r=$((DEADLINE - SECONDS)); ((r < 5)) && r=5; echo "$r"; }

# run_check <name> <description> <function>; the function returns 0=pass, 1=fail, 2=skip
run_check() {
  local name="$1" desc="$2" fn="$3" start=$SECONDS detail rc status
  detail="$($fn 2>&1)"; rc=$?
  case $rc in 0) status=pass; PASSED=$((PASSED + 1)) ;; 2) status=skipped; SKIPPED=$((SKIPPED + 1)) ;; *) status=fail; FAILED=$((FAILED + 1)) ;; esac
  jq -nc --arg n "$name" --arg d "$desc" --arg s "$status" --arg detail "$detail" --argjson dur "$((SECONDS - start))" \
     '{name:$n, description:$d, status:$s, detail:$detail, durationSeconds:$dur}' >>"$CHECKS"
  local mark="${C_GRN}PASS${C_OFF}"; [[ $status == fail ]] && mark="${C_RED}FAIL${C_OFF}"; [[ $status == skipped ]] && mark="${C_YEL}SKIP${C_OFF}"
  printf '  [%s] %-22s %s\n' "$mark" "$name" "$(head -c 200 <<<"$detail" | head -1)"
}

app_json() { k -n "$NS_ARGOCD" get application "$APP_NAME" -o json 2>/dev/null; }
dep_json() { k -n "$NS_APP" get deploy "$APP_NAME" -o json 2>/dev/null; }

# ------------------------------------------------------------------ checks
c_argocd_sync() {
  local j s rev op
  until j="$(app_json)" && s="$(jq -r '.status.sync.status // "Unknown"' <<<"$j")" \
        && rev="$(jq -r '.status.sync.revision // ""' <<<"$j")" && op="$(jq -r '.status.operationState.phase // "None"' <<<"$j")" \
        && [[ "$s" == Synced && ( -z "$EXPECT_REV" || "$rev" == "$EXPECT_REV"* ) && "$op" != Running ]]; do
    ((SECONDS >= DEADLINE)) && { echo "sync=$s revision=${rev:0:12} operation=$op expectedRevision=${EXPECT_REV:0:12} after ${WAIT}s: $(jq -r '[.status.conditions[]?.message] | join("; ")' <<<"$j")"; return 1; }
    sleep 3
  done
  echo "Synced at revision ${rev:0:12} (last operation: $op)"
}

c_argocd_health() {
  local j h
  until j="$(app_json)" && h="$(jq -r '.status.health.status // "Unknown"' <<<"$j")" && [[ "$h" == Healthy ]]; do
    # Degraded is a final verdict, stop waiting
    if [[ "$h" == Degraded ]] || ((SECONDS >= DEADLINE)); then
      echo "health=$h: $(jq -r '[.status.resources[]? | select(.health.status != null and .health.status != "Healthy") | "\(.kind)/\(.name)=\(.health.status)"] | join(", ")' <<<"$j") $(dep_json | jq -r '[.status.conditions[]? | select(.type=="Progressing" and .status!="True") | "Deployment Progressing=False (\(.reason))"] | join(", ")')"; return 1
    fi
    sleep 3
  done
  echo "Healthy"
}

# Child manifests of an image index (identical rebuilds get new index digests)
index_children() { # index_children <repository-ref> <index-digest>
  local ref="$1" dig="$2" host path
  host="${ref%%/*}"; path="${ref#*/}"
  [[ "$host" == "localhost:${REGISTRY_PORT}" ]] || return 0
  curl -fsS -m 5 -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    "http://127.0.0.1:${REGISTRY_PORT}/v2/${path}/manifests/${dig}" 2>/dev/null \
    | jq -r '.manifests[]? | select((.platform.os // "") != "unknown") | .digest'   # real images only, not attestations
}

c_image() {
  [[ -n "$EXPECT_DIGEST" ]] || { echo "no expected digest known (nothing released from this workspace yet)"; return 2; }
  local spec repo live p n=0 pname pspec pid d note="" children
  spec="$(dep_json | jq -r '.spec.template.spec.containers[0].image')"
  [[ "$spec" == *"@$EXPECT_DIGEST" ]] || { echo "Deployment image is '$spec', expected digest $EXPECT_DIGEST"; return 1; }
  repo="${spec%@*}"
  children="$(index_children "$repo" "$EXPECT_DIGEST")"
  live="$(k -n "$NS_APP" get pods -l "$SELECTOR" -o json | jq -c '.items[] | select(.status.phase=="Running" and .metadata.deletionTimestamp==null) | {n:.metadata.name, spec:.spec.containers[0].image, id:.status.containerStatuses[0].imageID}')"
  [[ -n "$live" ]] || { echo "no running pods to compare against (spec pins ${EXPECT_DIGEST:0:19})"; return 1; }
  while IFS= read -r p; do
    n=$((n + 1))
    pname="$(jq -r .n <<<"$p")"; pspec="$(jq -r .spec <<<"$p")"; pid="$(jq -r .id <<<"$p")"; d="${pid##*@}"
    # 1) the pod was created from the expected release
    [[ "$pspec" == *"@$EXPECT_DIGEST" ]] || { echo "pod $pname was created from '$pspec', expected ...@$EXPECT_DIGEST"; return 1; }
    # 2) the kubelet pulled the expected digest or a child of that index
    if [[ "$d" == "$EXPECT_DIGEST" ]]; then :
    elif [[ -n "$children" ]] && { grep -qx "$d" <<<"$children" || grep -qxFf <(echo "$children") <(index_children "$repo" "$d"); }; then
      # Same platform image under another index digest (identical rebuild)
      note=" (runtime reports ${d:0:15}…: another index holding the identical platform image)"
    else echo "pod $pname runs image ID '$pid', which is neither the expected digest nor provably the same image"; return 1; fi
  done <<<"$live"
  echo "Deployment and $n running pod(s) pin ${EXPECT_DIGEST:0:19}…$note"
}

c_rollout() {
  local j want upd avail ready gen obs reason total
  while :; do
    j="$(dep_json)"; [[ -n "$j" ]] || { echo "deployment $APP_NAME not found"; return 1; }
    want="$(jq .spec.replicas <<<"$j")"; upd="$(jq '.status.updatedReplicas // 0' <<<"$j")"; avail="$(jq '.status.availableReplicas // 0' <<<"$j")"
    ready="$(jq '.status.readyReplicas // 0' <<<"$j")"; gen="$(jq .metadata.generation <<<"$j")"; obs="$(jq '.status.observedGeneration // 0' <<<"$j")"
    reason="$(jq -r '.status.conditions[]? | select(.type=="Progressing") | .reason' <<<"$j")"
    total="$(jq '.status.replicas // 0' <<<"$j")"
    if [[ "$obs" -ge "$gen" && "$upd" == "$want" && "$avail" == "$want" && "$total" == "$want" ]]; then
      echo "rollout complete: $avail/$want available, all updated (reason=$reason)"; return 0
    fi
    [[ "$reason" == ProgressDeadlineExceeded ]] && { echo "ProgressDeadlineExceeded: updated=$upd available=$avail/$want total=$total"; return 1; }
    ((SECONDS >= DEADLINE)) && { echo "rollout not complete after ${WAIT}s: updated=$upd ready=$ready available=$avail desired=$want total=$total reason=$reason"; return 1; }
    sleep 3
  done
}

c_pods() {
  local app notready mysql
  # Ignore pods already being deleted (old ReplicaSet after a rollback)
  notready="$(k -n "$NS_APP" get pods -l "$SELECTOR" -o json | jq -r '[.items[] | select(.metadata.deletionTimestamp==null) | select(([.status.conditions[]? | select(.type=="Ready" and .status=="True")] | length) == 0) | .metadata.name] | join(",")')"
  [[ -z "$notready" ]] || { echo "pods not Ready: $notready"; return 1; }
  app="$(k -n "$NS_APP" get pods -l "$SELECTOR" -o json | jq '[.items[] | select(.metadata.deletionTimestamp==null)] | length')"
  mysql="$(k -n "$NS_APP" get pods -l "$MYSQL_SELECTOR" -o json | jq -r '[.items[] | select(.status.containerStatuses[0].ready==true)] | length')"
  [[ "$mysql" -ge 1 ]] || { echo "MySQL pod is not Ready"; return 1; }
  echo "$app app pod(s) and $mysql MySQL pod Ready"
}

c_restarts() {
  local n
  n="$(k -n "$NS_APP" get pods -l "app.kubernetes.io/instance=${APP_NAME}" -o json | jq '[.items[] | select(.metadata.deletionTimestamp==null) | .status.containerStatuses[]?.restartCount] | add // 0')"
  [[ "$n" -le "${MAX_RESTARTS:-2}" ]] || { echo "$n container restarts (limit ${MAX_RESTARTS:-2})"; return 1; }
  echo "$n container restart(s) since the pods started"
}

c_health() {
  local pod body
  pod="$(k -n "$NS_APP" get pods -l "$SELECTOR" -o json | jq -r '[.items[] | select(.status.phase=="Running" and .metadata.deletionTimestamp==null and ([.status.conditions[]? | select(.type=="Ready" and .status=="True")] | length) > 0)][0].metadata.name // empty')"
  [[ -n "$pod" ]] || { echo "no running application pod"; return 1; }
  # The management port is not in the Service: go through the pod
  body="$(k -n "$NS_APP" exec "$pod" -c app -- wget -q -T 5 -O- "http://127.0.0.1:8081/actuator/health" 2>&1)" || { echo "health request failed: $body"; return 1; }
  [[ "$(jq -r .status <<<"$body")" == UP && "$(jq -r .components.db.status <<<"$body")" == UP ]] \
    || { echo "unhealthy: $(jq -c '{status, db:.components.db.status}' <<<"$body" 2>/dev/null || echo "$body")"; return 1; }
  echo "status=UP db=UP (pod $pod)"
}

# API checks go through the Service, like real clients
api() { curl -sS -m 10 "$@"; }
c_api_post() {
  local name="verify-${RUN_ID}" hdr body code loc
  hdr="$(mktemp)"
  body="$(api -D "$hdr" -o - -X POST "$API_URL/user" -H 'Content-Type: application/json' -d "{\"name\":\"$name\"}")" || { echo "POST failed: $body"; rm -f "$hdr"; return 1; }
  code="$(awk 'NR==1{print $2}' "$hdr")"; loc="$(grep -i '^location:' "$hdr" | tr -d '\r' | awk '{print $2}')"; rm -f "$hdr"
  [[ "$code" == 200 ]] || { echo "POST /user returned HTTP $code: $body"; return 1; }
  [[ "$body" == "Greetings from Crewmeister, ${name}!" ]] || { echo "unexpected POST body: $body"; return 1; }
  [[ -n "$loc" ]] || { echo "response has no Location header"; return 1; }
  echo "$loc" >"$STATE_DIR/.verify-location"; echo "$name" >"$STATE_DIR/.verify-name"
  echo "HTTP 200, created $name at $loc"
}
c_api_get() {
  local loc name body
  loc="$(cat "$STATE_DIR/.verify-location" 2>/dev/null)"; name="$(cat "$STATE_DIR/.verify-name" 2>/dev/null)"
  [[ -n "$loc" ]] || { echo "POST did not succeed, nothing to read back"; return 1; }
  body="$(api "$API_URL$loc")" || { echo "GET failed: $body"; return 1; }
  [[ "$body" == "Greetings from Crewmeister, ${name}!" ]] || { echo "GET $loc returned: $body"; return 1; }
  echo "GET $loc -> \"$body\""
}

mysql_q() { # mysql_q <sql>: run as root INSIDE the MySQL pod; the password never leaves the pod
  k -n "$NS_APP" exec "sts/${APP_NAME}-mysql" -c mysql -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B -e "$1" 2>/dev/null' _ "$1"
}
c_db_row() {
  local loc id name got
  loc="$(cat "$STATE_DIR/.verify-location" 2>/dev/null)"; name="$(cat "$STATE_DIR/.verify-name" 2>/dev/null)"; id="${loc##*=}"
  [[ "$id" =~ ^[0-9]+$ ]] || { echo "no created record to look for"; return 1; }
  got="$(mysql_q "SELECT name FROM challenge.user WHERE id=${id}")" || { echo "could not query MySQL"; return 1; }
  [[ "$got" == "$name" ]] || { echo "row id=$id has name '$got', expected '$name'"; return 1; }
  echo "row id=$id found directly in MySQL with name '$got' (persisted, not just echoed)"
}
c_flyway() {
  local n
  n="$(mysql_q "SELECT COUNT(*) FROM challenge.flyway_schema_history WHERE success=1")" || { echo "could not query flyway history"; return 1; }
  [[ "${n:-0}" -ge 1 ]] || { echo "no successful Flyway migration recorded"; return 1; }
  echo "$n successful Flyway migration(s) recorded"
}

PROM_URL="http://127.0.0.1:${PROMETHEUS_PORT}"
prom() { curl -sS -m 10 -G "$PROM_URL/api/v1/query" --data-urlencode "query=$1"; }
c_monitoring() {
  [[ "$MONITORING" == 1 ]] || { echo "disabled (--no-monitoring)"; return 2; }
  curl -fsS -m 5 "$PROM_URL/-/ready" >/dev/null 2>&1 || { echo "Prometheus not reachable at $PROM_URL"; return 2; }
  local up want dbup end=$((SECONDS + 90))
  want="$(dep_json | jq .spec.replicas)"
  while :; do
    up="$(prom "sum(up{namespace=\"$NS_APP\",container=\"app\"})" | jq -r '.data.result[0].value[1] // "0"')"
    dbup="$(prom "min(app_database_up{namespace=\"$NS_APP\"})" | jq -r '.data.result[0].value[1] // "none"')"
    [[ "${up%.*}" == "$want" && "$dbup" == 1 ]] && break
    ((SECONDS >= end)) && { echo "Prometheus sees up=$up/$want app_database_up=$dbup"; return 1; }
    sleep 5
  done
  echo "Prometheus scrapes $up/$want app targets; app_database_up=1"
}

# ------------------------------------------------------------------ diagnostics (only on failure)
diagnostics() {
  echo "### Argo CD application"
  app_json | jq -r '"sync=\(.status.sync.status) health=\(.status.health.status) revision=\(.status.sync.revision // "-")", (.status.conditions[]? | "condition \(.type): \(.message)"), (.status.operationState | if . then "operation \(.phase): \(.message)" else empty end)'
  echo; echo "### Deployment"
  dep_json | jq -r '.status.conditions[]? | "\(.type)=\(.status) reason=\(.reason): \(.message)"'
  echo; echo "### Pods"
  k -n "$NS_APP" get pods -o wide 2>&1
  local pod
  for pod in $(k -n "$NS_APP" get pods -l "$SELECTOR" -o json | jq -r '.items[] | select(([.status.conditions[]? | select(.type=="Ready" and .status=="True")] | length) == 0) | .metadata.name'); do
    echo; echo "### $pod: container state"
    k -n "$NS_APP" get pod "$pod" -o json | jq -r '.status.containerStatuses[]? | "waiting=\(.state.waiting.reason // "-") lastTerminated=\(.lastState.terminated.reason // "-") exitCode=\(.lastState.terminated.exitCode // "-") restarts=\(.restartCount)"'
    echo "### $pod: events"
    k -n "$NS_APP" get events --field-selector "involvedObject.name=$pod" --sort-by=.lastTimestamp 2>&1 | tail -6
    echo "### $pod: application log (errors)"
    { k -n "$NS_APP" logs "$pod" -c app --tail=300 2>&1; k -n "$NS_APP" logs "$pod" -c app --previous --tail=300 2>&1; } \
      | grep -E "Caused by|ERROR|UnknownHost|Access denied|Communications link|Unable to obtain connection|APPLICATION FAILED" | sort -u | head -8
  done
}

root_cause() { # heuristic, labelled as such
  local d="$1"
  grep -q "UnknownHostException" <<<"$d" && { echo "the application cannot resolve its database host (UnknownHostException) - check config.database.host"; return; }
  grep -qE "Access denied" <<<"$d" && { echo "MySQL rejected the application credentials (Access denied)"; return; }
  grep -qE "ErrImagePull|ImagePullBackOff|manifest unknown|not found" <<<"$d" && { echo "the image cannot be pulled (ErrImagePull/ImagePullBackOff) - wrong or missing digest"; return; }
  grep -qE "Communications link|Connection refused" <<<"$d" && { echo "the application cannot connect to MySQL (connection refused / link failure)"; return; }
  grep -q "ProgressDeadlineExceeded" <<<"$d" && { echo "the rollout exceeded its progress deadline; new pods never became Ready"; return; }
  echo "no known signature matched - read the diagnostics above"
}

# ------------------------------------------------------------------ main
step "verifying release '$LABEL' (waiting up to ${WAIT}s for convergence)"
need kubectl; need jq; need curl
[[ -n "$EXPECT_DIGEST" ]] && info "expected image digest: $EXPECT_DIGEST" || warn "no expected digest: the image check will be skipped"
[[ -n "$EXPECT_REV" ]] && info "expected GitOps revision: ${EXPECT_REV:0:12}"

# Reach the Service via NodePort, else a temporary port-forward
wait_http() { # wait_http <url> <seconds>: any HTTP response counts as "reachable"
  local end=$((SECONDS + $2))
  until curl -s -m 3 -o /dev/null "$1"; do ((SECONDS >= end)) && return 1; sleep 2; done
}
API_URL="http://127.0.0.1:${APP_PORT}"
ensure_api() {
  wait_http "$API_URL/user?id=1" 45 && return 0
  warn "NodePort $API_URL not reachable after 45s - falling back to a port-forward to the Service"
  local p=$((20000 + RANDOM % 20000))
  # call kubectl directly so $! is its real PID
  kubectl --context "$KIND_CONTEXT" -n "$NS_APP" port-forward "svc/$APP_NAME" "$p:8080" >/dev/null 2>&1 & PF_PID=$!
  API_URL="http://127.0.0.1:$p"
  wait_http "$API_URL/user?id=1" 30 || warn "the API is not reachable through the port-forward either; the api.* checks will fail"
}

run_check argocd.sync      "Argo CD Application is Synced to the expected revision" c_argocd_sync
run_check argocd.health    "Argo CD reports the Application Healthy"                c_argocd_health
run_check image.expected   "Deployment and running pods use the expected digest"    c_image
run_check k8s.rollout      "Deployment rollout completed (updated = available = desired)" c_rollout
run_check k8s.pods         "All application pods and MySQL are Ready"               c_pods
run_check k8s.restarts     "No restart loop"                                        c_restarts
run_check app.health       "Actuator health UP, including the database component"   c_health
ensure_api   # not a check: resolves how the API is reached, now that the pods have had their chance to become Ready
run_check api.post         "POST /user creates a user (200, greeting, Location)"    c_api_post
run_check api.get          "GET /user?id=<new id> returns the created user"         c_api_get
run_check db.persistence   "The created row exists in MySQL (queried directly)"     c_db_row
run_check db.migrations    "Flyway migrations applied successfully"                 c_flyway
run_check monitoring.scrape "Prometheus scrapes every replica; app_database_up=1"   c_monitoring

RESULT=passed; [[ $FAILED -gt 0 ]] && RESULT=failed
DIAG=""; ROOT_CAUSE=""
if [[ $FAILED -gt 0 ]]; then
  echo; step "diagnostics"
  DIAG="$(diagnostics 2>&1)"; echo "$DIAG" | sed 's/^/    /'
  ROOT_CAUSE="$(root_cause "$DIAG$(jq -r 'select(.status=="fail") | .detail' "$CHECKS")")"
  echo; warn "likely cause (heuristic): $ROOT_CAUSE"
fi

DEP="$(dep_json)"; APPJ="$(app_json)"
jq -n --arg label "$LABEL" --arg result "$RESULT" --arg at "$(now_iso)" --arg rev "$(git_rev)" \
      --arg digest "$EXPECT_DIGEST" --arg expRev "$EXPECT_REV" --arg diag "$DIAG" --arg cause "$ROOT_CAUSE" \
      --argjson passed "$PASSED" --argjson failed "$FAILED" --argjson skipped "$SKIPPED" \
      --argjson dep "${DEP:-null}" --argjson app "${APPJ:-null}" \
      --slurpfile checks "$CHECKS" \
  '{label:$label, result:$result, finishedAt:$at, workspaceRevision:$rev, expectedImageDigest:$digest, expectedGitopsRevision:$expRev,
    summary:{passed:$passed, failed:$failed, skipped:$skipped},
    argocd:{sync:$app.status.sync.status, health:$app.status.health.status, revision:$app.status.sync.revision},
    deployment:{image:$dep.spec.template.spec.containers[0].image, desired:$dep.spec.replicas, available:($dep.status.availableReplicas // 0)},
    checks:$checks, likelyCause:(if $cause=="" then null else $cause end), diagnostics:(if $diag=="" then null else $diag end)}' >"$OUT_JSON"

echo
if [[ $FAILED -eq 0 ]]; then
  printf '%s✔ RELEASE VERIFIED%s  %d passed, %d skipped  -> %s\n' "$C_GRN" "$C_OFF" "$PASSED" "$SKIPPED" "${OUT_JSON#"$ROOT"/}"; exit 0
else
  printf '%s✖ RELEASE FAILED VERIFICATION%s  %d failed, %d passed, %d skipped  -> %s\n' "$C_RED" "$C_OFF" "$FAILED" "$PASSED" "$SKIPPED" "${OUT_JSON#"$ROOT"/}"; exit 1
fi
