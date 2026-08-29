#!/usr/bin/env bash
# Reset MangoHud config that breaks Steam CEF (BMainLoop stall, no CreateBrowser).
#
# Symptom: steamos-session.log shows webhelper "Starting message loop" then stall;
# MangoHud errors "Unknown option nis_steam_sharpness" in steamwebhelper.
#
# Cause: Steam QAM wrote fsr/nis_steam_sharpness into MangoHud.conf while
# control=mangohud hooks MangoHud into steamwebhelper (CEF).
#
# Usage: sudo ./scripts/as-root.sh ./scripts/fix-steam-mango-on-storage.sh [rootfs]
set -euo pipefail

ROOTFS="${1:-/media/odin2/STORAGE}"
log() { printf '==> [fix-mango] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -d "${ROOTFS}/home/steam" ]] || die "Usage: $0 [rootfs]"

USER_MANGO="${ROOTFS}/home/steam/.config/MangoHud/steam"
STEAM_MANGO="${ROOTFS}/home/steam/.local/share/Steam/config/mangohud.conf"
SYS_MANGO="${ROOTFS}/usr/share/sm8550-steamos/MangoHud/steam/MangoHud.conf"

mkdir -p "$USER_MANGO"
if [[ -f "$SYS_MANGO" ]]; then
  install -D -m 0644 "$SYS_MANGO" "${USER_MANGO}/MangoHud.conf"
else
  printf '%s\n' 'control=mangoapp' 'preset=0' >"${USER_MANGO}/MangoHud.conf"
  chmod 0644 "${USER_MANGO}/MangoHud.conf"
fi

# Steam reads this copy too — keep in sync (may be hardlinked)
mkdir -p "$(dirname "$STEAM_MANGO")"
if [[ -e "$STEAM_MANGO" && "$STEAM_MANGO" -ef "${USER_MANGO}/MangoHud.conf" ]]; then
  : # same inode — already updated
elif [[ -e "$STEAM_MANGO" ]]; then
  cp -a "${USER_MANGO}/MangoHud.conf" "$STEAM_MANGO"
else
  ln "${USER_MANGO}/MangoHud.conf" "$STEAM_MANGO" 2>/dev/null \
    || cp -a "${USER_MANGO}/MangoHud.conf" "$STEAM_MANGO"
fi
chmod 0644 "$STEAM_MANGO"

# Fix executable bit left by bad chown passes
chmod 0644 "${USER_MANGO}/MangoHud.conf" "${USER_MANGO}/presets.conf" 2>/dev/null || true

STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "${ROOTFS}/etc/passwd")"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "${ROOTFS}/etc/passwd")"
if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
  chown -R "${STEAM_UID}:${STEAM_GID}" "${ROOTFS}/home/steam/.config/MangoHud" 2>/dev/null || true
  chown "${STEAM_UID}:${STEAM_GID}" "$STEAM_MANGO" 2>/dev/null || true
fi

log "MangoHud.conf reset:"
cat "${USER_MANGO}/MangoHud.conf"
log "Done — reboot SD and test Gaming Mode"
