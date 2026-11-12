#!/usr/bin/env bash
# ReleaseOps - single entry point.   ./run.sh help
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$ROOT/scripts"
# shellcheck source=scripts/lib/common.sh
source "$S/lib/common.sh"
# shellcheck source=scripts/lib/gitops.sh
source "$S/lib/gitops.sh"

usage() {
  cat <<EOF
ReleaseOps - build, deploy (GitOps), verify and recover a release, locally on kind.

  ./run.sh up        EVERYTHING: doctor -> cluster -> Terraform -> Argo CD -> release -> verify -> report
  ./run.sh doctor    check prerequisites (read-only)
  ./run.sh tools     install missing CLI tools into ~/.local/bin (no sudo)
  ./run.sh setup     create/reuse the kind cluster, run Terraform, start Argo CD + monitoring (no release)
  ./run.sh deploy    test -> build -> scan -> SBOM -> push -> commit the image digest to Git -> Argo CD syncs
  ./run.sh verify    verify the running release end-to-end (exit 1 on any failure)
  ./run.sh monitor   prove monitoring works: dashboard queries, alert rules, Grafana import
  ./run.sh demo      bad-release demo: break via Git, detect, diagnose, revert via Git, re-verify
  ./run.sh status    cluster / Argo CD / app / monitoring overview and access URLs
  ./run.sh logs [app|mysql|argocd]   follow logs
  ./run.sh report    build reports/out/release-report.{json,md} from recorded results
  ./run.sh test      run the Maven tests only
  ./run.sh validate  offline checks: helm lint/template, terraform fmt/validate, shell syntax
  ./run.sh cleanup [--yes] [--keep-cache]   delete ONLY this project's cluster, registry and local state

Configuration is via environment variables (see scripts/lib/common.sh), e.g.
  GITOPS_MODE=remote GITOPS_REPO_URL=https://github.com/<you>/<repo>.git ./run.sh up
  SKIP_TESTS=1 ./run.sh up        (skip the Maven/Testcontainers run; recorded as "skipped")
EOF
}

cmd_setup() {
  # Missing CLI tools install into ~/.local/bin (no sudo, checksums verified)
  "$S/setup/install-tools.sh"
  "$S/setup/doctor.sh"
  step "Stage 0: cluster + registry (script)"; "$S/setup/cluster.sh"
  if [[ "$GITOPS_MODE" == local ]]; then mirror_build_push; fi
  step "Stages 1-4: Terraform (namespaces, secrets, Argo CD, monitoring${GITOPS_MODE:+, GitOps source: $GITOPS_MODE})"
  "$S/setup/infra.sh" apply
  if [[ "$GITOPS_MODE" == local ]]; then
    step "seeding the in-cluster git mirror from this workspace"
    wait_for "git mirror ready" 120 k -n "$MIRROR_NS" wait --for=condition=Available deploy/git-mirror --timeout=5s || die "git mirror did not start"
    gitops_open; trap gitops_close EXIT
    seed_from_workspace
    gitops_close; trap - EXIT
  else
    info "Argo CD tracks $GITOPS_REPO_URL @ $GITOPS_BRANCH (nothing is pushed by setup)"
  fi
  argocd_refresh
  wait_for "Argo CD server" 300 k -n "$NS_ARGOCD" rollout status deploy/argocd-server --timeout=5s || warn "Argo CD server not ready yet"
  ok "setup complete"
}

cmd_deploy() { "$S/release/release.sh" all; }

cmd_verify() { "$S/verify/verify.sh" "$@"; }

cmd_up() {
  local start=$SECONDS
  cmd_setup
  if [[ "$GITOPS_MODE" == remote ]]; then
    # Remote mode: the image comes from CI via a release PR
    cat <<EOF

    Remote GitOps mode: Argo CD now tracks ${GITOPS_REPO_URL} @ ${GITOPS_BRANCH}.
    The application stays "ComparisonError: set image.digest" until a release is pinned in Git:
      1. push this repository to GitHub (see README: "Using your own GitHub repository")
      2. let the CI workflow run on main; it opens a release pull request
      3. merge that pull request  ->  Argo CD deploys it
      4. ./run.sh verify          ->  proves the release works
EOF
    "$S/verify/status.sh" || true
    return 0
  fi
  cmd_deploy
  "$S/verify/verify.sh" --label baseline --wait 300 || { warn "baseline verification FAILED - see output above"; "$S/release/report.sh" || true; exit 1; }
  step "monitoring"; "$S/verify/monitor-check.sh" || warn "monitoring check reported problems (see above)"
  "$S/release/report.sh" || true
  "$S/verify/status.sh" || true
  ok "done in $((SECONDS - start))s.  Next: ./run.sh demo   (bad release + Git rollback)"
}

