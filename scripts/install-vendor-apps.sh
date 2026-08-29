#!/usr/bin/env bash
# Orquestador opcional — lanza los installs en orden.
# Tú supervisas; puedes ejecutar cada script por separado si prefieres.
#
# Uso:
#   sudo ./scripts/install-vendor-apps.sh [rootfs]
#
# Saltar pasos:
#   SKIP_ARM_MANAGER=1 SKIP_LSFG=1 SKIP_PROTON=1 SKIP_HEROIC=1 SKIP_EMUDECK=1 SKIP_SRM=1 SKIP_NO_STEAM=1
#
# Orden:
#   1. ARM-Manager (MESA Easy Manager, update-box64 script, install-fexemu script, UFS)
#      — no compile; Box64/FEX binaries are built later on the device
#   2. lsfg-vk lib                                — compila
#   3. Proton ARM Easy Manager                    — copia
#   4. Heroic                                     — compila (lento)
#   5. EmuDeck                                    — descarga AppImage
#   6. Steam ROM Manager                          — copia
#   7. ARM Non-Steam Games                        — copia
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
ROOTFS="$(cd "$ROOTFS" && pwd)"
SCRIPTS="${ROOT_DIR}/scripts"

log() { printf '\n==> [vendor-apps] %s\n' "$*"; }
run() {
  local name="$1" script="$2"
  [[ "${!name:-0}" == "1" ]] && { log "SKIP ${script}"; return 0; }
  log "Ejecutando ${script}..."
  bash "${SCRIPTS}/${script}" "$ROOTFS"
}

[[ "${EUID}" -eq 0 ]] || { echo "Ejecuta como root: sudo $0 $*" >&2; exit 1; }
[[ -d "${ROOTFS}/usr" ]] || { echo "Rootfs no encontrado: ${ROOTFS}" >&2; exit 1; }

chmod +x "${SCRIPTS}"/install-vendor-*.sh "${SCRIPTS}"/install-*-into-rootfs.sh 2>/dev/null || true

run SKIP_ARM_MANAGER  install-vendor-arm-manager.sh
run SKIP_LSFG         install-lsfg-vk-into-rootfs.sh
run SKIP_PROTON       install-proton-arm-easy-manager.sh
if [[ "${SKIP_HEROIC:-0}" != "1" ]]; then
  log "Preparando Node 22 + pnpm para Heroic…"
  # shellcheck source=lib/ensure-build-node.sh
  source "${SCRIPTS}/lib/ensure-build-node.sh"
  ensure_build_node "$ROOT_DIR" || {
    echo "ERROR: Heroic requiere Node 22 + pnpm 10 en el host de compilación." >&2
    echo "Ejecuta: sudo ./scripts/install-host-build-deps.sh" >&2
    echo "O exporta PATH con tu Node local antes de sudo." >&2
    exit 1
  }
fi
run SKIP_HEROIC       install-heroic-into-rootfs.sh
run SKIP_EMUDECK      install-emudeck-into-rootfs.sh
run SKIP_SRM          install-vendor-steam-rom-manager.sh
run SKIP_NO_STEAM     install-no-steam-manager.sh

log "Todos los pasos solicitados completados."
