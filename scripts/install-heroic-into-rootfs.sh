#!/usr/bin/env bash
# Compila Heroic Games Launcher (arm64) e instala en /opt/Heroic.
# Clona upstream y compila con pnpm@10 — sin pin de versión ni frozen-lockfile.
#
# Uso:
#   sudo ./scripts/install-heroic-into-rootfs.sh [rootfs]
#
# Requiere en el HOST (aarch64): git, Node 22, pnpm 10
# (scripts/lib/ensure-build-node.sh los resuelve bajo sudo).
#
# Env opcional:
#   HEROIC_GIT_REF=v2.x.y     — tag/branch concreto (default: HEAD del repo)
#   HEROIC_FRESH_CLONE=1      — borrar cache y clonar de cero
#   HEROIC_WORK_DIR=...       — directorio de build (default vendor/.cache/heroic-build)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
ROOTFS="$(cd "$ROOTFS" && pwd)"
WORK_DIR="${HEROIC_WORK_DIR:-${ROOT_DIR}/vendor/.cache/heroic-build}"
REPO="https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher.git"

log() { printf '==> [heroic] %s\n' "$*" >&2; }
die() { printf 'ERROR: [heroic] %s\n' "$*" >&2; exit 1; }

# shellcheck source=lib/ensure-build-node.sh
source "${ROOT_DIR}/scripts/lib/ensure-build-node.sh"

[[ -d "${ROOTFS}/usr" ]] || die "Rootfs no encontrado: ${ROOTFS}"
[[ "${EUID}" -eq 0 ]] || die "Ejecuta como root (sudo)"
[[ "$(uname -m)" == "aarch64" ]] || die "Compila en aarch64"

command -v git >/dev/null || die "Falta git (apt install git)"

ensure_build_node "$ROOT_DIR" || die \
  "No se pudo preparar Node 22 + pnpm 10. Comprueba red o ejecuta: sudo ./scripts/install-host-build-deps.sh"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

heroic_src="${WORK_DIR}/HeroicGamesLauncher"

if [[ "${HEROIC_FRESH_CLONE:-0}" == "1" ]]; then
  log "HEROIC_FRESH_CLONE=1 — eliminando clone anterior"
  rm -rf "$heroic_src"
fi

if [[ ! -d "${heroic_src}/.git" ]]; then
  log "Clonando Heroic (shallow, submodules)…"
  git clone --depth 1 --recurse-submodules "$REPO" "$heroic_src"
else
  log "Actualizando clone Heroic existente…"
  git -C "$heroic_src" fetch --depth 1 origin || true
fi

cd "$heroic_src"

if [[ -n "${HEROIC_GIT_REF:-}" ]]; then
  log "Checkout ${HEROIC_GIT_REF}"
  git fetch --depth 1 origin "${HEROIC_GIT_REF}" 2>/dev/null || true
  git checkout -f "${HEROIC_GIT_REF}"
else
  # Siempre compilar la punta del repo — no exigir lockfile/versión fija.
  default_branch="$(git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}')"
  default_branch="${default_branch:-main}"
  log "Checkout origin/${default_branch} (última versión upstream)"
  git fetch --depth 1 origin "${default_branch}" || true
  git checkout -f "origin/${default_branch}" 2>/dev/null \
    || git checkout -f "${default_branch}" 2>/dev/null \
    || git pull --ff-only || true
fi

git submodule update --init --recursive --depth 1 || true

log "Heroic $(git rev-parse --short HEAD) — pnpm $(pnpm -v), node $(node -v)"
log "packageManager en package.json (informativo): $(node -e "try{console.log(require('./package.json').packageManager||'none')}catch(e){console.log('none')}")"
log "No se fuerza corepack/packageManager — pnpm@10 del bake es suficiente"

heroic_pnpm_install() {
  log "pnpm install (sin frozen-lockfile)…"
  pnpm install --reporter=append-only
}

if [[ -d node_modules ]]; then
  log "node_modules presente — probando install incremental…"
  if ! heroic_pnpm_install; then
    log "install incremental falló — limpiando node_modules y reintentando…"
    rm -rf node_modules
    heroic_pnpm_install
  fi
else
  heroic_pnpm_install
fi

log "Descargando binarios auxiliares (legendary, gogdl, nile)…"
pnpm run download-helper-binaries || true

log "Compilando frontend (electron-vite)…"
export CSC_IDENTITY_AUTO_DISCOVERY=false
pnpm exec electron-vite build

log "Empaquetando linux arm64 (directorio, no AppImage)…"
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
