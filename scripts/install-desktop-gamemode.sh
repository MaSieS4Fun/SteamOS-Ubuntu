#!/usr/bin/env bash
# Session select stays from vendor/Desktop_gamemode/.
# The Games-menu "Desktop Gaming Mode" launcher is not installed.
# The desktop icon is vendor/SteamARM/steambp.desktop (copied as-is).
#
#   steamos-session-select   → /usr/bin/steamos-session-select
#   SteamARM/steambp.desktop → ~/Desktop and /etc/skel/Desktop
#
# Usage:
#   sudo ./scripts/install-desktop-gamemode.sh           # live system (/)
#   sudo ./scripts/install-desktop-gamemode.sh /path/to/rootfs
set -euo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${_HERE}/.." && pwd)"
VENDOR="${ROOT_DIR}/vendor/Desktop_gamemode"
STEAMBP_SRC="${ROOT_DIR}/vendor/SteamARM/steambp.desktop"
NOTES_SRC="${ROOT_DIR}/system_files/etc/skel/Desktop/usage-notes.txt"
ROOTFS="${1:-/}"

log() { printf '==> [desktop-gamemode] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -d "$VENDOR" ]] || die "Missing ${VENDOR}"
[[ -f "${VENDOR}/steamos-session-select" ]] || die "Missing steamos-session-select"
[[ -f "$STEAMBP_SRC" ]] || die "Missing ${STEAMBP_SRC}"

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

DESKTOP_DIR="$(path /home/steam/Desktop)"
APPS_DIR="$(path /usr/local/share/applications)"
SESSION_BIN="$(path /usr/bin/steamos-session-select)"

install -d -m 0755 "$DESKTOP_DIR" "$APPS_DIR" "$(dirname "$SESSION_BIN")"

log "Remove Desktop Gaming Mode from the Games menu"
rm -f \
  "${APPS_DIR}/steambp.desktop" \
  "$(path /usr/share/applications)/steambp.desktop" \
  "$(path /usr/share/applications)/steamos-gaming-mode.desktop" \
  "${DESKTOP_DIR}/steamos-gaming-mode.desktop" \
  2>/dev/null || true

SKEL_DESKTOP="$(path /etc/skel/Desktop)"
install -d -m 0755 "$DESKTOP_DIR" "$SKEL_DESKTOP"
log "Desktop icon: ${STEAMBP_SRC}"
install -m 0755 "$STEAMBP_SRC" "${DESKTOP_DIR}/steambp.desktop"
install -m 0755 "$STEAMBP_SRC" "${SKEL_DESKTOP}/steambp.desktop"
if [[ -f "$NOTES_SRC" ]]; then
  install -m 0644 "$NOTES_SRC" "${DESKTOP_DIR}/usage-notes.txt"
  install -m 0644 "$NOTES_SRC" "${SKEL_DESKTOP}/usage-notes.txt"
else
  log "WARN: missing ${NOTES_SRC}"
fi
STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "$(path /etc/passwd)" 2>/dev/null || true)"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "$(path /etc/passwd)" 2>/dev/null || true)"
if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
  chown "${STEAM_UID}:${STEAM_GID}" \
    "${DESKTOP_DIR}/steambp.desktop" \
    "${DESKTOP_DIR}/usage-notes.txt" \
    2>/dev/null || true
fi

log "Install steamos-session-select → ${SESSION_BIN}"
install -m 0755 "${VENDOR}/steamos-session-select" "$SESSION_BIN"

# Keep system_files in sync for future overlays (copy only; vendor stays untouched)
SYS_SEL="${ROOT_DIR}/system_files/usr/bin/steamos-session-select"
if [[ -d "${ROOT_DIR}/system_files/usr/bin" ]]; then
  install -m 0755 "${VENDOR}/steamos-session-select" "$SYS_SEL"
  log "Synced system_files copy of steamos-session-select"
fi

log "Done"
log "  Games menu: Desktop Gaming Mode removed"
log "  Desktop icon: ${DESKTOP_DIR}/steambp.desktop"
log "  Usage notes: ${DESKTOP_DIR}/usage-notes.txt"
log "  Session select: ${SESSION_BIN}"
