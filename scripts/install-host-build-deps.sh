#!/usr/bin/env bash
# Install host deps for a one-shot create-image bake:
#   - Mesa / gamescope / MangoHud compile tools (packages/build-deps)
#   - SM8550 kernel build tools
#   - Podman stack (optional; skip with SKIP_PODMAN_DEPS=1)
#
# Run after switching to a fresh OS / before the first bake:
#   sudo ./scripts/install-host-build-deps.sh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEBIAN_FRONTEND=noninteractive

log() { printf '==> [host-deps] %s\n' "$*"; }
warn() { printf '==> [host-deps] WARN: %s\n' "$*" >&2; }

[[ "${EUID}" -eq 0 ]] || { echo "Run as root: sudo $0" >&2; exit 1; }

read_pkg_list() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  grep -vE '^\s*(#|$)' "$file" | awk 'NF'
}

mapfile -t PKGS < <(read_pkg_list "${ROOT_DIR}/packages/build-deps" | sort -u)
mapfile -t OPTIONAL < <(read_pkg_list "${ROOT_DIR}/packages/build-deps-optional" | sort -u)

KERNEL_PKGS=(
  bc bison flex make gcc g++ patch curl git device-tree-compiler
  libssl-dev libncurses-dev libelf-dev
  initramfs-tools busybox-static abootimg
  rsync debootstrap qemu-utils parted e2fsprogs dosfstools
)
PODMAN_PKGS=(
  podman buildah crun catatonit uidmap slirp4netns fuse-overlayfs
)

ALL=("${PKGS[@]}" "${KERNEL_PKGS[@]}")
if [[ "${SKIP_PODMAN_DEPS:-0}" != "1" ]]; then
  ALL+=("${PODMAN_PKGS[@]}")
fi

mapfile -t ALL < <(printf '%s\n' "${ALL[@]}" | awk 'NF && !seen[$0]++')

log "Updating apt indices…"
apt-get update -y

log "Installing required host bake deps (${#ALL[@]} packages)…"
if ! apt-get install -y --no-install-recommends "${ALL[@]}"; then
  warn "Batch install failed — retrying missing packages one by one…"
  FAILED=()
  for p in "${ALL[@]}"; do
    apt-get install -y --no-install-recommends "$p" || FAILED+=("$p")
  done
  if ((${#FAILED[@]})); then
    warn "Missing packages: ${FAILED[*]}"
    warn "Mesa/gamescope compile may fail until these are installed."
  fi
fi

if ((${#OPTIONAL[@]})); then
  log "Installing optional packages (${#OPTIONAL[@]})…"
  if ! apt-get install -y --no-install-recommends "${OPTIONAL[@]}" 2>/dev/null; then
    for p in "${OPTIONAL[@]}"; do
      apt-get install -y --no-install-recommends "$p" 2>/dev/null \
        || warn "Optional package not available: ${p}"
    done
  fi
fi

# Quick sanity check for the usual Mesa/gamescope blockers
MISSING=()
for cmd in meson ninja pkg-config git curl; do
  command -v "$cmd" >/dev/null || MISSING+=("$cmd")
done
for pc in libdrm wayland-client xcb xkbcommon libinput libpipewire-0.3; do
  pkg-config --exists "$pc" 2>/dev/null || MISSING+=("pkg-config:${pc}")
done
if ((${#MISSING[@]})); then
  warn "Still missing after install: ${MISSING[*]}"
  warn "Re-run: sudo ./scripts/install-host-build-deps.sh"
else
  log "Mesa/gamescope toolchain sanity check: OK"
fi

# Node 22 + pnpm for Heroic bake and Decky plugin frontends
# shellcheck source=lib/ensure-build-node.sh
source "${ROOT_DIR}/scripts/lib/ensure-build-node.sh"
if ensure_build_node "$ROOT_DIR"; then
  log "Build Node ready: $(node -v) / $(pnpm -v)"
else
  warn "Could not prepare Node 22 + pnpm — Heroic bake may fail until network/bootstrap succeeds"
fi

log "Host build deps step finished."
