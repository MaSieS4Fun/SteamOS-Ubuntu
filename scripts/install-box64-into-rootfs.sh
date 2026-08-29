#!/usr/bin/env bash
# Compila box64 (SD8G2) desde upstream e instala en el rootfs.
# NOT used by image bake (install-vendor-apps.sh). ARM-Manager ships
# /usr/bin/update-box64 so the user builds Box64 on the device if needed.
#
# Uso:
#   sudo ./scripts/install-box64-into-rootfs.sh [rootfs]
#
# Requiere en el HOST (aarch64): git cmake make gcc g++ (GCC 12+)
# Clona en /tmp/box64-build-$$ (se borra al terminar).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
ROOTFS="$(cd "$ROOTFS" && pwd)"
WORK_DIR="${BOX64_WORK_DIR:-/tmp/box64-build-$$}"
REPO="https://github.com/ptitSeb/box64"

log() { printf '==> [box64] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

[[ -d "${ROOTFS}/usr" ]] || die "Rootfs no encontrado: ${ROOTFS}"
[[ "${EUID}" -eq 0 ]] || die "Ejecuta como root (sudo)"
[[ "$(uname -m)" == "aarch64" ]] || die "Compila en aarch64 (Odin 2 o build host ARM)"

for cmd in git cmake make gcc g++; do
  command -v "$cmd" >/dev/null || die "Falta: $cmd"
done
gcc_major="$(gcc -dumpversion | cut -d. -f1)"
(( gcc_major >= 12 )) || die "box64 SD8G2 necesita GCC 12+ (tienes ${gcc_major})"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

log "Clonando box64..."
git clone --depth 1 --recursive "$REPO" box64
cd box64
mkdir -p build

log "Compilando (SD8G2, RelWithDebInfo)..."
cmake -S . -B build -DSD8G2=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build build -j"$(nproc)"

log "Instalando en ${ROOTFS}..."
DESTDIR="$ROOTFS" cmake --install build

# Sin menú del configurador empaquetado por upstream.
rm -f \
  "${ROOTFS}/usr/local/share/applications/box64-configurator.desktop" \
  "${ROOTFS}/usr/share/applications/box64-configurator.desktop" 2>/dev/null || true

# Manifiesto para update-box64 uninstall.
install -d "${ROOTFS}/usr/local/share/box64"
if [[ -f build/install_manifest.txt ]]; then
  grep -v 'box64-configurator\.desktop' build/install_manifest.txt \
    >"${ROOTFS}/usr/local/share/box64/install_manifest.txt"
else
  cp -f "${ROOT_DIR}/vendor/BOX64/install_manifest.txt" \
    "${ROOTFS}/usr/local/share/box64/install_manifest.txt"
  sed -i '/box64-configurator\.desktop/d' \
    "${ROOTFS}/usr/local/share/box64/install_manifest.txt"
fi

[[ -x "${ROOTFS}/usr/local/bin/box64" ]] || die "box64 no quedó instalado"
log "Instalado: ${ROOTFS}/usr/local/bin/box64"
"${ROOTFS}/usr/local/bin/box64" --version 2>/dev/null || true
