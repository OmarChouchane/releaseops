#!/usr/bin/env bash
# Prerequisite checks; exit 1 if something REQUIRED is missing. Changes nothing.
set -uo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

FAIL=0
req()  { if "${@:2}" >/dev/null 2>&1; then ok "$1"; else printf '    %s✖%s %s\n' "$C_RED" "$C_OFF" "$1" >&2; FAIL=1; fi; }
hint() { printf '      %s→ %s%s\n' "$C_DIM" "$*" "$C_OFF" >&2; }

step "operating system"
if grep -qi microsoft /proc/version 2>/dev/null; then ok "WSL2 detected ($(. /etc/os-release; echo "$PRETTY_NAME"))"
else info "not WSL ($(uname -sr)) - fine, this is plain Linux"; fi

step "required tools"
for t in docker git curl jq tar; do
  if have "$t"; then ok "$t"; else printf '    %s✖%s %s missing\n' "$C_RED" "$C_OFF" "$t" >&2; FAIL=1
    hint "sudo apt-get update && sudo apt-get install -y $t"; fi
done
if have java && java -version 2>&1 | grep -qE 'version "(17|21)'; then ok "java ($(java -version 2>&1 | head -1)) - used by the Maven test stage"
else warn "Java 17+ not found: the Maven test stage will fail. Install: sudo apt-get install -y openjdk-17-jdk-headless  - or run with SKIP_TESTS=1 (recorded as skipped)"; fi
have make || { warn "make not found (optional: only for the Makefile shortcuts) -> sudo apt-get install -y make"; }
have unzip || warn "unzip not found (only needed by scripts/setup/install-tools.sh for terraform)"
for t in kind kubectl helm terraform; do
  if have "$t"; then ok "$t ($(
    case $t in kind) kind version | awk '{print $2}';; kubectl) kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion;;
      helm) helm version --short;; terraform) terraform version | head -1;; esac))"
  else printf '    %s✖%s %s missing\n' "$C_RED" "$C_OFF" "$t" >&2; FAIL=1; hint "./run.sh tools   (installs into ~/.local/bin, no sudo)"; fi
done

step "docker"
if have docker && docker info >/dev/null 2>&1; then
  ok "daemon reachable (server $(docker version --format '{{.Server.Version}}'))"
  mem_gb=$(docker info --format '{{.MemTotal}}' | awk '{printf "%.1f", $1/1024/1024/1024}')
  cpus=$(docker info --format '{{.NCPU}}')
  info "docker has ${cpus} CPUs and ${mem_gb} GiB memory available"
  awk -v m="$mem_gb" 'BEGIN{exit !(m < 6)}' && { warn "less than 6 GiB: the full stack (kind + Argo CD + Prometheus/Grafana) needs about 4 GiB; consider raising it in .wslconfig / Docker settings"; }
  df_gb=$(df -Pk "$HOME" | awk 'NR==2{printf "%d", $4/1024/1024}')
  ((df_gb < 10)) && warn "only ${df_gb} GiB free in \$HOME; images + volumes need ~8 GiB" || ok "disk: ${df_gb} GiB free"
else
  printf '    %s✖%s cannot talk to the Docker daemon\n' "$C_RED" "$C_OFF" >&2; FAIL=1
  hint "Docker Desktop: start it and enable Settings > Resources > WSL integration for this distro"
  hint "Docker Engine in WSL: sudo systemctl start docker && sudo usermod -aG docker \$USER (then re-login)"
fi

step "host ports"
if cluster_exists; then info "cluster '$CLUSTER_NAME' already exists - its ports are in use by design"
else
  for p in "$API_PORT" "$APP_PORT" "$ARGOCD_PORT" "$GRAFANA_PORT" "$PROMETHEUS_PORT"; do
    if port_in_use "$p"; then printf '    %s✖%s port %s is in use\n' "$C_RED" "$C_OFF" "$p" >&2; FAIL=1; hint "choose another with e.g. APP_PORT=28080 ./run.sh setup"; else ok "port $p free"; fi
  done
fi
if ! docker inspect "$REGISTRY_NAME" >/dev/null 2>&1 && port_in_use "$REGISTRY_PORT"; then
  printf '    %s✖%s registry port %s is in use\n' "$C_RED" "$C_OFF" "$REGISTRY_PORT" >&2; FAIL=1; hint "REGISTRY_PORT=5002 ./run.sh setup"
fi

step "kubernetes context safety"
info "this project uses its own kubeconfig ($KUBECONFIG_FILE) and the pinned context '$KIND_CONTEXT'; ~/.kube/config is never read or written"
if [[ "$GITOPS_MODE" == remote ]]; then
  [[ -n "$GITOPS_REPO_URL" ]] && ok "GitOps source: $GITOPS_REPO_URL (branch $GITOPS_BRANCH)" || { printf '    %s✖%s GITOPS_MODE=remote needs GITOPS_REPO_URL\n' "$C_RED" "$C_OFF" >&2; FAIL=1; }
else ok "GitOps source: in-cluster git mirror of this workspace"; fi

echo
if [[ $FAIL -eq 0 ]]; then printf '%s✔ environment looks good%s\n' "$C_GRN" "$C_OFF"; else printf '%s✖ fix the items above, then re-run ./run.sh doctor%s\n' "$C_RED" "$C_OFF" >&2; fi
exit $FAIL
