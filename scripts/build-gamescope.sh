#!/usr/bin/env bash
# Build Adreno 740 gamescope from vendor/gamescope and install into a rootfs.
# Never copy a random host gamescope — always compile this tree.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT_DIR}/vendor/gamescope"
ROOTFS="${1:-}"
PREFIX="${PREFIX:-/usr/local}"
BUILD_DIR="${ROOT_DIR}/output/work/gamescope-build"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ -f "${SRC}/meson.build" ]] || die "Missing ${SRC}"

command -v meson >/dev/null || die "Need meson"
command -v ninja >/dev/null || die "Need ninja-build"
command -v g++ >/dev/null || die "Need g++"

log "Configuring vendor gamescope (Adreno) → ${BUILD_DIR}"
mkdir -p "$(dirname "$BUILD_DIR")"
if [[ -d "${BUILD_DIR}" ]]; then
  meson setup --reconfigure "${BUILD_DIR}" "${SRC}" \
    --prefix="${PREFIX}" \
    --buildtype=release \
    -Dpipewire=enabled \
    -Denable_gamescope=true \
    -Denable_gamescope_wsi_layer=true \
    -Denable_openvr_support=false \
    -Dbenchmark=disabled \
    -Dforce_fallback_for=wlroots,libliftoff,vkroots || \
  meson setup "${BUILD_DIR}" "${SRC}" \
    --prefix="${PREFIX}" \
    --buildtype=release \
    -Dpipewire=enabled \
    -Denable_gamescope=true \
    -Denable_gamescope_wsi_layer=true \
    -Denable_openvr_support=false \
    -Dbenchmark=disabled
else
  meson setup "${BUILD_DIR}" "${SRC}" \
    --prefix="${PREFIX}" \
    --buildtype=release \
    -Dpipewire=enabled \
    -Denable_gamescope=true \
    -Denable_gamescope_wsi_layer=true \
    -Denable_openvr_support=false \
    -Dbenchmark=disabled
fi

log "Compiling gamescope"
meson compile -C "${BUILD_DIR}"

log "Installing gamescope into ${ROOTFS} (prefix=${PREFIX})"
DESTDIR="${ROOTFS}" meson install -C "${BUILD_DIR}" --no-rebuild

[[ -x "${ROOTFS}${PREFIX}/bin/gamescope" ]] \
  || die "gamescope missing after install at ${ROOTFS}${PREFIX}/bin/gamescope"

# Prefer /usr/local/bin on PATH
install -d "${ROOTFS}/etc/profile.d"
cat >"${ROOTFS}/etc/profile.d/steamos-gamescope-path.sh" <<EOF
export PATH="${PREFIX}/bin:\$PATH"
EOF

log "vendor gamescope installed: $(file "${ROOTFS}${PREFIX}/bin/gamescope" | cut -d: -f2-)"
