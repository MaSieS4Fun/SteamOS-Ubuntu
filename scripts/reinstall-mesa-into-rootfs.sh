#!/usr/bin/env bash
# Reinstall vendor Mesa into a mounted rootfs (e.g. /media/odin2/STORAGE).
# Reuses output/work/mesa-* unless FORCE_REBUILD=1.
# Purges + apt-pins Ubuntu Mesa, then installs full Turnip/OpenGL/LLVM stack.
#
#   sudo ./scripts/reinstall-mesa-into-rootfs.sh /media/odin2/STORAGE
#   sudo FORCE_REBUILD=1 ./scripts/reinstall-mesa-into-rootfs.sh /media/odin2/STORAGE
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || {
  echo "Usage: $0 <rootfs-mount>" >&2
  exit 1
}
[[ "${EUID}" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

chmod +x "${ROOT_DIR}/scripts/build-vendor-mesa.sh"
# Also refresh session wrapper with VK_DRIVER_FILES pin
if [[ -f "${ROOT_DIR}/system_files/usr/bin/gamescope-session" ]]; then
  install -D -m 0755 \
    "${ROOT_DIR}/system_files/usr/bin/gamescope-session" \
    "${ROOTFS}/usr/bin/gamescope-session"
fi
install -D -m 0644 \
  "${ROOT_DIR}/config/apt-preferences/99-block-ubuntu-mesa" \
  "${ROOTFS}/etc/apt/preferences.d/99-block-ubuntu-mesa"

exec "${ROOT_DIR}/scripts/build-vendor-mesa.sh" "$ROOTFS"
