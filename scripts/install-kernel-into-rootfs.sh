#!/usr/bin/env bash
# Install kernel tree into rootfs:
#   firmware/ → /usr/lib/firmware
#   modules/  → /usr/lib/modules
# (boot/KERNEL goes to the VFAT partition in make-disk-image.sh — not here)
#
# Usage: install-kernel-into-rootfs.sh <rootfs> [kernel-build-dir]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
BUILD="${2:-}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs> [kernel-build]"

if [[ -z "$BUILD" ]]; then
  BUILD="$("${ROOT_DIR}/scripts/ensure-kernel.sh")"
fi
BUILD="$(printf '%s\n' "${BUILD}" | awk 'NF{p=$0} END{print p}')"
BUILD="${BUILD%/}"

[[ -f "${BUILD}/boot/KERNEL" ]] || die "Missing ${BUILD}/boot/KERNEL"
[[ -d "${BUILD}/firmware" ]] || die "Missing ${BUILD}/firmware"
[[ -d "${BUILD}/modules" ]] || die "Missing ${BUILD}/modules"

log "Using kernel build: ${BUILD}"

# usrmerge: /lib → usr/lib, so /lib/firmware IS /usr/lib/firmware.
# Never recreate /lib/firmware as a relative symlink on merged systems.
is_usrmerge=0
if [[ -L "${ROOTFS}/lib" ]]; then
  is_usrmerge=1
fi

ensure_real_dir() {
  local path="$1"
  # If path is a symlink (or a symlink via usrmerge parent), replace with a real dir
  if [[ -L "$path" ]]; then
    rm -f "$path"
  fi
  if [[ -e "$path" && ! -d "$path" ]]; then
    rm -f "$path"
  fi
  if [[ -d "$path" ]]; then
    # empty existing tree without removing the directory inode
    find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
  else
    mkdir -p "$path"
  fi
}

log "Clearing distro firmware under rootfs"
ensure_real_dir "${ROOTFS}/usr/lib/firmware"

# Only create /lib/firmware → ../usr/lib/firmware when /lib is a real directory
if (( ! is_usrmerge )); then
  if [[ -L "${ROOTFS}/lib/firmware" ]]; then
    rm -f "${ROOTFS}/lib/firmware"
  elif [[ -e "${ROOTFS}/lib/firmware" && ! -d "${ROOTFS}/lib/firmware" ]]; then
    rm -f "${ROOTFS}/lib/firmware"
  fi
  if [[ ! -e "${ROOTFS}/lib/firmware" ]]; then
    mkdir -p "${ROOTFS}/lib"
    ln -sfn ../usr/lib/firmware "${ROOTFS}/lib/firmware"
  fi
fi

log "Copy firmware/ → /usr/lib/firmware"
rsync -a --delete "${BUILD}/firmware/" "${ROOTFS}/usr/lib/firmware/"

log "Clearing old modules under rootfs"
ensure_real_dir "${ROOTFS}/usr/lib/modules"

if (( ! is_usrmerge )); then
  if [[ -L "${ROOTFS}/lib/modules" ]]; then
    rm -f "${ROOTFS}/lib/modules"
  fi
  if [[ ! -e "${ROOTFS}/lib/modules" ]]; then
    mkdir -p "${ROOTFS}/lib"
    ln -sfn ../usr/lib/modules "${ROOTFS}/lib/modules"
  fi
fi

log "Copy modules/ → /usr/lib/modules"
rsync -a --delete "${BUILD}/modules/" "${ROOTFS}/usr/lib/modules/"

RELEASE="$(basename "$(find "${BUILD}/modules" -mindepth 1 -maxdepth 1 -type d | head -1)")"
install -d "${ROOTFS}/usr/share/sm8550-steamos"
printf '%s\n' "$RELEASE" > "${ROOTFS}/usr/share/sm8550-steamos/kernel-release"
printf '%s\n' "$BUILD" > "${ROOTFS}/usr/share/sm8550-steamos/kernel-build-path"

FW="$(du -sh "${ROOTFS}/usr/lib/firmware" | awk '{print $1}')"
MOD="$(du -sh "${ROOTFS}/usr/lib/modules" | awk '{print $1}')"
log "Kernel installed (firmware=${FW}, modules=${MOD}, release=${RELEASE})"
log "boot/KERNEL will be placed on VFAT by make-disk-image.sh"
