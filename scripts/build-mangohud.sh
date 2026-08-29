#!/usr/bin/env bash
# Build SM8550-adapted MangoHud from vendor/MangoHud into a rootfs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT_DIR}/vendor/MangoHud"
ROOTFS="${1:-}"
BUILD_DIR="${ROOT_DIR}/output/work/mangohud-build"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ -f "${SRC}/meson.build" ]] || die "Missing ${SRC}"

command -v meson >/dev/null || die "Need meson"
command -v ninja >/dev/null || die "Need ninja-build"

log "Configuring vendor MangoHud → ${BUILD_DIR}"
mkdir -p "$(dirname "$BUILD_DIR")"
if [[ -d "${BUILD_DIR}" ]]; then
  meson setup --reconfigure "${BUILD_DIR}" "${SRC}" \
    --prefix=/usr \
    --libdir=lib/aarch64-linux-gnu \
    --buildtype=release \
    -Dappend_libdir_mangohud=false \
    -Dwith_xnvctrl=disabled \
    -Dmangoapp=true \
    -Dmangohudctl=true || \
  meson setup "${BUILD_DIR}" "${SRC}" \
    --prefix=/usr \
    --libdir=lib/aarch64-linux-gnu \
    --buildtype=release \
    -Dappend_libdir_mangohud=false \
    -Dwith_xnvctrl=disabled
else
  meson setup "${BUILD_DIR}" "${SRC}" \
    --prefix=/usr \
    --libdir=lib/aarch64-linux-gnu \
    --buildtype=release \
    -Dappend_libdir_mangohud=false \
    -Dwith_xnvctrl=disabled
fi

log "Compiling MangoHud"
meson compile -C "${BUILD_DIR}"

log "Installing MangoHud into ${ROOTFS}"
DESTDIR="${ROOTFS}" meson install -C "${BUILD_DIR}" --no-rebuild

# Overlay configs: vendor/MangoHud/MangoHud/ → ~/.config/MangoHud/ (copy only)
PRESETS="${SRC}/MangoHud"
if [[ -d "$PRESETS" ]]; then
  install -d "${ROOTFS}/etc/skel/.config/MangoHud"
  cp -a "${PRESETS}/." "${ROOTFS}/etc/skel/.config/MangoHud/"
  if [[ -d "${ROOTFS}/home/steam" ]]; then
    install -d "${ROOTFS}/home/steam/.config/MangoHud"
    cp -a "${PRESETS}/." "${ROOTFS}/home/steam/.config/MangoHud/"
    chown -R --reference="${ROOTFS}/home/steam" "${ROOTFS}/home/steam/.config/MangoHud" 2>/dev/null || true
  fi
fi

log "vendor MangoHud installed"
