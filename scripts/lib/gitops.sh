#!/usr/bin/env bash
# Git side of the GitOps loop (local mirror or your own remote repo).
# shellcheck shell=bash

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

WORKCLONE="$STATE_DIR/gitops-work"
MIRROR_NS="gitops-mirror"
PF_PIDFILE="$STATE_DIR/git-portforward.pid"
GIT_IDENT=(-c user.name="releaseops-bot" -c user.email="releaseops-bot@localhost" -c commit.gpgsign=false)

# ----------------------------------------------------------------------------- git mirror image
mirror_image_ref() { # echoes registry/name@digest for the git-mirror image (after build_push)
  cat "$STATE_DIR/git-mirror-image" 2>/dev/null || true
}

mirror_build_push() {
  local tag="localhost:${REGISTRY_PORT}/releaseops/git-mirror:1" out digest
  step "building the git-mirror image"
  docker build -q -t "$tag" "$ROOT/deploy/git-mirror" >/dev/null
  out="$(docker push "$tag" 2>&1)"
  digest="$(grep -o 'digest: sha256:[a-f0-9]\{64\}' <<<"$out" | tail -1 | awk '{print $2}')"
  [[ -n "$digest" ]] || die "could not read the pushed digest of $tag:\n$out"
  echo "localhost:${REGISTRY_PORT}/releaseops/git-mirror@${digest}" >"$STATE_DIR/git-mirror-image"
  ok "git-mirror image: $(mirror_image_ref)"
}

# ----------------------------------------------------------------------------- push endpoint
pf_stop() {
  [[ -f "$PF_PIDFILE" ]] && kill "$(cat "$PF_PIDFILE")" 2>/dev/null || true
  rm -f "$PF_PIDFILE"
  # Stop port-forwards of ours left by a crashed run
  pkill -f "context ${KIND_CONTEXT} .*port-forward svc/git-mirror" 2>/dev/null || true
  local _; for _ in 1 2 3 4 5 6 7 8 9 10; do port_in_use "$GITOPS_GIT_PORT" || return 0; sleep 0.5; done
  return 0
}

# pf_start: reach the in-cluster mirror from the host (local mode only).
pf_start() {
  pf_stop
  port_in_use "$GITOPS_GIT_PORT" && die "port $GITOPS_GIT_PORT busy (set GITOPS_GIT_PORT)"
  # call kubectl directly so $! is its real PID
  kubectl --context "$KIND_CONTEXT" -n "$MIRROR_NS" port-forward svc/git-mirror "${GITOPS_GIT_PORT}:8080" >"$STATE_DIR/git-portforward.log" 2>&1 &
  echo $! >"$PF_PIDFILE"
  wait_for "git mirror reachable" 30 curl -fs "http://127.0.0.1:${GITOPS_GIT_PORT}/healthz" || die "git mirror not reachable (see $STATE_DIR/git-portforward.log)"
}

# URL the host pushes to / clones from
host_remote_url() {
  if [[ "$GITOPS_MODE" == "local" ]]; then echo "http://127.0.0.1:${GITOPS_GIT_PORT}/releaseops.git"
  else [[ -n "$GITOPS_REPO_URL" ]] || die "GITOPS_REPO_URL is required for GITOPS_MODE=remote"; echo "$GITOPS_REPO_URL"; fi
}

gitops_open() { [[ "$GITOPS_MODE" == "local" ]] && pf_start; ensure_workclone; }
gitops_close() { [[ "$GITOPS_MODE" == "local" ]] && pf_stop; true; }

ensure_workclone() {
  local url; url="$(host_remote_url)"
  if [[ ! -d "$WORKCLONE/.git" ]]; then
    rm -rf "$WORKCLONE"; git init -q -b "$GITOPS_BRANCH" "$WORKCLONE"
    git -C "$WORKCLONE" remote add origin "$url"
  else
    git -C "$WORKCLONE" remote set-url origin "$url"
  fi
  # The remote is the source of truth, not the clone
  if git -C "$WORKCLONE" ls-remote --exit-code --heads origin "$GITOPS_BRANCH" >/dev/null 2>&1; then
    git -C "$WORKCLONE" fetch -q origin "$GITOPS_BRANCH"
    git -C "$WORKCLONE" checkout -q -B "$GITOPS_BRANCH" "origin/$GITOPS_BRANCH"
  fi
}

gw() { git -C "$WORKCLONE" "${GIT_IDENT[@]}" "$@"; }
gitops_head() { gw rev-parse HEAD; }
gitops_push() { gw push -q origin "HEAD:refs/heads/${GITOPS_BRANCH}"; }

# ----------------------------------------------------------------------------- image pin in values
values_get() { # values_get <key>  (key = repository|digest) from the work clone
  awk -v key="$1" '$1=="image:"{in_img=1;next} in_img && $1==key":"{print $2; exit} in_img && /^[^ ]/{in_img=0}' "$WORKCLONE/$ENV_VALUES_REL"
}

values_set_image() { # values_set_image <repository> <digest>
  local f="$WORKCLONE/$ENV_VALUES_REL" tmp
  tmp="$(mktemp)"
  awk -v repo="$1" -v dig="$2" '
    $1=="image:"            { in_img=1; print; next }
    in_img && $1=="repository:" { print "  repository: " repo; next }
    in_img && $1=="digest:"     { print "  digest: " dig; next }
    in_img && /^[^ ]/       { in_img=0 }
    { print }' "$f" >"$tmp"
  cat "$tmp" >"$f"; rm -f "$tmp"
}

# ----------------------------------------------------------------------------- seed from workspace
# Copy workspace files into the work clone and commit; the image pin stays as on the remote.
seed_from_workspace() {
  local keep_repo="" keep_digest="" f
  [[ -f "$WORKCLONE/$ENV_VALUES_REL" ]] && { keep_repo="$(values_get repository)"; keep_digest="$(values_get digest)"; }

  # Drop files removed from the workspace, then copy the current ones
  (cd "$WORKCLONE" && git ls-files -z | xargs -0 -r rm -f)
  while IFS= read -r -d '' f; do
    [[ -f "$ROOT/$f" ]] || continue   # staged-but-deleted files
    mkdir -p "$WORKCLONE/$(dirname "$f")"; cp -p "$ROOT/$f" "$WORKCLONE/$f"
  done < <(cd "$ROOT" && git ls-files -z --cached --others --exclude-standard)

  [[ -n "$keep_repo$keep_digest" ]] && values_set_image "$keep_repo" "$keep_digest"

  gw add -A
  if gw diff --cached --quiet; then ok "mirror already matches the workspace"; return; fi
  gw commit -q -m "sync: workspace snapshot ($(git_rev)$([[ "$(git_dirty)" == true ]] && echo '+uncommitted'))"
  gitops_push
  ok "mirror updated to $(gitops_head | cut -c1-12)"
}

argocd_refresh() { # ask Argo CD to re-read Git now instead of waiting for the poll interval
  k -n "$NS_ARGOCD" annotate application "$APP_NAME" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
}