cmd_logs() {
  case "${1:-app}" in
    app)    k -n "$NS_APP" logs -f -l "app.kubernetes.io/instance=${APP_NAME},app.kubernetes.io/component=app" --all-containers --prefix --tail=50 ;;
    mysql)  k -n "$NS_APP" logs -f "sts/${APP_NAME}-mysql" --tail=50 ;;
    argocd) k -n "$NS_ARGOCD" logs -f deploy/argocd-application-controller --tail=50 ;;
    *) die "usage: ./run.sh logs [app|mysql|argocd]" ;;
  esac
}

cmd_validate() {
  need helm; need jq
  step "helm lint + template (strict)"
  local dig="sha256:0000000000000000000000000000000000000000000000000000000000000000"
  helm lint "$CHART_DIR" -f "$ROOT/$ENV_VALUES_REL" --set image.digest="$dig" --strict
  helm template "$APP_NAME" "$CHART_DIR" -n "$NS_APP" -f "$ROOT/$ENV_VALUES_REL" --set image.digest="$dig" >/dev/null && ok "chart renders"
  helm lint "$ROOT/infra/terraform/modules/argocd/chart" --strict >/dev/null && ok "gitops-bootstrap chart lints"
  "$S/setup/infra.sh" validate
  step "shell syntax"
  local f; for f in "$ROOT"/run.sh "$S"/{setup,release,verify,lib,ci}/*.sh "$ROOT"/deploy/git-mirror/entrypoint.sh; do bash -n "$f" || die "syntax error in $f"; done; ok "all scripts parse"
  if have shellcheck; then shellcheck -x -S warning "$ROOT"/run.sh "$S"/{setup,release,verify,lib,ci}/*.sh && ok "shellcheck clean"; else info "shellcheck not installed - skipped"; fi
}

cmd_cleanup() {
  local yes=0 keep_cache=0 a2
  for a2 in "$@"; do [[ "$a2" == "--yes" ]] && yes=1; [[ "$a2" == "--keep-cache" ]] && keep_cache=1; done
  step "this will remove ONLY the following ReleaseOps resources"
  cluster_exists && info "kind cluster:      $CLUSTER_NAME (and everything running in it)"
  docker inspect "$REGISTRY_NAME" >/dev/null 2>&1 && info "registry container: $REGISTRY_NAME"
  [[ $keep_cache -eq 0 ]] && docker volume inspect releaseops-trivy-cache >/dev/null 2>&1 && info "docker volume:      releaseops-trivy-cache (the ~3 GB scanner DB; keep it with --keep-cache)"
  info "local state dir:    $STATE_DIR (kubeconfig, terraform state, git work clone)"
  info "images:             releaseops-app:local, localhost:${REGISTRY_PORT}/releaseops/*"
  info "NOT touched: your other containers/volumes/clusters, ~/.kube/config, ~/.local/bin tools, reports/out"
  if [[ $yes -ne 1 ]]; then read -r -p "Proceed? [y/N] " a; [[ "$a" =~ ^[Yy]$ ]] || { info "aborted"; return 0; }; fi
  gitops_close 2>/dev/null || true
  cluster_exists && kind delete cluster --name "$CLUSTER_NAME"
  docker inspect "$REGISTRY_NAME" >/dev/null 2>&1 && docker rm -f "$REGISTRY_NAME" >/dev/null
  [[ $keep_cache -eq 0 ]] && docker volume rm releaseops-trivy-cache >/dev/null 2>&1 || true
  docker rmi releaseops-app:local >/dev/null 2>&1 || true
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^localhost:${REGISTRY_PORT}/releaseops/" | xargs -r docker rmi >/dev/null 2>&1 || true
  rm -rf "$STATE_DIR"
  ok "clean"
}

case "${1:-help}" in
  up) cmd_up ;;
  doctor) "$S/setup/doctor.sh" ;;
  tools) "$S/setup/install-tools.sh" ;;
  setup) cmd_setup ;;
  deploy) cmd_deploy ;;
  verify) shift; cmd_verify "$@" ;;
  demo) shift; "$S/verify/demo.sh" "$@" ;;
  status) "$S/verify/status.sh" ;;
  monitor) "$S/verify/monitor-check.sh" ;;
  logs) shift; cmd_logs "$@" ;;
  report) "$S/release/report.sh" ;;
  test) "$S/release/release.sh" test ;;
  validate) cmd_validate ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
