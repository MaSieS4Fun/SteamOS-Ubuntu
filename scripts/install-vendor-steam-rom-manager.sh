#!/usr/bin/env bash
# Install Steam ROM Manager into rootfs from vendor/SteamROMManager
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
ROOTFS="$(cd "$ROOTFS" && pwd)"
VENDOR="${ROOT_DIR}/vendor/SteamROMManager"

log() { printf '==> [steam-rom-manager] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"

if [[ ! -d "${VENDOR}/linux-arm64-unpacked" ]]; then
    log "Missing vendor tree — fetching Steam ROM Manager…"
    "${ROOT_DIR}/scripts/fetch-steam-rom-manager.sh"
fi

[[ -d "${VENDOR}/linux-arm64-unpacked" ]] || die "Missing ${VENDOR}/linux-arm64-unpacked"

log "Installing Steam ROM Manager → ${ROOTFS}/opt/SteamROMManager"
rm -rf "${ROOTFS}/opt/SteamROMManager"
mkdir -p "${ROOTFS}/opt/SteamROMManager" \
         "${ROOTFS}/usr/bin" \
         "${ROOTFS}/usr/share/applications" \
         "${ROOTFS}/usr/share/icons/hicolor/256x256/apps"

cp -a "${VENDOR}/linux-arm64-unpacked/." "${ROOTFS}/opt/SteamROMManager/"

cat > "${ROOTFS}/usr/bin/steam-rom-manager" <<'LAUNCHER'
#!/bin/sh
exec /opt/SteamROMManager/steam-rom-manager --no-sandbox "$@"
LAUNCHER
chmod 755 "${ROOTFS}/usr/bin/steam-rom-manager"

cp -a "${VENDOR}/steam-rom-manager.png" \
  "${ROOTFS}/usr/share/icons/hicolor/256x256/apps/steam-rom-manager.png"

cat > "${ROOTFS}/usr/share/applications/steam-rom-manager.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Steam ROM Manager
Comment=Manage ROMs and add them to Steam
Exec=steam-rom-manager
Icon=steam-rom-manager
Type=Application
Categories=Game;
Terminal=false
DESKTOP

log "Done"
