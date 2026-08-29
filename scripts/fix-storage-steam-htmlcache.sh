#!/usr/bin/env bash
# Clear Steam CEF htmlcache after failed boots (stale SingletonLock, partial GPU init).
# Safe on mounted rootfs; Steam recreates cache on next launch.
#
# Usage: sudo ./scripts/fix-storage-steam-htmlcache.sh [/media/odin2/STORAGE]
set -euo pipefail

ROOTFS="${1:-/media/odin2/STORAGE}"
log() { printf '==> [htmlcache] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -d "${ROOTFS}/home/steam" ]] || die "Usage: $0 [rootfs]"

CACHE="${ROOTFS}/home/steam/.local/share/Steam/config/htmlcache"
STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "${ROOTFS}/etc/passwd")"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "${ROOTFS}/etc/passwd")"

if [[ ! -d "$CACHE" ]]; then
  log "No htmlcache yet — nothing to clear"
  exit 0
fi

log "Removing ${CACHE#"$ROOTFS"}"
rm -rf "$CACHE"
mkdir -p "$CACHE"
if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
  chown "${STEAM_UID}:${STEAM_GID}" "$CACHE"
fi
chmod 0775 "$CACHE"

log "Done — Steam will rebuild CEF cache on next Gaming Mode boot"
