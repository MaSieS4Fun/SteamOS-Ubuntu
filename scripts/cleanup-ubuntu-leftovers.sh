#!/usr/bin/env bash
# Remove Kubuntu desktop junk from a rootfs. Safe for image bake.
# Does NOT touch cloud-init, snap, ubuntu user, or passwd — those can break
# first-boot networking / Plasma on some images.
#
# Usage: cleanup-ubuntu-leftovers.sh <rootfs>
set -euo pipefail

ROOTFS="${1:-}"
log() { printf '==> [ubuntu-leftover] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ "${EUID}" -eq 0 ]] || die "Run as root"

# Kubuntu / Focus website launchers on Desktop and in applications/
rm -f \
  "${ROOTFS}/usr/share/applications/org.kfocus.web.howtos.desktop" \
  "${ROOTFS}/usr/share/applications/org.kubuntu.web.home.desktop" \
  "${ROOTFS}/usr/share/applications/org.kubuntu.restore-desktop-links.desktop" \
  "${ROOTFS}/usr/share/applications/org.kubuntu.driver-manager.desktop" \
  "${ROOTFS}/usr/share/applications/org.kubuntu.manage-software.desktop" \
  "${ROOTFS}/usr/bin/kubuntu-restore-desktop-links" \
  "${ROOTFS}/usr/bin/kubuntu-manage-software" \
  2>/dev/null || true

rm -f \
  "${ROOTFS}/home/steam/Desktop/"*howto* \
  "${ROOTFS}/home/steam/Desktop/"*HOW* \
  "${ROOTFS}/home/steam/Desktop/"*kubuntu* \
  "${ROOTFS}/home/steam/Desktop/"*Kubuntu* \
  "${ROOTFS}/home/steam/Desktop/org.kfocus."* \
  "${ROOTFS}/home/steam/Desktop/org.kubuntu."* \
  2>/dev/null || true

# Kubuntu plymouth themes (keep breeze / default)
rm -rf \
  "${ROOTFS}/usr/share/plymouth/themes/kubuntu-logo" \
  "${ROOTFS}/usr/share/plymouth/themes/kubuntu-text" \
  2>/dev/null || true

log "Removed Kubuntu desktop branding (cloud-init/ubuntu user untouched)"
