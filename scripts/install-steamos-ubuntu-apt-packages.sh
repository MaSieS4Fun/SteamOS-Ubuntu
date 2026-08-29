#!/usr/bin/env bash
# Install MaSi .deb packages via apt (not raw dpkg) so devices can apt upgrade later.
#
# Image bake uses a hybrid kernel path:
#   1) build-image already flashed firmware/modules + VFAT KERNEL from vendor/kernel/output/
#   2) this script installs masi-kernel-edge-sm8550 .deb with STEAMOS_APT_BAKE=1
#      → postinst skips re-flash, writes dpkg stamp + embeds bundle for future apt upgrade
#
# Usage:
#   sudo ./scripts/install-steamos-ubuntu-apt-packages.sh [rootfs]
#   sudo ./scripts/install-steamos-ubuntu-apt-packages.sh /          # live system
#
# Env:
#   SKIP_STEAMOS_APT_PACKAGES=1
#   BUILD_KERNEL_DEB=1 (default via build-debs.sh)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
# shellcheck source=lib/rootfs-guard.sh
source "${ROOT_DIR}/scripts/lib/rootfs-guard.sh"

log() { printf '==> [apt-bake] %s\n' "$*" >&2; }
die() { printf 'ERROR: [apt-bake] %s\n' "$*" >&2; exit 1; }

[[ "${SKIP_STEAMOS_APT_PACKAGES:-0}" == "1" ]] && { log "SKIP (SKIP_STEAMOS_APT_PACKAGES=1)"; exit 0; }
[[ "${EUID}" -eq 0 ]] || die "Run as root"

if [[ "${ROOTFS}" == "/" ]]; then
    LIVE=1
else
    LIVE=0
    require_rootfs "$ROOTFS"
fi

DEBS_SRC="${ROOT_DIR}/output/debs"
if [[ "${LIVE}" -eq 1 ]]; then
    DEBS_DST="/var/cache/steamos-ubuntu/debs"
else
    DEBS_DST="${ROOTFS}/var/cache/steamos-ubuntu/debs"
fi

build_local_debs() {
    # channel.conf must not inherit stripped KERNEL_VER=7.2.2 from create-image
    (
        unset KERNEL_VER KERNEL_RELEASE PKG_MASI_KERNEL_EDGE_SM8550 || true
        # shellcheck source=packaging/apt/channel.conf
        source "${ROOT_DIR}/packaging/apt/channel.conf"
        export KERNEL_VER KERNEL_RELEASE PKG_MASI_KERNEL_EDGE_SM8550
        "${ROOT_DIR}/scripts/build-debs.sh"
    )
}

pick_pkg_deb() {
    local pkg="$1" deb base
    for deb in "${staged[@]}"; do
        base="$(basename "$deb")"
        case "$base" in
        "${pkg}_"*.deb)
            printf '%s\n' "$deb"
            return 0
            ;;
        esac
    done
    return 1
}

shopt -s nullglob
src_debs=( "${DEBS_SRC}"/*.deb )
if ((${#src_debs[@]} == 0)); then
    log "No output/debs — building packages (kernel kbase embedded)…"
    build_local_debs
    src_debs=( "${DEBS_SRC}"/*.deb )
else
    kernel_ok=0
    for deb in "${src_debs[@]}"; do
        [[ "$(basename "$deb")" == masi-kernel-edge-sm8550_*edge-sm8550*.deb ]] && kernel_ok=1
    done
    if [[ "${kernel_ok}" -eq 0 ]]; then
        log "Rebuilding debs — kernel .deb must contain edge-sm8550 in version"
        build_local_debs
        src_debs=( "${DEBS_SRC}"/*.deb )
    fi
fi
((${#src_debs[@]})) || die "missing ${DEBS_SRC}/*.deb — run ./scripts/build-debs.sh"

log "Staging ${#src_debs[@]} debs → ${DEBS_DST}"
install -d "${DEBS_DST}"
find "${DEBS_DST}" -maxdepth 1 -name '*.deb' -delete 2>/dev/null || true
cp -a "${src_debs[@]}" "${DEBS_DST}/"

staged=( "${DEBS_DST}"/*.deb )
((${#staged[@]})) || die "copy to ${DEBS_DST} failed (expected ${#src_debs[@]} files)"

# Stable install order (metapackage last) — match by package name, not cwd glob
ordered=()
for pkg in \
    mesa-easy-manager \
    easy-ufs-install \
    proton-arm-easy-manager \
    no-steam-games \
    gyro-desktop \
    masi-kernel-edge-sm8550 \
    steamos-ubuntu-apps
do
    deb="$(pick_pkg_deb "$pkg")" || die "missing ${pkg} .deb in ${DEBS_DST} (have: $(ls -1 "${DEBS_DST}"))"
    ordered+=("${deb}")
done
shopt -u nullglob

((${#ordered[@]} == 7)) || die "expected 7 debs, got ${#ordered[@]}"

log "Installing MaSi packages via apt (registers origin for future apt upgrade)…"

if [[ "${LIVE}" -eq 1 ]]; then
    env STEAMOS_APT_BAKE=1 DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --allow-downgrades --reinstall "${ordered[@]}"
else
    rootfs_chroot_prep
    trap 'rootfs_chroot_cleanup' EXIT
    chroot_paths=()
    for deb in "${ordered[@]}"; do
        chroot_paths+=("/var/cache/steamos-ubuntu/debs/$(basename "${deb}")")
    done
    chroot "${ROOTFS}" env STEAMOS_APT_BAKE=1 DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --allow-downgrades --reinstall "${chroot_paths[@]}"
fi

log "Installed via apt:"
if [[ "${LIVE}" -eq 1 ]]; then
    dpkg -l mesa-easy-manager easy-ufs-install proton-arm-easy-manager \
        no-steam-games gyro-desktop masi-kernel-edge-sm8550 steamos-ubuntu-apps \
        2>/dev/null | tail -n +2 || true
else
    chroot "${ROOTFS}" dpkg -l \
        mesa-easy-manager easy-ufs-install proton-arm-easy-manager \
        no-steam-games gyro-desktop masi-kernel-edge-sm8550 steamos-ubuntu-apps \
        2>/dev/null | tail -n +2 || true
fi

log "Done — devices can: sudo apt update && sudo apt upgrade"
