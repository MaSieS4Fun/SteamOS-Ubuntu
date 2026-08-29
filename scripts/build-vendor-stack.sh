#!/usr/bin/env bash
# Build/install the SM8550 gaming userspace stack into a rootfs:
#   Mesa 26.1.6 (patched) → gamescope (Adreno) → MangoHud → Steam ARM (+ updater)
# Usage: build-vendor-stack.sh <rootfs>
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"

log() { printf '==> [vendor-stack] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
chmod +x "${ROOT_DIR}/scripts/"*.sh

if [[ "${EUID}" -eq 0 && "${SKIP_HOST_DEPS:-0}" != "1" ]]; then
  if ! command -v meson >/dev/null 2>&1 \
    || ! pkg-config --exists libdrm 2>/dev/null \
    || ! pkg-config --exists wayland-client 2>/dev/null; then
    log "Host compile deps missing — installing (packages/build-deps)…"
    "${ROOT_DIR}/scripts/install-host-build-deps.sh"
  fi
fi

install -d "${ROOTFS}/usr/share/sm8550-steamos"

SKIP_MESA="${SKIP_MESA:-0}"
SKIP_GAMESCOPE="${SKIP_GAMESCOPE:-0}"
SKIP_MANGOHUD="${SKIP_MANGOHUD:-0}"
SKIP_STEAM="${SKIP_STEAM:-0}"

if [[ "$SKIP_MESA" != "1" ]]; then
  log "1/4 Mesa ${MESA_VER:-26.1.6} + SM8550 patches"
  "${ROOT_DIR}/scripts/build-vendor-mesa.sh" "$ROOTFS"
else
  log "SKIP_MESA=1"
fi

if [[ "$SKIP_GAMESCOPE" != "1" ]]; then
  log "2/4 vendor gamescope (Adreno 740)"
  "${ROOT_DIR}/scripts/build-vendor-gamescope.sh" "$ROOTFS"
else
  log "SKIP_GAMESCOPE=1 — still verifying/installing runtime libs if binary exists"
  if [[ -x "${ROOTFS}/usr/local/bin/gamescope" ]]; then
    "${ROOT_DIR}/scripts/ensure-gamescope-libs.sh" "$ROOTFS"
  fi
fi

if [[ "$SKIP_MANGOHUD" != "1" ]]; then
  log "3/4 vendor MangoHud"
  "${ROOT_DIR}/scripts/build-vendor-mangohud.sh" "$ROOTFS"
else
  log "SKIP_MANGOHUD=1"
fi

if [[ "$SKIP_STEAM" != "1" ]]; then
  log "4/4 Steam ARM Deck bake (steamdeck_publicbeta → steamui + OOBE)"
  "${ROOT_DIR}/scripts/install-steam-arm-into-rootfs.sh" "$ROOTFS"
else
  log "SKIP_STEAM=1"
fi

log "Vendor stack complete"

# gamescope embeds Steam via Xwayland — must exist after Mesa purge
"${ROOT_DIR}/scripts/ensure-xwayland-into-rootfs.sh" "$ROOTFS"
