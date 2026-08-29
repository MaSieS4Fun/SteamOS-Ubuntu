#!/usr/bin/env bash
# Optional deep clean: cloud-init, snap, ubuntu user, motd-news, etc.
# NOT run during image bake — only when you explicitly want a trimmed SD.
#
# Usage: cleanup-ubuntu-leftovers-aggressive.sh <rootfs>
set -euo pipefail

ROOTFS="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log() { printf '==> [ubuntu-deep] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ "${EUID}" -eq 0 ]] || die "Run as root"

"${ROOT_DIR}/scripts/cleanup-ubuntu-leftovers.sh" "$ROOTFS"

mask_unit() {
  local u="$1"
  mkdir -p "${ROOTFS}/etc/systemd/system"
  ln -sfn /dev/null "${ROOTFS}/etc/systemd/system/${u}"
}

rm -rf "${ROOTFS}/etc/cloud" "${ROOTFS}/var/lib/cloud" 2>/dev/null || true
mask_unit cloud-init.service
mask_unit cloud-init-local.service
mask_unit cloud-config.service
mask_unit cloud-final.service

rm -f \
  "${ROOTFS}/etc/update-motd.d/50-motd-news" \
  "${ROOTFS}/etc/update-motd.d/60-unminimize" \
  "${ROOTFS}/etc/update-motd.d/91-contract-ua-esm-status" \
  "${ROOTFS}/etc/update-motd.d/91-release-upgrade" \
  "${ROOTFS}/etc/update-motd.d/95-hwe-eol" \
  "${ROOTFS}/etc/apt/preferences.d/ubuntu-pro-esm-apps" \
  "${ROOTFS}/etc/apt/preferences.d/ubuntu-pro-esm-infra" \
  "${ROOTFS}/etc/skel/examples.desktop" \
  "${ROOTFS}/home/.directory" \
  2>/dev/null || true
mask_unit ubuntu-advantage.service
mask_unit ua-reboot-cmds.service
mask_unit ua-timer.timer
mask_unit motd-news.timer

rm -rf "${ROOTFS}/snap" "${ROOTFS}/var/snap" "${ROOTFS}/var/lib/snapd" \
  "${ROOTFS}/var/cache/snapd" "${ROOTFS}/.rock" 2>/dev/null || true
mask_unit snapd.service
mask_unit snapd.socket
mask_unit snapd.seeded.service
mask_unit snapd.apparmor.service

# Lock ubuntu (do not delete — uid 1000 slot can matter for overlays)
if grep -q '^ubuntu:' "${ROOTFS}/etc/passwd"; then
  chroot "$ROOTFS" passwd -l ubuntu 2>/dev/null || true
  chroot "$ROOTFS" usermod -s /usr/sbin/nologin ubuntu 2>/dev/null || true
  log "Locked user ubuntu (not removed from passwd)"
fi

log "Deep Ubuntu trim done"
