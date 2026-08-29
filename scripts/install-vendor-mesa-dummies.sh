#!/usr/bin/env bash
# Empty placeholder debs so apt stays usable after Ubuntu Mesa is purged + pinned.
# Keep real libgbm1/libgbm-dev installed; only replace stock Mesa package names that
# would otherwise force Ubuntu's Mesa back in.
#
# Usage: install-vendor-mesa-dummies.sh <rootfs>
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
MESA_VER="${MESA_VER:-26.1.6}"
VER="99:${MESA_VER}-sm8550vendor1"

log() { printf '==> [mesa-dummies] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ "${EUID}" -eq 0 ]] || die "Run as root"

ARCH="$(chroot "$ROOTFS" dpkg --print-architecture 2>/dev/null || echo arm64)"
WORKDIR="$(mktemp -d /tmp/mesa-dummies.XXXXXX)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# Names Ubuntu still Depends on after stock Mesa is gone.
DUMMIES=(
  libegl-mesa0
  libglx-mesa0
  libgl1-mesa-dri
  libgl1-mesa-glx
  mesa-libgallium
  mesa-vulkan-drivers
  mesa-va-drivers
  mesa-vdpau-drivers
)

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
      "Section: libs" \
      "Priority: optional" \
      "Multi-Arch: same"
    printf '%s\n' \
      "Description: Vendor Mesa placeholder (${name})" \
      " Empty package so apt remains consistent after Ubuntu stock Mesa is" \
      " purged. Real GL/VK/EGL/GBM libs come from the SM8550 vendor Mesa" \
      " ${MESA_VER} stack under /usr/lib."
  } >"${dir}/DEBIAN/control"
  dpkg-deb --root-owner-group --build "$dir" "${WORKDIR}/${name}.deb" >/dev/null
}

log "Building placeholders (${VER}, arch=${ARCH})"
for name in "${DUMMIES[@]}"; do
  build_dummy "$name"
done

log "Installing placeholders into ${ROOTFS} (force-depends; keep vendor .so)"
install -d "${ROOTFS}/tmp/mesa-dummies"
cp -a "${WORKDIR}"/*.deb "${ROOTFS}/tmp/mesa-dummies/"
chroot "$ROOTFS" bash -c 'dpkg -i --force-depends --force-conflicts /tmp/mesa-dummies/*.deb'
rm -rf "${ROOTFS}/tmp/mesa-dummies"

log "Hold placeholders so apt does not replace them with Ubuntu Mesa"
chroot "$ROOTFS" apt-mark hold "${DUMMIES[@]}" 2>/dev/null || true

# Reinstall vendor Mesa if dpkg/apt touched any of the runtime files on disk.
MESA_BUILD="${ROOT_DIR}/output/work/mesa-${MESA_VER}"
libdir="${ROOTFS}/usr/lib/aarch64-linux-gnu"
gallium_dest="${libdir}/libgallium-${MESA_VER}.so"
gallium_src="${MESA_BUILD}/src/gallium/targets/dri/libgallium-${MESA_VER}.so"

restore_from_meson() {
  [[ -f "${MESA_BUILD}/build.ninja" ]] || return 1
  log "Re-install vendor Mesa from meson build (atomic stack)"
  DESTDIR="$ROOTFS" meson install -C "$MESA_BUILD" --no-rebuild
}

need_restore=0
for f in \
  "${libdir}/libgbm.so.1" \
  "${libdir}/libEGL_mesa.so.0" \
  "${libdir}/libGLX_mesa.so.0" \
  "${gallium_dest}" \
  "${libdir}/dri/msm_dri.so"
do
  [[ -e "$f" ]] || need_restore=1
done

gallium_mismatch=0
if [[ -f "$gallium_dest" && -f "$gallium_src" ]]; then
  if ! cmp -s "$gallium_dest" "$gallium_src"; then
    log "WARN: gallium on rootfs != meson build output (orphan build)"
    gallium_mismatch=1
  fi
elif [[ -f "$gallium_dest" && ! -f "$gallium_src" ]]; then
  log "WARN: meson build missing — cannot verify gallium"
  gallium_mismatch=1
fi

if [[ "$need_restore" -eq 1 || "$gallium_mismatch" -eq 1 ]]; then
  if restore_from_meson; then
    :
  elif [[ -x "${ROOT_DIR}/scripts/sync-vendor-mesa-golden.sh" ]]; then
    log "meson restore unavailable — sync golden gallium + Turnip"
    GOLDEN_ROOTFS="${GOLDEN_ROOTFS:-}" \
      "${ROOT_DIR}/scripts/sync-vendor-mesa-golden.sh" "$ROOTFS" || true
  else
    die "Vendor Mesa incomplete after dummy debs — run: sudo ./scripts/reinstall-mesa-into-rootfs.sh ${ROOTFS}"
  fi
fi

if [[ -x "${ROOT_DIR}/scripts/verify-vendor-mesa-stack.sh" ]]; then
  "${ROOT_DIR}/scripts/verify-vendor-mesa-stack.sh" "$ROOTFS"
fi

install -D -m 0644 \
  "${ROOT_DIR}/config/apt-preferences/99-block-ubuntu-mesa" \
  "${ROOTFS}/etc/apt/preferences.d/99-block-ubuntu-mesa"
chown root:root "${ROOTFS}/etc/apt/preferences.d/99-block-ubuntu-mesa"
chmod 0644 "${ROOTFS}/etc/apt/preferences.d/99-block-ubuntu-mesa"

log "Done (${VER})"
