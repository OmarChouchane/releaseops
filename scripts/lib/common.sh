#!/usr/bin/env bash
# Shared configuration and helpers. Sourced by run.sh and every script; never executed directly.
# shellcheck shell=bash
# shellcheck disable=SC2034  # configuration variables are consumed by the scripts that source this file

[[ -n "${_RELEASEOPS_COMMON:-}" ]] && return 0
_RELEASEOPS_COMMON=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ROOT

# ---------------------------------------------------------------- configuration
# Everything below can be overridden from the environment.
: "${CLUSTER_NAME:=releaseops}"
: "${REGISTRY_NAME:=releaseops-registry}"
: "${REGISTRY_PORT:=5001}"
: "${API_PORT:=16443}"          # Kubernetes API server on 127.0.0.1 (fixed on purpose, see cluster.sh)
: "${APP_PORT:=18080}"         # http://localhost:APP_PORT      -> app Service (NodePort 30080)
: "${ARGOCD_PORT:=18081}"       # http://localhost:ARGOCD_PORT   -> Argo CD UI (NodePort 30081)
: "${GRAFANA_PORT:=13000}"      # http://localhost:GRAFANA_PORT  -> Grafana   (NodePort 30300)
: "${PROMETHEUS_PORT:=19090}"   # http://localhost:PROMETHEUS_PORT -> Prometheus (NodePort 30900)
: "${NS_APP:=releaseops}"
: "${NS_ARGOCD:=argocd}"
: "${NS_MONITORING:=monitoring}"
: "${APP_NAME:=releaseops}"     # Helm release name == Argo CD Application name == resource prefix
: "${ENV_NAME:=local}"          # deploy/environments/<ENV_NAME>/values.yaml
: "${GITOPS_MODE:=local}"       # local  = in-cluster git mirror of this workspace (default)
                                # remote = Argo CD tracks GITOPS_REPO_URL (e.g. your GitHub repo)
: "${GITOPS_REPO_URL:=}"        # required for GITOPS_MODE=remote
: "${GITOPS_BRANCH:=main}"
: "${GITOPS_GIT_PORT:=18082}"   # port-forward used by the host to push to the in-cluster mirror

# Pinned tool and image versions (see docs/VERSIONS.md for sources and rationale).
KIND_VERSION="v0.33.0"
KIND_NODE_IMAGE="kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
KUBECTL_VERSION="v1.36.4"
HELM_VERSION="v4.3.1"
TERRAFORM_VERSION="1.16.7"
TRIVY_IMAGE="docker.io/aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222"   # same digest on public.ecr.aws/aquasecurity/trivy
REGISTRY_IMAGE="registry:2@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373"

STATE_DIR="${RELEASEOPS_STATE_DIR:-$ROOT/.releaseops}"
REPORT_DIR="${RELEASEOPS_REPORT_DIR:-$ROOT/reports/out}"
KUBECONFIG_FILE="$STATE_DIR/kubeconfig"
TF_DIR="$ROOT/infra/terraform/local"
CHART_DIR="$ROOT/deploy/helm/releaseops"
ENV_VALUES_REL="deploy/environments/${ENV_NAME}/values.yaml"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

mkdir -p "$STATE_DIR" "$REPORT_DIR"
export PATH="$HOME/.local/bin:$PATH"

# Dedicated kubeconfig: this project never reads or writes ~/.kube/config.
export KUBECONFIG="$KUBECONFIG_FILE"

# ---------------------------------------------------------------- output
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_DIM=""; C_OFF=""
fi
step()  { printf '%s==>%s %s\n' "$C_BLU" "$C_OFF" "$*"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s✔%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn()  { printf '    %s!%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()   { printf '%s✖ %s%s\n' "$C_RED" "$*" "$C_OFF" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }
need() { have "$1" || die "missing prerequisite: $1  (run ./run.sh doctor)"; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# kubectl always against OUR cluster, regardless of the user's current context.
k() { kubectl --context "$KIND_CONTEXT" "$@"; }

# wait_for <description> <timeout-seconds> <command...>: poll until the command succeeds.
wait_for() {
  local what="$1" timeout="$2"; shift 2
  local end=$((SECONDS + timeout))
  until "$@" >/dev/null 2>&1; do
    if ((SECONDS >= end)); then warn "timed out after ${timeout}s waiting for: $what"; return 1; fi
    sleep 3
  done
}

cluster_exists() { kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; }

# Version helpers for the local registry reference used in Git (kind nodes resolve it).
registry_ref() { echo "localhost:${REGISTRY_PORT}/releaseops/app"; }

port_in_use() { # port_in_use <port>: true if something listens on 127.0.0.1:<port>
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# The workspace revision shown in reports (works with or without commits).
git_rev() { git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo "no-commits"; }
git_dirty() { [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]] && echo true || echo false; }
