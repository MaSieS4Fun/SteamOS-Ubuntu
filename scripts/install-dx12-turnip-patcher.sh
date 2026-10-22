#!/usr/bin/env bash
# Install DX12 Turnip Patcher in the ARM-Manager menu.
# Copia vendor → /usr/share/dx12-turnip-patcher + lanzador + .desktop
#
# Uso:
#   sudo ./scripts/install-dx12-turnip-patcher.sh [rootfs]
#
# Lo llama scripts/install-vendor-apps.sh al generar la imagen.
# Dependencias runtime: python3 python3-gi gir1.2-gtk-3.0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
ROOTFS="$(cd "$ROOTFS" && pwd)"
VENDOR="${ROOT_DIR}/vendor/DX12-2-Turnip-Patcher"

log() { printf '==> [dx12-turnip] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "${ROOTFS}/usr" ]] || die "Rootfs no encontrado: ${ROOTFS}"
[[ "${EUID}" -eq 0 ]] || die "Ejecuta como root (sudo)"
[[ -d "${VENDOR}/dx12_turnip_patcher" ]] || die "Falta vendor/DX12-2-Turnip-Patcher"

share="${ROOTFS}/usr/share/dx12-turnip-patcher"
bin="${ROOTFS}/usr/bin"
apps="${ROOTFS}/usr/share/applications"
icon_theme="${ROOTFS}/usr/share/icons/hicolor"

log "Copiando a ${share}"
rm -rf "${share}"
mkdir -p "${share}"
cp -a "${VENDOR}/dx12_turnip_patcher" "${share}/"
[[ -f "${VENDOR}/run.py" ]] && cp -a "${VENDOR}/run.py" "${share}/"
[[ -d "${VENDOR}/data" ]] && cp -a "${VENDOR}/data" "${share}/"
find "${share}" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

cat > "${bin}/dx12-turnip-patcher" <<'EOF'
#!/bin/bash
export DX12_TURNIP_PATCHER_ROOT=/usr/share/dx12-turnip-patcher
export PYTHONPATH="${DX12_TURNIP_PATCHER_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m dx12_turnip_patcher "$@"
EOF
chmod 0755 "${bin}/dx12-turnip-patcher"

icon_name="applications-games"
if [[ -f "${VENDOR}/data/icons/dx12-turnip.png" ]]; then
  for size in 16 24 32 48 64 128 256 512; do
    install -d "${icon_theme}/${size}x${size}/apps"
    install -m 0644 "${VENDOR}/data/icons/dx12-turnip.png" \
      "${icon_theme}/${size}x${size}/apps/dx12-turnip-patcher.png"
  done
  icon_name="dx12-turnip-patcher"
  log "Icono tema hicolor instalado (${icon_name})"
fi

cat > "${apps}/dx12-turnip-patcher.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=DX12 Turnip Patcher
Comment=Patch a chosen Proton so DX12 games can run on Turnip
Exec=dx12-turnip-patcher gui
Icon=${icon_name}
Terminal=false
Categories=System;Utility;X-ARM-Manager;
Keywords=Proton;vkd3d;Turnip;mesh;DirectX;ARM;
StartupNotify=true
EOF

if command -v gtk-update-icon-cache >/dev/null 2>&1 \
  && [[ -d "${icon_theme}" ]]; then
  gtk-update-icon-cache -f "${icon_theme}" >/dev/null 2>&1 || true
fi

log "Installed ${apps}/dx12-turnip-patcher.desktop (ARM-Manager)"
