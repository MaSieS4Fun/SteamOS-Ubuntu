#!/usr/bin/env bash
# Install Desktop Gaming Mode assets from vendor/Desktop_gamemode/.
# Run after Steam is present (steambp.desktop icon path lives under Steam).
#
# Does NOT modify vendor files — copies them as-is:
#   steambp.desktop          → ~/Desktop/ and /usr/local/share/applications/
#   steamos-session-select   → /usr/bin/steamos-session-select
#
# Usage:
#   sudo ./scripts/install-desktop-gamemode.sh           # live system (/)
#   sudo ./scripts/install-desktop-gamemode.sh /path/to/rootfs
set -euo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${_HERE}/.." && pwd)"
VENDOR="${ROOT_DIR}/vendor/Desktop_gamemode"
ROOTFS="${1:-/}"

log() { printf '==> [desktop-gamemode] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -d "$VENDOR" ]] || die "Missing ${VENDOR}"
[[ -f "${VENDOR}/steambp.desktop" ]] || die "Missing steambp.desktop"
[[ -f "${VENDOR}/steamos-session-select" ]] || die "Missing steamos-session-select"

if [[ "$ROOTFS" != "/" ]]; then
  ROOTFS="${ROOTFS%/}"
  [[ -d "${ROOTFS}/usr" ]] || die "Not a rootfs: ${ROOTFS}"
fi

path() {
  local p="$1"
  if [[ "$ROOTFS" == "/" ]]; then
    printf '%s\n' "$p"
  else
    printf '%s%s\n' "$ROOTFS" "$p"
  fi
}

STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "$(path /etc/passwd)" 2>/dev/null || echo 1000)"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "$(path /etc/passwd)" 2>/dev/null || echo 1000)"
DESKTOP_DIR="$(path /home/steam/Desktop)"
APPS_DIR="$(path /usr/local/share/applications)"
SESSION_BIN="$(path /usr/bin/steamos-session-select)"

install -d -m 0755 "$DESKTOP_DIR" "$APPS_DIR" "$(dirname "$SESSION_BIN")"

log "Install steambp.desktop → ${DESKTOP_DIR}/ and ${APPS_DIR}/"
install -m 0755 "${VENDOR}/steambp.desktop" "${DESKTOP_DIR}/steambp.desktop"
install -m 0644 "${VENDOR}/steambp.desktop" "${APPS_DIR}/steambp.desktop"
chown "${STEAM_UID}:${STEAM_GID}" "${DESKTOP_DIR}/steambp.desktop" 2>/dev/null || true

log "Install steamos-session-select → ${SESSION_BIN}"
install -m 0755 "${VENDOR}/steamos-session-select" "$SESSION_BIN"

# Keep system_files in sync for future overlays (copy only; vendor stays untouched)
SYS_SEL="${ROOT_DIR}/system_files/usr/bin/steamos-session-select"
if [[ -d "${ROOT_DIR}/system_files/usr/bin" ]]; then
  install -m 0755 "${VENDOR}/steamos-session-select" "$SYS_SEL"
  log "Synced system_files copy of steamos-session-select"
fi

log "Done"
log "  Desktop icon: ${DESKTOP_DIR}/steambp.desktop"
log "  Applications: ${APPS_DIR}/steambp.desktop"
log "  Session select: ${SESSION_BIN}"
