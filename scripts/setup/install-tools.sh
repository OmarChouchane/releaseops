#!/usr/bin/env bash
# Installs missing CLI tools into ~/.local/bin (no sudo, checksums verified).
# Never replaces an existing tool; system packages (docker, git, ...) are not installed.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "unsupported CPU architecture: $(uname -m)" ;;
esac

verify_sha256() { # verify_sha256 <file> <expected-hash>
  local actual
  actual="$(sha256sum "$1" | awk '{print $1}')"
  [[ "$actual" == "$2" ]] || die "checksum mismatch for $1 (expected $2, got $actual)"
}

install_kind() {
  have kind && { ok "kind present ($(kind version | awk '{print $2}'))"; return; }
  step "installing kind $KIND_VERSION"
  local base="https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION"
  curl -fsSL -o "$TMP/kind" "$base/kind-linux-$ARCH"
  curl -fsSL -o "$TMP/kind.sha256" "$base/kind-linux-$ARCH.sha256sum"
  verify_sha256 "$TMP/kind" "$(awk '{print $1}' "$TMP/kind.sha256")"
  install -m 0755 "$TMP/kind" "$BIN/kind"; ok "kind installed"
}

install_kubectl() {
  have kubectl && { ok "kubectl present"; return; }
  step "installing kubectl $KUBECTL_VERSION"
  local base="https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARCH"
  curl -fsSL -o "$TMP/kubectl" "$base/kubectl"
  verify_sha256 "$TMP/kubectl" "$(curl -fsSL "$base/kubectl.sha256")"
  install -m 0755 "$TMP/kubectl" "$BIN/kubectl"; ok "kubectl installed"
}

install_helm() {
  have helm && { ok "helm present ($(helm version --short))"; return; }
  step "installing helm $HELM_VERSION"
  local f="helm-$HELM_VERSION-linux-$ARCH.tar.gz"
  curl -fsSL -o "$TMP/$f" "https://get.helm.sh/$f"
  verify_sha256 "$TMP/$f" "$(curl -fsSL "https://get.helm.sh/$f.sha256sum" | awk '{print $1}')"
  tar -xzf "$TMP/$f" -C "$TMP"; install -m 0755 "$TMP/linux-$ARCH/helm" "$BIN/helm"; ok "helm installed"
}

install_terraform() {
  have terraform && { ok "terraform present ($(terraform version | head -1))"; return; }
  step "installing terraform $TERRAFORM_VERSION"
  have unzip || die "unzip is required to install terraform (sudo apt-get install -y unzip)"
  local base="https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION" f="terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip"
  curl -fsSL -o "$TMP/$f" "$base/$f"
  curl -fsSL -o "$TMP/SUMS" "$base/terraform_${TERRAFORM_VERSION}_SHA256SUMS"
  verify_sha256 "$TMP/$f" "$(grep " $f\$" "$TMP/SUMS" | awk '{print $1}')"
  unzip -q -o "$TMP/$f" terraform -d "$TMP"; install -m 0755 "$TMP/terraform" "$BIN/terraform"; ok "terraform installed"
}

have curl || die "curl is required (sudo apt-get install -y curl)"
install_kind
install_kubectl
install_helm
install_terraform
case ":$PATH:" in *":$BIN:"*) ;; *) warn "add to your shell profile:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;; esac
