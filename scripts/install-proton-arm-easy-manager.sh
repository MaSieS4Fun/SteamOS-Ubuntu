#!/usr/bin/env bash
# Instala Proton ARM Easy Manager en el menú Games.
# Copia vendor → /usr/share/proton-arm-easy-manager + lanzador + .desktop
#
# Uso:
#   sudo ./scripts/install-proton-arm-easy-manager.sh [rootfs]
#
# Icono maestro: vendor/Proton-ARM-Easy-Manager/eparm.png
# (sync a data/icons/ antes de empaquetar — ver scripts/sync-proton-arm-icons.sh)
#
# Dependencias runtime: python3 python3-gi gir1.2-gtk-3.0 (GUI)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
ROOTFS="$(cd "$ROOTFS" && pwd)"
VENDOR="${ROOT_DIR}/vendor/Proton-ARM-Easy-Manager"

log() { printf '==> [proton-arm] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "${ROOTFS}/usr" ]] || die "Rootfs no encontrado: ${ROOTFS}"
[[ "${EUID}" -eq 0 ]] || die "Ejecuta como root (sudo)"
[[ -d "${VENDOR}/proton_arm_easy_manager" ]] || die "Falta vendor/Proton-ARM-Easy-Manager"

if [[ -x "${ROOT_DIR}/scripts/sync-proton-arm-icons.sh" ]]; then
  log "Sincronizando iconos desde vendor/eparm.png…"
  bash "${ROOT_DIR}/scripts/sync-proton-arm-icons.sh"
fi

share="${ROOTFS}/usr/share/proton-arm-easy-manager"
bin="${ROOTFS}/usr/bin"
apps="${ROOTFS}/usr/share/applications"
icon_theme="${ROOTFS}/usr/share/icons/hicolor"

log "Copiando a ${share}"
rm -rf "${share}"
mkdir -p "${share}"
cp -a "${VENDOR}/proton_arm_easy_manager" "${share}/"
cp -a "${VENDOR}/data" "${share}/"
[[ -f "${VENDOR}/run.py" ]] && cp -a "${VENDOR}/run.py" "${share}/"
find "${share}" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

cat > "${bin}/proton-arm-easy-manager" <<'EOF'
#!/bin/bash
export PROTON_ARM_EASY_MANAGER_ROOT=/usr/share/proton-arm-easy-manager
export PYTHONPATH="${PROTON_ARM_EASY_MANAGER_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m proton_arm_easy_manager "$@"
EOF
chmod 0755 "${bin}/proton-arm-easy-manager"

icon_name="applications-games"
if [[ -f "${VENDOR}/data/icons/eparm.png" ]]; then
  for size in 16 24 32 48 64 128 256 512; do
    src="${VENDOR}/data/icons/eparm-${size}.png"
    [[ -f "$src" ]] || src="${VENDOR}/data/icons/eparm.png"
    install -d "${icon_theme}/${size}x${size}/apps"
    install -m 0644 "$src" \
      "${icon_theme}/${size}x${size}/apps/proton-arm-easy-manager.png"
  done
  icon_name="proton-arm-easy-manager"
  log "Icono tema hicolor instalado (${icon_name})"
fi

cat > "${apps}/proton-arm-easy-manager.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Proton ARM Easy Manager
Comment=Install and manage ARM64 Proton builds for Steam, Lutris and Heroic
Exec=proton-arm-easy-manager gui
Icon=${icon_name}
Terminal=false
Categories=Game;Utility;
Keywords=Proton;Steam;ARM;Wine;Lutris;Heroic;
StartupNotify=true
EOF

if command -v gtk-update-icon-cache >/dev/null 2>&1 \
  && [[ -d "${icon_theme}" ]]; then
  gtk-update-icon-cache -f "${icon_theme}" >/dev/null 2>&1 || true
fi

log "Listo: ${apps}/proton-arm-easy-manager.desktop (Categories=Game)"
