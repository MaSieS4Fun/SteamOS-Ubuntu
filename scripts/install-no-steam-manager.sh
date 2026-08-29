#!/usr/bin/env bash
# Instala ARM Non-Steam Games en el menú Games.
#
# Uso:
#   sudo ./scripts/install-no-steam-manager.sh [rootfs]
#
# Dependencias runtime: python3 python3-gi gir1.2-gtk-3.0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
ROOTFS="$(cd "$ROOTFS" && pwd)"
VENDOR="${ROOT_DIR}/vendor/NO_Steam"

log() { printf '==> [no-steam] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "${ROOTFS}/usr" ]] || die "Rootfs no encontrado: ${ROOTFS}"
[[ "${EUID}" -eq 0 ]] || die "Ejecuta como root (sudo)"
[[ -d "${VENDOR}/no_steam_games" ]] || die "Falta vendor/NO_Steam/no_steam_games"

share="${ROOTFS}/usr/share/no-steam-games"
bin="${ROOTFS}/usr/bin"
apps="${ROOTFS}/usr/share/applications"

log "Copiando a ${share}"
rm -rf "${share}"
mkdir -p "${share}"
cp -a "${VENDOR}/no_steam_games" "${share}/"
[[ -f "${VENDOR}/run.py" ]] && cp -a "${VENDOR}/run.py" "${share}/"
[[ -d "${VENDOR}/data" ]] && cp -a "${VENDOR}/data" "${share}/"
find "${share}" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

cat > "${bin}/no-steam-games" <<'EOF'
#!/bin/bash
export NO_STEAM_GAMES_ROOT=/usr/share/no-steam-games
export PYTHONPATH="${NO_STEAM_GAMES_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m no_steam_games "$@"
EOF
chmod 0755 "${bin}/no-steam-games"

icon_name="applications-games"
if [[ -f "${VENDOR}/data/icons/no-steam-games.png" ]]; then
  install -d "${ROOTFS}/usr/share/icons/hicolor/256x256/apps"
  install -m 0644 "${VENDOR}/data/icons/no-steam-games.png" \
    "${ROOTFS}/usr/share/icons/hicolor/256x256/apps/no-steam-games.png"
  icon_name="no-steam-games"
fi

cat > "${apps}/no-steam-games.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ARM Non-Steam Games
GenericName=Add DRM-free games to Steam
Comment=Add DRM-free games to Steam — assign Proton in Steam for .exe; native ARM binaries launch direct
Exec=no-steam-games gui
Icon=${icon_name}
Terminal=false
Categories=Game;Utility;
Keywords=Steam;Non-Steam;GOG;Proton;ARM;Shortcut;Lutris;Heroic;
StartupNotify=true
EOF

log "Listo: ${apps}/no-steam-games.desktop"
