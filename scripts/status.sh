#!/usr/bin/env bash
# Read-only overview: cluster, Argo CD, app, monitoring, access URLs.
set -uo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if ! cluster_exists; then
  warn "cluster '$CLUSTER_NAME' does not exist. Start with: ./run.sh up"; exit 1
fi

step "Argo CD application"
k -n "$NS_ARGOCD" get application "$APP_NAME" -o json 2>/dev/null \
  | jq -r '"    sync=\(.status.sync.status // "?")  health=\(.status.health.status // "?")  revision=\((.status.sync.revision // "-")[0:12])  source=\(.spec.source.repoURL)"' \
  || warn "Application not found"

step "workloads ($NS_APP)"
k -n "$NS_APP" get deploy,sts,pods,pvc 2>/dev/null | sed 's/^/    /'

step "image in use"
k -n "$NS_APP" get deploy "$APP_NAME" -o jsonpath='    {.spec.template.spec.containers[0].image}{"\n"}' 2>/dev/null

step "monitoring"
k -n "$NS_MONITORING" get pods --no-headers 2>/dev/null | awk '{printf "    %-60s %s %s\n",$1,$2,$3}'
if curl -fs -m 3 "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/alerts" >/dev/null 2>&1; then
  firing="$(curl -fs -m 5 "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/alerts" | jq '[.data.alerts[] | select(.state=="firing" and (.labels.alertname|startswith("ReleaseOps")))] | length')"
  info "ReleaseOps alerts firing: $firing"
fi

if [[ -n "${STATUS_QUIET:-}" ]]; then exit 0; fi
step "access"
gpw="$("$ROOT/scripts/infra.sh" output grafana_admin_password 2>/dev/null || echo '<run: terraform output -raw grafana_admin_password>')"
apw="$(k -n "$NS_ARGOCD" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo '<not available>')"
cat <<EOF
    Application API : http://localhost:${APP_PORT}/user?id=1
    Argo CD UI      : http://localhost:${ARGOCD_PORT}      user: admin   password: ${apw}
    Grafana         : http://localhost:${GRAFANA_PORT}     user: admin   password: ${gpw}
                      dashboard: Dashboards > ReleaseOps > "ReleaseOps - application and release health"
    Prometheus      : http://localhost:${PROMETHEUS_PORT}  (Status > Targets, Alerts)
    kubectl         : export KUBECONFIG=${KUBECONFIG_FILE}; kubectl --context ${KIND_CONTEXT} get pods -A
EOF
