#!/usr/bin/env bash
# Hot-fix Deck session + fixed MangoHud steam configs onto STORAGE.
#
# Usage:
#   sudo ./scripts/APPLY-QAM-MANGO-NOW.sh /media/odin2/STORAGE
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
log() { printf '==> [deck-mango] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs|STORAGE>"

if findmnt -n -o OPTIONS --target "$ROOTFS" 2>/dev/null | grep -q '\bro\b'; then
  log "Remounting $ROOTFS read-write…"
  mount -o remount,rw "$ROOTFS" || die "Cannot remount $ROOTFS rw"
fi

SRC="${ROOT_DIR}/system_files"
STEAM_HOME="${ROOTFS}/home/steam"
MANGO_STEAM="${ROOT_DIR}/vendor/MangoHud/MangoHud/steam"

[[ -f "${SRC}/usr/bin/gamescope-session" ]] || die "Missing gamescope-session"
[[ -f "${SRC}/usr/libexec/steamos-ubuntu/launch-steam" ]] || die "Missing launch-steam"
[[ -d "$MANGO_STEAM" ]] || die "Missing vendor/MangoHud/MangoHud/steam"

install -D -m 0755 "${SRC}/usr/bin/gamescope-session" \
  "${ROOTFS}/usr/bin/gamescope-session"
install -D -m 0755 "${SRC}/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"
log "Installed gamescope-session + launch-steam"

install -d "${ROOTFS}/usr/share/sm8550-steamos/MangoHud/steam"
cp -a "${MANGO_STEAM}/." "${ROOTFS}/usr/share/sm8550-steamos/MangoHud/steam/"
log "System presets → /usr/share/sm8550-steamos/MangoHud/steam/"

install -d "${ROOTFS}/var/lib/steamos-ubuntu"
printf 'deck\n' > "${ROOTFS}/var/lib/steamos-ubuntu/steam-mode"
log "steam-mode=deck"

if [[ -d "$STEAM_HOME" ]]; then
  install -d "${STEAM_HOME}/.config/MangoHud/steam" \
    "${STEAM_HOME}/.local/share/Steam/config"
  # Refresh presets; seed MangoHud.conf only if missing (keep QAM preset=)
  cp -a "${MANGO_STEAM}/presets.conf" \
    "${STEAM_HOME}/.config/MangoHud/steam/presets.conf"
  if [[ ! -f "${STEAM_HOME}/.config/MangoHud/steam/MangoHud.conf" ]]; then
    cp -a "${MANGO_STEAM}/MangoHud.conf" \
      "${STEAM_HOME}/.config/MangoHud/steam/MangoHud.conf"
  else
    grep -q '^control=mangohud' "${STEAM_HOME}/.config/MangoHud/steam/MangoHud.conf" 2>/dev/null \
      || sed -i '1i control=mangohud' "${STEAM_HOME}/.config/MangoHud/steam/MangoHud.conf"
  fi
  if [[ -L "${STEAM_HOME}/.config/MangoHud/steam/MangoHud.conf" ]]; then
    rm -f "${STEAM_HOME}/.config/MangoHud/steam/MangoHud.conf"
    cp -a "${MANGO_STEAM}/MangoHud.conf" \
      "${STEAM_HOME}/.config/MangoHud/steam/MangoHud.conf"
  fi
  CONF="${STEAM_HOME}/.config/MangoHud/steam/MangoHud.conf"
  FALLBACK="${STEAM_HOME}/.local/share/Steam/config/mangohud.conf"
  rm -f "$FALLBACK"
  ln "$CONF" "$FALLBACK" 2>/dev/null || cp -a "$CONF" "$FALLBACK"
  chown -R --reference="$STEAM_HOME" "${STEAM_HOME}/.config/MangoHud" \
    "${STEAM_HOME}/.local/share/Steam/config" 2>/dev/null || true
  log "User conf → ${CONF}"
fi

log "Done. Re-enter Gaming Mode. Log should show:"
log "  mangoapp: CONFIGFILE=/home/steam/.config/MangoHud/steam/MangoHud.conf"
log "Keep checking systemdisplaymanager.txt still says wayland: modeset"
