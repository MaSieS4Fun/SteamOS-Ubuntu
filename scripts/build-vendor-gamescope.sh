#!/usr/bin/env bash
# Build Adreno 740–adapted gamescope from vendor/gamescope into rootfs.
# Usage: build-vendor-gamescope.sh <rootfs>
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
SRC="${ROOT_DIR}/vendor/gamescope"
BUILD_DIR="${ROOT_DIR}/output/work/gamescope-build"
JOBS="${JOBS:-$(nproc)}"

log() { printf '==> [gamescope] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ -f "${SRC}/meson.build" ]] || die "Missing vendor/gamescope"

need_cmd() { command -v "$1" >/dev/null || die "Missing tool: $1"; }
need_cmd meson
need_cmd ninja
need_cmd git

log "Updating gamescope submodules"
(
  cd "$SRC"
  git submodule update --init --recursive 2>/dev/null \
    || git submodule update --init 2>/dev/null \
    || true
)

mkdir -p "$(dirname "$BUILD_DIR")"
# Stale/partial meson dirs (e.g. failed option names) break --reconfigure; wipe if incomplete.
if [[ -d "$BUILD_DIR" && ! -f "${BUILD_DIR}/build.ninja" ]]; then
  log "Removing incomplete meson dir ${BUILD_DIR}"
  rm -rf "$BUILD_DIR"
fi
if [[ "${FORCE_GAMESCOPE_REBUILD:-0}" == "1" ]]; then
  log "FORCE_GAMESCOPE_REBUILD=1 — wiping ${BUILD_DIR}"
  rm -rf "$BUILD_DIR"
fi

log "Meson setup → ${BUILD_DIR}"
MESON_OPTS=(
  --prefix=/usr/local
  --buildtype=release
  -Dpipewire=enabled
  -Ddrm_backend=enabled
  -Dsdl2_backend=enabled
  -Davif_screenshots=enabled
  -Dinput_emulation=enabled
  -Denable_gamescope=true
  -Denable_gamescope_wsi_layer=true
  -Denable_openvr_support=false
  -Dbenchmark=disabled
  -Drt_cap=enabled
)
if [[ ! -f "${BUILD_DIR}/build.ninja" ]]; then
  meson setup "$BUILD_DIR" "$SRC" "${MESON_OPTS[@]}"
else
  meson setup --reconfigure "$BUILD_DIR" "$SRC" "${MESON_OPTS[@]}" || true
fi

log "Compiling vendor gamescope (Adreno)"
meson compile -C "$BUILD_DIR" -j "$JOBS"

log "Installing gamescope into rootfs (/usr/local)"
# Remove any previous host-copied binary so we never ship stock gamescope by mistake
rm -f "${ROOTFS}/usr/local/bin/gamescope" "${ROOTFS}/usr/bin/gamescope"
DESTDIR="$ROOTFS" meson install -C "$BUILD_DIR" --no-rebuild --skip-subprojects

[[ -x "${ROOTFS}/usr/local/bin/gamescope" ]] \
  || die "gamescope missing after install"

# gamescope links static wlroots from subproject; also copy shared host .so if present
for ver in 0.18 0.19; do
  if [[ -e /usr/local/lib/aarch64-linux-gnu/libwlroots-${ver}.so ]]; then
    install -d "${ROOTFS}/usr/local/lib/aarch64-linux-gnu"
    cp -a /usr/local/lib/aarch64-linux-gnu/libwlroots-${ver}.so* \
      "${ROOTFS}/usr/local/lib/aarch64-linux-gnu/" 2>/dev/null || true
    log "Copied host libwlroots-${ver} into rootfs"
  fi
done

# libliftoff from distro (gamescope NEEDED)
install -d "${ROOTFS}/usr/lib/aarch64-linux-gnu"
cp -a /usr/lib/aarch64-linux-gnu/libliftoff.so* \
  "${ROOTFS}/usr/lib/aarch64-linux-gnu/" 2>/dev/null || true

# Prefer /usr/local on PATH
install -d "${ROOTFS}/etc/profile.d"
cat >"${ROOTFS}/etc/profile.d/zz-steamos-local-path.sh" <<'EOF'
export PATH="/usr/local/bin:${PATH}"
export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
EOF

log "Vendor gamescope installed: ${ROOTFS}/usr/local/bin/gamescope"

log "Post-compile library gate (install missing into rootfs)"
"${ROOT_DIR}/scripts/ensure-gamescope-libs.sh" "$ROOTFS" "${ROOTFS}/usr/local/bin/gamescope"
