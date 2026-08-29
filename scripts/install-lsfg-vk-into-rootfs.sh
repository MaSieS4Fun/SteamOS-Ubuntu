#!/usr/bin/env bash
# Compila lsfg-vk e instala SOLO la librería:
#   /usr/local/lib/liblsfg-vk.so
#
# NO instala VkLayer_LS_frame_generation.json (evita conflicto Vulkan).
# Si ya existía en el rootfs, se elimina.
#
# Uso:
#   sudo ./scripts/install-lsfg-vk-into-rootfs.sh [rootfs]
#
# Fuente: vendor/lsfg-vk
# Requiere en el HOST (aarch64): cmake g++ make
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
ROOTFS="$(cd "$ROOTFS" && pwd)"
SRC="${ROOT_DIR}/vendor/lsfg-vk"
BUILD_DIR="${LSFGVK_BUILD_DIR:-/tmp/lsfg-vk-build-$$}"
LAYER_JSON="VkLayer_LS_frame_generation.json"

log() { printf '==> [lsfg-vk] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -d "$BUILD_DIR" && "$BUILD_DIR" == /tmp/* ]] && rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

[[ -d "${ROOTFS}/usr" ]] || die "Rootfs no encontrado: ${ROOTFS}"
[[ -f "${SRC}/CMakeLists.txt" ]] || die "Falta vendor/lsfg-vk"
[[ "${EUID}" -eq 0 ]] || die "Ejecuta como root (sudo)"
[[ "$(uname -m)" == "aarch64" ]] || die "Compila en aarch64"

for cmd in cmake make g++; do
  command -v "$cmd" >/dev/null || die "Falta: $cmd"
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log "Configurando cmake..."
cmake -S "$SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local

log "Compilando..."
cmake --build "$BUILD_DIR" -j"$(nproc)"

built_so="${BUILD_DIR}/liblsfg-vk.so"
[[ -f "$built_so" ]] || die "No se generó liblsfg-vk.so"

install -d "${ROOTFS}/usr/local/lib"
install -m 0644 "$built_so" "${ROOTFS}/usr/local/lib/liblsfg-vk.so"

# Quitar capa implícita si algún install anterior la dejó.
find "${ROOTFS}/usr/local/share/vulkan" "${ROOTFS}/usr/share/vulkan" \
  -name "${LAYER_JSON}" -delete 2>/dev/null || true

log "Instalado: ${ROOTFS}/usr/local/lib/liblsfg-vk.so (sin ${LAYER_JSON})"
ls -lh "${ROOTFS}/usr/local/lib/liblsfg-vk.so"

# Decky PluginLoader + LSFG children hang shutdown/session switch for minutes
# unless KillMode=control-group (vendor/system-fixes/LSFG-VK).
DROP_IN_DIR="${ROOT_DIR}/vendor/system-fixes/LSFG-VK/plugin_loader.service.d"
for drop in fast-stop.conf fex-steam-rootfs.conf; do
  DROP_IN_SRC="${DROP_IN_DIR}/${drop}"
  [[ -f "$DROP_IN_SRC" ]] || continue
  install -D -m 0644 "$DROP_IN_SRC" \
    "${ROOTFS}/etc/systemd/system/plugin_loader.service.d/${drop}"
  log "Installed plugin_loader.service.d/${drop}"
  if [[ "$drop" == "fast-stop.conf" ]] && grep -q '^steam:' "${ROOTFS}/etc/passwd" 2>/dev/null; then
    steam_uid="$(awk -F: '$1=="steam"{print $3}' "${ROOTFS}/etc/passwd")"
    steam_gid="$(awk -F: '$1=="steam"{print $4}' "${ROOTFS}/etc/passwd")"
    install -D -m 0644 "$DROP_IN_SRC" \
      "${ROOTFS}/home/steam/.config/systemd/user/plugin_loader.service.d/fast-stop.conf"
    if [[ -n "${steam_uid:-}" && -n "${steam_gid:-}" ]]; then
      chown -R "${steam_uid}:${steam_gid}" \
        "${ROOTFS}/home/steam/.config/systemd" 2>/dev/null || true
    fi
  fi
done
