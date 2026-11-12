#!/usr/bin/env bash
# Stage 1-4: Terraform against the existing cluster. Subcommands: apply | destroy | output <name> | validate
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/gitops.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitops.sh"

TF_STATE="$STATE_DIR/terraform.tfstate"

tf_env() {
  export TF_IN_AUTOMATION=1 TF_INPUT=0
  export TF_VAR_kubeconfig_path="$KUBECONFIG_FILE"
  export TF_VAR_kube_context="$KIND_CONTEXT"
  export TF_VAR_app_namespace="$NS_APP" TF_VAR_argocd_namespace="$NS_ARGOCD" TF_VAR_monitoring_namespace="$NS_MONITORING"
  export TF_VAR_app_name="$APP_NAME" TF_VAR_environment="$ENV_NAME"
  export TF_VAR_gitops_mode="$GITOPS_MODE" TF_VAR_gitops_repo_url="$GITOPS_REPO_URL" TF_VAR_gitops_revision="$GITOPS_BRANCH"
  TF_VAR_git_mirror_image="$(mirror_image_ref)"; export TF_VAR_git_mirror_image
  # Private remote repos only: read-only credentials via env, never a file
  [[ -n "${GITOPS_REPO_USERNAME:-}" ]] && export TF_VAR_gitops_repo_username="$GITOPS_REPO_USERNAME"
  [[ -n "${GITOPS_REPO_TOKEN:-}" ]] && export TF_VAR_gitops_repo_password="$GITOPS_REPO_TOKEN"
  true
}

tf() { terraform -chdir="$TF_DIR" "$@"; }

tf_init() {
  tf init -input=false -backend-config="path=$TF_STATE" -reconfigure >/dev/null
  [[ -f "$TF_STATE" ]] && chmod 600 "$TF_STATE" || true
}

cmd_apply() {
  need terraform
  [[ "$GITOPS_MODE" == "local" && -z "$(mirror_image_ref)" ]] && mirror_build_push
  tf_env; tf_init
  step "terraform apply (cluster context: $KIND_CONTEXT, GitOps source: $GITOPS_MODE)"
  local log="$STATE_DIR/terraform-apply.log"
  if ! tf apply -input=false -auto-approve -no-color >"$log" 2>&1; then
    tail -40 "$log" >&2; die "terraform apply failed (full log: $log)"
  fi
  grep -E '^(Apply complete|No changes)' "$log" | sed 's/^/    /' || true
  chmod 600 "$TF_STATE" 2>/dev/null || true
  ok "infrastructure converged"
}

cmd_destroy() {
  need terraform; tf_env; tf_init
  # Argo CD would self-heal resources while Terraform removes them
  k -n "$NS_ARGOCD" delete application "$APP_NAME" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  tf destroy -input=false -auto-approve -no-color
}

cmd_output() { tf_env; tf_init; tf output -raw "$1"; }

cmd_validate() { # offline: no cluster, no providers' network calls beyond init
  need terraform
  local d
  for d in "$ROOT/infra/terraform/environments/local" "$ROOT/infra/terraform/environments/aws"; do
    [[ -d "$d" ]] || continue
    step "terraform validate: ${d#"$ROOT"/}"
    terraform -chdir="$d" init -backend=false -input=false >/dev/null
    terraform -chdir="$d" validate -no-color
    terraform -chdir="$d" fmt -check -recursive -diff >/dev/null && ok "fmt clean" || die "terraform fmt needed in $d"
  done
}

case "${1:-}" in
  apply) cmd_apply ;;
  destroy) cmd_destroy ;;
  output) shift; cmd_output "$@" ;;
  validate) cmd_validate ;;
  *) die "usage: infra.sh apply|destroy|output <name>|validate" ;;
esac
