#!/usr/bin/env bash
# Ensure abootimg is present (Easy UFS Installer packs Android boot images).
#
# Bake: call from finalize-handheld-rootfs.sh after apt sources work:
#   "${ROOT_DIR}/scripts/ensure-abootimg.sh" "$ROOTFS"
# Or add "abootimg" to packages/* (see packages/ufs-tools).
set -euo pipefail

ROOTFS="${1:-/}"
export DEBIAN_FRONTEND=noninteractive

if [[ "$ROOTFS" == "/" ]]; then
  apt-get install -y --no-install-recommends abootimg
else
  [[ -d "${ROOTFS}/usr" ]] || { echo "Usage: $0 <rootfs>" >&2; exit 1; }
  chroot "$ROOTFS" apt-get install -y --no-install-recommends abootimg
fi
