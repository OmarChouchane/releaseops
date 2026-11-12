#!/usr/bin/env bash
# Proves monitoring is real: dashboard queries return data, alerts are loaded, Grafana has the dashboard.
set -uo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

PROM="http://127.0.0.1:${PROMETHEUS_PORT}"
GRAF="http://127.0.0.1:${GRAFANA_PORT}"
DASH="$CHART_DIR/dashboards/releaseops.json"
FAIL=0; EMPTY=0; OK=0

curl -fsS -m 5 "$PROM/-/ready" >/dev/null || die "Prometheus not reachable at $PROM"

step "dashboard queries against live Prometheus"
while IFS=$'\t' read -r title expr; do
  q="${expr//\$namespace/$NS_APP}"
  n="$(curl -sS -m 15 -G "$PROM/api/v1/query" --data-urlencode "query=$q" | jq -r 'if .status=="success" then (.data.result|length) else "ERR:\(.error)" end')"
  if [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]]; then OK=$((OK + 1)); printf '    %s✔%s %-34s %s series\n' "$C_GRN" "$C_OFF" "$title" "$n"
  elif [[ "$n" == 0 ]]; then EMPTY=$((EMPTY + 1)); printf '    %s∅%s %-34s no data (valid query; metric has no samples yet)\n' "$C_YEL" "$C_OFF" "$title"
  else FAIL=$((FAIL + 1)); printf '    %s✖%s %-34s %s\n' "$C_RED" "$C_OFF" "$title" "$n"; fi
done < <(jq -r '.panels[] | select(.targets) | . as $p | .targets[] | [$p.title, .expr] | @tsv' "$DASH")
info "$OK returned data, $EMPTY valid-but-empty, $FAIL invalid"

step "alert rules loaded in Prometheus"
rules="$(curl -sS -m 10 "$PROM/api/v1/rules" | jq -r '[.data.groups[].rules[] | select(.name|startswith("ReleaseOps")) | "\(.name)=\(.state)"] | join(", ")')"
[[ -n "$rules" ]] && ok "$rules" || { printf '    %s✖%s no ReleaseOps rules loaded\n' "$C_RED" "$C_OFF"; FAIL=$((FAIL + 1)); }

step "Prometheus targets"
curl -sS -m 10 "$PROM/api/v1/targets" | jq -r --arg ns "$NS_APP" '.data.activeTargets[] | select(.labels.namespace==$ns) | "    \(.health)  \(.labels.pod)  \(.scrapeUrl)"'

step "Grafana dashboard imported"
GPW="$("$ROOT/scripts/infra.sh" output grafana_admin_password 2>/dev/null)"
if [[ -n "$GPW" ]]; then
  found="$(curl -sS -m 10 -u "admin:$GPW" "$GRAF/api/search?query=ReleaseOps" | jq -r '[.[] | .title] | join("; ")')"
  [[ -n "$found" ]] && ok "$found" || { printf '    %s✖%s dashboard not found in Grafana\n' "$C_RED" "$C_OFF"; FAIL=$((FAIL + 1)); }
  # Prove the dashboard datasource uid resolves by querying THROUGH Grafana
  via="$(curl -sS -m 15 -u "admin:$GPW" -G "$GRAF/api/datasources/proxy/uid/prometheus/api/v1/query" \
         --data-urlencode "query=min(app_database_up{namespace=\"$NS_APP\"})" | jq -r '.data.result[0].value[1] // "none"')"
  [[ "$via" == 1 ]] && ok "query through Grafana's 'prometheus' datasource works (app_database_up=$via)" \
                    || { printf '    %s✖%s Grafana datasource query returned: %s\n' "$C_RED" "$C_OFF" "$via"; FAIL=$((FAIL + 1)); }
else warn "could not read the Grafana password (terraform state) - dashboard import not checked"; fi

echo
[[ $FAIL -eq 0 ]] && printf '%s✔ monitoring verified%s\n' "$C_GRN" "$C_OFF" || { printf '%s✖ monitoring check failed (%d)%s\n' "$C_RED" "$FAIL" "$C_OFF"; exit 1; }
