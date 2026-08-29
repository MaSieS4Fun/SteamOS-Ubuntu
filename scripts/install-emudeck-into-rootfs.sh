#!/usr/bin/env bash
# Descarga EmuDeck (AppImage arm64) y crea entrada en menú Games.
# NO ejecuta el wizard interactivo — solo deja el AppImage listo.
#
# Uso:
#   sudo ./scripts/install-emudeck-into-rootfs.sh [rootfs]
#
# Icono: vendor/e-deck.jpeg → hicolor 256x256
# AppImage: ~/Applications/EmuDeck.AppImage (usuario steam, uid 1000)
#
# Dependencias runtime (instálalas tú en el rootfs):
#   jq zenity flatpak unzip bash libfuse2 git rsync whiptail python3
#
# URL fija del script install-arm.sh de EmuDeck (main-arm):
EMUDECK_URL="${EMUDECK_URL:-https://github.com/EmuDeck/emudeck-electron/releases/download/v2.6.1/EmuDeck-2.6.1-arm64.AppImage}"

log() { printf '==> [emudeck] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
ROOTFS="$(cd "$ROOTFS" && pwd)"
ICON_SRC="${ROOT_DIR}/vendor/e-deck.jpeg"
STEAM_HOME="${ROOTFS}/home/steam"
APP_DIR="${STEAM_HOME}/Applications"
APP_IMAGE="${APP_DIR}/EmuDeck.AppImage"

[[ -d "${ROOTFS}/usr" ]] || die "Rootfs no encontrado: ${ROOTFS}"
[[ "${EUID}" -eq 0 ]] || die "Ejecuta como root (sudo)"
[[ -f "$ICON_SRC" ]] || die "Falta vendor/e-deck.jpeg"
command -v curl >/dev/null || die "Falta curl en el host"

mkdir -p "$APP_DIR" "${ROOTFS}/usr/bin" "${ROOTFS}/usr/share/applications"
mkdir -p "${ROOTFS}/usr/share/icons/hicolor/256x256/apps"

log "Descargando EmuDeck AppImage..."
curl -fsSL -o "${APP_IMAGE}" "$EMUDECK_URL"
chmod 0755 "${APP_IMAGE}"

log "Icono emudeck desde e-deck.jpeg"
if command -v convert >/dev/null 2>&1; then
  convert "$ICON_SRC" -resize 256x256 \
    "${ROOTFS}/usr/share/icons/hicolor/256x256/apps/emudeck.png"
elif command -v magick >/dev/null 2>&1; then
  magick "$ICON_SRC" -resize 256x256 \
    "${ROOTFS}/usr/share/icons/hicolor/256x256/apps/emudeck.png"
elif python3 -c "from PIL import Image" 2>/dev/null; then
  python3 - "$ICON_SRC" "${ROOTFS}/usr/share/icons/hicolor/256x256/apps/emudeck.png" <<'PY'
import sys
from PIL import Image
Image.open(sys.argv[1]).convert("RGBA").resize((256, 256), Image.LANCZOS).save(sys.argv[2])
PY
else
  install -m 0644 "$ICON_SRC" \
    "${ROOTFS}/usr/share/icons/hicolor/256x256/apps/emudeck.jpeg"
  log "Sin ImageMagick/Pillow — Icon= emudeck.jpeg (ruta absoluta en .desktop)"
fi

icon_line="Icon=emudeck"
[[ -f "${ROOTFS}/usr/share/icons/hicolor/256x256/apps/emudeck.jpeg" ]] && \
  icon_line="Icon=/usr/share/icons/hicolor/256x256/apps/emudeck.jpeg"

cat > "${ROOTFS}/usr/bin/emudeck" <<'EOF'
#!/bin/bash
# EmuDeck en Ubuntu/Plasma: --no-sandbox (install-arm.sh)
APP="${HOME}/Applications/EmuDeck.AppImage"
[[ -x "$APP" ]] || APP="/home/steam/Applications/EmuDeck.AppImage"
exec "$APP" --no-sandbox "$@"
EOF
chmod 0755 "${ROOTFS}/usr/bin/emudeck"

cat > "${ROOTFS}/usr/share/applications/emudeck.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=EmuDeck
Comment=Emulator setup and configuration for handheld Linux
Exec=emudeck
${icon_line}
Terminal=false
Categories=Game;
Keywords=emulator;retro;steam;deck;
StartupNotify=true
EOF

# Propietario steam (uid 1000 en esta imagen)
if id -u steam >/dev/null 2>&1 && [[ -d "$STEAM_HOME" ]]; then
  chown -R 1000:1000 "$STEAM_HOME/Applications" 2>/dev/null || true
elif [[ -d "$STEAM_HOME" ]]; then
  chown -R 1000:1000 "$STEAM_HOME/Applications" 2>/dev/null || true
fi

log "Listo: ${APP_IMAGE}"
log "Primera ejecución: abre EmuDeck desde el menú Games y sigue el wizard."
