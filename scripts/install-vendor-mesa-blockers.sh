#!/usr/bin/env bash
# Install vendor libgbm blocker debs + apt-mark hold Ubuntu Mesa packages.
# Prevents apt/Discover from replacing vendor Turnip/Mesa (and "fix --broken").
#
# Usage:
#   sudo ./scripts/install-vendor-mesa-blockers.sh /media/odin2/STORAGE
#   sudo ./scripts/install-vendor-mesa-blockers.sh /
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
MESA_DIR="${ROOT_DIR}/vendor/system-fixes/MESA"

log() { printf '==> [mesa-block] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ "$ROOTFS" == "/" ]] || ROOTFS="${ROOTFS%/}"

DEB_GBM1="${MESA_DIR}/libgbm1_99.26.0.3-sm8550vendor1_arm64.deb"
DEB_DEV="${MESA_DIR}/libgbm-dev_99.26.0.3-sm8550vendor1_arm64.deb"
HAVE_DEBS=0
if [[ -f "$DEB_GBM1" && -f "$DEB_DEV" ]]; then
  HAVE_DEBS=1
else
  log "Vendor libgbm debs not in ${MESA_DIR} — apt-mark hold only"
fi

# User-specified hold list (vendor/system-fixes/MESA/hold pakages.txt)
# shellcheck source=lib/mesa-hold-packages.sh
source "${ROOT_DIR}/scripts/lib/mesa-hold-packages.sh"
HOLD_PKGS=("${MESA_HOLD_PKGS[@]}")
# Keep vendor libgbm held when the blocker debs are installed
HOLD_PKGS+=(libgbm1 libgbm-dev)

# Apt pin (block stock Ubuntu Mesa from repos)
PIN_SRC="${ROOT_DIR}/config/apt-preferences/99-block-ubuntu-mesa"
[[ -f "$PIN_SRC" ]] || PIN_SRC="${ROOT_DIR}/system_files/etc/apt/preferences.d/99-block-ubuntu-mesa"
if [[ -f "$PIN_SRC" ]]; then
  install -D -m 0644 "$PIN_SRC" "${ROOTFS}/etc/apt/preferences.d/99-block-ubuntu-mesa"
  chown root:root "${ROOTFS}/etc/apt/preferences.d/99-block-ubuntu-mesa"
  log "Installed apt pin 99-block-ubuntu-mesa"
fi

if [[ "$HAVE_DEBS" -eq 1 ]]; then
  stage="$(mktemp -d)"
  cleanup() { rm -rf "$stage"; }
  trap cleanup EXIT
  cp -a "$DEB_GBM1" "$DEB_DEV" "$stage/"

  if [[ "$ROOTFS" == "/" ]]; then
    log "Installing vendor libgbm debs on live system"
    dpkg -i "${stage}/"*.deb || apt-get -y -f install
  else
    log "Installing vendor libgbm debs into ${ROOTFS}"
    mkdir -p "${ROOTFS}/tmp/mesa-blockers"
    cp -a "${stage}/"*.deb "${ROOTFS}/tmp/mesa-blockers/"
    mountpoint -q "${ROOTFS}/proc" || mount -t proc proc "${ROOTFS}/proc"
    mountpoint -q "${ROOTFS}/sys" || mount -t sysfs sysfs "${ROOTFS}/sys"
    mountpoint -q "${ROOTFS}/dev" || mount --bind /dev "${ROOTFS}/dev"
    chroot "$ROOTFS" bash -c 'dpkg -i /tmp/mesa-blockers/*.deb || apt-get -y -f install'
    chroot "$ROOTFS" rm -rf /tmp/mesa-blockers
    if [[ -x "${ROOT_DIR}/scripts/unmount-rootfs-binds.sh" ]]; then
      "${ROOT_DIR}/scripts/unmount-rootfs-binds.sh" "$ROOTFS"
    else
      umount -l "${ROOTFS}/sys" "${ROOTFS}/proc" "${ROOTFS}/dev" 2>/dev/null || true
    fi
  fi
else
  HOLD_PKGS=("${MESA_HOLD_PKGS[@]}")
fi

log "apt-mark hold Mesa packages"
if [[ "$ROOTFS" == "/" ]]; then
  apt-mark hold "${HOLD_PKGS[@]}" || true
  apt-mark showhold | grep -E 'mesa|libegl|libgl|libgbm|libgles' || true
else
  chroot "$ROOTFS" apt-mark hold "${HOLD_PKGS[@]}" 2>/dev/null || true
  chroot "$ROOTFS" apt-mark showhold 2>/dev/null | grep -E 'mesa|libegl|libgl|libgbm|libgles' || true
fi

log "Installed versions:"
if [[ "$ROOTFS" == "/" ]]; then
  dpkg -l libgbm1 libgbm-dev 2>/dev/null | awk '/^ii/{print}'
else
  chroot "$ROOTFS" dpkg -l libgbm1 libgbm-dev 2>/dev/null | awk '/^ii/{print}' || true
fi

log "Done"
