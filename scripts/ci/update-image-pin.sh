#!/usr/bin/env bash
# update-image-pin.sh <image-repository> <digest>
# Rewrites image.repository / image.digest in the GitOps environment file. Used by CI's release PR.
set -euo pipefail
REPO="${1:?image repository}"; DIGEST="${2:?digest}"
[[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "refusing malformed digest: $DIGEST" >&2; exit 1; }
FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/deploy/environments/local/values.yaml"
tmp="$(mktemp)"
awk -v repo="$REPO" -v dig="$DIGEST" '
  $1=="image:"            { in_img=1; print; next }
  in_img && $1=="repository:" { print "  repository: " repo; next }
  in_img && $1=="digest:"     { print "  digest: " dig; next }
  in_img && /^[^ ]/       { in_img=0 }
  { print }' "$FILE" >"$tmp"
cat "$tmp" >"$FILE"; rm -f "$tmp"
git diff --stat -- "$FILE" || true
