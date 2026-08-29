#!/usr/bin/env bash
# Compila Heroic Games Launcher (arm64) e instala en /opt/Heroic.
# Entrada en menú Games.
#
# Uso:
#   sudo ./scripts/install-heroic-into-rootfs.sh [rootfs]
#
# Requiere en el HOST (aarch64): git, Node 22, pnpm 10
# (scripts/lib/ensure-build-node.sh los resuelve bajo sudo).
#
# Clona/compila en /tmp/heroic-build-$$ (se borra al terminar).
# Tarda varios minutos — supervisa la salida.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
# Ruta absoluta antes de cd al tree de compilación (si no, output/rootfs acaba bajo /tmp).
ROOTFS="$(cd "$ROOTFS" && pwd)"
WORK_DIR="${HEROIC_WORK_DIR:-${ROOT_DIR}/vendor/.cache/heroic-build}"
REPO="https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher.git"

log() { printf '==> [heroic] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() {
  [[ "${HEROIC_CLEAN_WORK_DIR:-0}" == "1" ]] || return 0
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# shellcheck source=lib/ensure-build-node.sh
source "${ROOT_DIR}/scripts/lib/ensure-build-node.sh"

[[ -d "${ROOTFS}/usr" ]] || die "Rootfs no encontrado: ${ROOTFS}"
[[ "${EUID}" -eq 0 ]] || die "Ejecuta como root (sudo)"
[[ "$(uname -m)" == "aarch64" ]] || die "Compila en aarch64"

command -v git >/dev/null || die "Falta git (apt install git)"

ensure_build_node "$ROOT_DIR" || die \
  "No se pudo preparar Node 22 + pnpm 10 para compilar Heroic. Comprueba red o BUILD_NODE_VERSION."

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

if [[ -d HeroicGamesLauncher/.git ]]; then
  log "Repo Heroic ya presente en ${WORK_DIR} — actualizando..."
  git -C HeroicGamesLauncher pull --ff-only || true
else
  log "Clonando Heroic..."
  git clone --depth 1 --recurse-submodules "$REPO" HeroicGamesLauncher
fi
cd HeroicGamesLauncher

ensure_project_package_manager "package.json"

if [[ -d node_modules ]]; then
  log "node_modules ya existe — omitiendo pnpm install"
else
  log "pnpm install - puede tardar, progreso linea a linea..."
  if ! pnpm install --frozen-lockfile --reporter=append-only; then
    log "lockfile no congelado - reintentando pnpm install..."
    pnpm install --reporter=append-only
  fi
fi

log "Descargando binarios auxiliares legendary gogdl nile..."
pnpm run download-helper-binaries || true

log "Compilando frontend (electron-vite)..."
export CSC_IDENTITY_AUTO_DISCOVERY=false
pnpm exec electron-vite build

log "Empaquetando linux arm64 (directorio, no AppImage)..."
set +e
pnpm exec electron-builder --linux dir --arm64 \
  -c.linux.icon=build/icon.png \
  -c.npmRebuild=true
eb_rc=$?
set -e

unpacked="$(find dist -type d -name 'linux*-unpacked' 2>/dev/null | head -1 || true)"
[[ -n "$unpacked" && -x "${unpacked}/heroic" ]] \
  || die "Falló electron-builder (rc=${eb_rc}); no hay linux*-unpacked/heroic"
[[ "${eb_rc}" -ne 0 ]] && log "electron-builder avisó rc=${eb_rc} pero el tree existe — sigo"

log "Instalando en ${ROOTFS}/opt/Heroic"
rm -rf "${ROOTFS}/opt/Heroic"
mkdir -p \
  "${ROOTFS}/opt/Heroic" \
  "${ROOTFS}/usr/bin" \
  "${ROOTFS}/usr/share/applications" \
  "${ROOTFS}/usr/share/icons/hicolor/256x256/apps"
cp -a "${unpacked}/." "${ROOTFS}/opt/Heroic/"
chmod 0755 "${ROOTFS}/opt/Heroic/heroic"
[[ -f "${ROOTFS}/opt/Heroic/chrome-sandbox" ]] && \
  chmod 4755 "${ROOTFS}/opt/Heroic/chrome-sandbox" 2>/dev/null || true

cat > "${ROOTFS}/usr/bin/heroic" <<'EOF'
#!/bin/bash
# Heroic en sesión Wayland (Plasma / gamescope desktop)
mkdir -p /tmp/.X11-unix 2>/dev/null || true
exec /opt/Heroic/heroic \
  --ozone-platform-hint=auto \
  --enable-features=UseOzonePlatform,WaylandWindowDecorations \
  "$@"
EOF
chmod 0755 "${ROOTFS}/usr/bin/heroic"

if [[ -f build/icon.png ]]; then
  install -d "${ROOTFS}/usr/share/icons/hicolor/256x256/apps"
  install -m 0644 build/icon.png \
    "${ROOTFS}/usr/share/icons/hicolor/256x256/apps/heroic.png"
fi

cat > "${ROOTFS}/usr/share/applications/heroic.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Heroic Games Launcher
Comment=Launcher for Epic, GOG and Amazon Games
Exec=heroic %U
Icon=heroic
Terminal=false
Categories=Game;
Keywords=epic;gog;amazon;games;heroic;
StartupNotify=true
MimeType=x-scheme-handler/heroic;
EOF

log "Listo: /opt/Heroic + ${ROOTFS}/usr/bin/heroic"
