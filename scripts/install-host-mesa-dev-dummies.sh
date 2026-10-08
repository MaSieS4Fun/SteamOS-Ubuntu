#!/usr/bin/env bash
# Epoch-99 placeholders for Mesa -dev packages that Ubuntu Resolute still
# Depends on (libsdl2-dev → libgbm-dev) after vendor Turnip owns GBM/EGL.
#
# Ubuntu libgbm-dev is apt-pinned to -1 (99-block-ubuntu-mesa) so a plain
# `apt install libsdl2-dev` conflicts. These dummies satisfy the Depends
# without pulling Mesa 26.0 over the SM8550 stack.
#
# Usage:
#   sudo ./scripts/install-host-mesa-dev-dummies.sh
#   sudo ./scripts/install-host-mesa-dev-dummies.sh /path/to/rootfs
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-/}"
MESA_VER="${MESA_VER:-26.1.6}"
VER="99:${MESA_VER}-sm8550vendor1"

log() { printf '==> [mesa-dev-dummies] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root: sudo $0 ${TARGET}"
[[ -d "${TARGET}/usr" ]] || die "Not a rootfs: ${TARGET}"

if [[ "$TARGET" == "/" ]]; then
  ARCH="$(dpkg --print-architecture)"
  dpkg_i() { dpkg -i --force-depends --force-conflicts --force-overwrite "$@"; }
  mark_hold() { apt-mark hold "$@" 2>/dev/null || true; }
else
  ARCH="$(chroot "$TARGET" dpkg --print-architecture 2>/dev/null || echo arm64)"
  dpkg_i() {
    install -d "${TARGET}/tmp/mesa-dev-dummies"
    cp -a "$@" "${TARGET}/tmp/mesa-dev-dummies/"
    chroot "$TARGET" bash -c 'dpkg -i --force-depends --force-conflicts --force-overwrite /tmp/mesa-dev-dummies/*.deb'
    rm -rf "${TARGET}/tmp/mesa-dev-dummies"
  }
  mark_hold() { chroot "$TARGET" apt-mark hold "$@" 2>/dev/null || true; }
fi

WORKDIR="$(mktemp -d /tmp/mesa-dev-dummies.XXXXXX)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# Headers: prefer already-installed vendor Mesa, then the bake source tree.
copy_gbm_headers() {
  local dest="$1"
  local src=""
  local candidate
  for candidate in \
    "${TARGET}/usr/include/gbm.h" \
    /usr/include/gbm.h \
    "${ROOT_DIR}/output/rootfs/usr/include/gbm.h" \
    "${ROOT_DIR}/output/src/mesa-${MESA_VER}/src/gbm/main/gbm.h"
  do
    if [[ -f "$candidate" ]]; then
      src="$candidate"
      break
    fi
  done
  [[ -n "$src" ]] || return 0
  install -D -m 0644 "$src" "${dest}/usr/include/gbm.h"
  # Companion backend header if present next to gbm.h
  local side
  side="$(dirname "$src")/gbm_backend_abi.h"
  [[ -f "$side" ]] && install -D -m 0644 "$side" "${dest}/usr/include/gbm_backend_abi.h"
  install -d "${dest}/usr/lib/${ARCH}-linux-gnu/pkgconfig"
  cat >"${dest}/usr/lib/${ARCH}-linux-gnu/pkgconfig/gbm.pc" <<EOF
prefix=/usr
libdir=\${prefix}/lib/${ARCH}-linux-gnu
includedir=\${prefix}/include

Name: gbm
Description: Vendor Mesa GBM (SM8550 placeholder)
Version: ${MESA_VER}
Libs: -L\${libdir} -lgbm
Cflags: -I\${includedir}
EOF
}

build_dummy() {
  local name="$1"
  local dir="${WORKDIR}/${name}"
  rm -rf "$dir"
  mkdir -p "${dir}/DEBIAN"
  {
    printf '%s\n' \
      "Package: ${name}" \
      "Version: ${VER}" \
      "Architecture: ${ARCH}" \
      "Maintainer: SteamOS-Ubuntu <steamos-ubuntu@local>" \
      "Section: libdevel" \
      "Priority: optional" \
      "Multi-Arch: same" \
      "Depends: libc6" \
      "Provides: ${name}" \
      "Replaces: ${name}" \
      "Description: Vendor Mesa -dev placeholder (${name})" \
      " Satisfies apt Depends (e.g. libsdl2-dev) without installing Ubuntu" \
      " Mesa ${MESA_VER%%.*}.0. Real libs come from vendor Turnip/GBM."
  } >"${dir}/DEBIAN/control"
  if [[ "$name" == "libgbm-dev" ]]; then
    copy_gbm_headers "$dir"
  fi
  dpkg-deb --root-owner-group --build "$dir" "${WORKDIR}/${name}.deb" >/dev/null
}

DUMMIES=(
  libgbm-dev
  libegl1-mesa-dev
  libgles2-mesa-dev
)

log "Building -dev placeholders (${VER}, arch=${ARCH}) for ${TARGET}"
for name in "${DUMMIES[@]}"; do
  build_dummy "$name"
done

log "Installing placeholders (dpkg; apt pin blocks Ubuntu versions)"
dpkg_i "${WORKDIR}"/*.deb
mark_hold "${DUMMIES[@]}"
log "Done — libsdl2-dev can be installed without Ubuntu libgbm-dev"
