#!/usr/bin/env bash
# Fix /var/cache/man ownership so apt man-db triggers stop printing
# "mandb: can't chmod ... Operation not permitted".
#
# Live handheld:
#   sudo ./scripts/fix-man-cache.sh
#
# Rootfs bake (also runs from fix-rootfs-ownership.sh):
#   sudo ./scripts/fix-man-cache.sh /path/to/rootfs
set -euo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/rootfs-guard.sh
source "${_HERE}/lib/rootfs-guard.sh"

ROOTFS="${1:-/}"
log() { printf '==> [man-cache] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -d "${ROOTFS}/usr" ]] || die "Not a rootfs: ${ROOTFS}"
if [[ "$ROOTFS" == "/" ]]; then
  : # live OK
else
  require_rootfs "$ROOTFS"
  ROOTFS="${ROOTFS%/}"
fi

resolve_ugid() {
  local name="$1" kind="$2"
  local file
  if [[ "$kind" == uid ]]; then
    file="${ROOTFS}/etc/passwd"
    awk -F: -v n="$name" '$1==n {print $3; exit}' "$file" 2>/dev/null || true
  else
    file="${ROOTFS}/etc/group"
    awk -F: -v n="$name" '$1==n {print $3; exit}' "$file" 2>/dev/null || true
  fi
}

man_dir="/var/cache/man"
[[ "$ROOTFS" != "/" ]] && man_dir="${ROOTFS}/var/cache/man"
mkdir -p "$man_dir"

man_uid="$(resolve_ugid man uid)"
man_gid="$(resolve_ugid man gid)"
if [[ -n "$man_uid" && -n "$man_gid" ]]; then
  chown -R "${man_uid}:${man_gid}" "$man_dir"
elif [[ "$ROOTFS" == "/" ]]; then
  chown -R man:man "$man_dir"
else
  die "man user/group missing in ${ROOTFS}/etc/passwd|group"
fi

find "$man_dir" -type d -exec chmod 0755 {} + 2>/dev/null || true
find "$man_dir" -type f -exec chmod 0644 {} + 2>/dev/null || true
chmod 0755 "$man_dir"

log "Fixed ${man_dir} → man:man 0755"

if [[ "$ROOTFS" == "/" ]] && command -v mandb >/dev/null 2>&1; then
  # Quiet rebuild as man user (same as trigger)
  if command -v runuser >/dev/null 2>&1; then
    runuser -u man -- mandb -pq 2>/dev/null || true
  elif command -v setpriv >/dev/null 2>&1; then
    setpriv --reuid=man --regid=man --init-groups -- mandb -pq 2>/dev/null || true
  fi
  log "Smoke: sudo apt-get install -y --reinstall tree  (should have no mandb chmod errors)"
fi
