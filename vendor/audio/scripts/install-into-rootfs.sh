#!/usr/bin/env bash
# Install SM8550 audio drop-in into a Ubuntu rootfs (never the live build host).
# Usage:
#   sudo ./install-into-rootfs.sh /path/to/rootfs
#   sudo ./install-into-rootfs.sh /media/odin2/STORAGE
# Live handheld only: ALLOW_LIVE_ROOT=1 sudo ./install-into-rootfs.sh /
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_PROJ="$(cd "${HERE}/../.." && pwd)"
# shellcheck source=../../../scripts/lib/rootfs-guard.sh
source "${_PROJ}/scripts/lib/rootfs-guard.sh"
ROOT="${1:-}"
[[ -n "$ROOT" ]] || { echo "Usage: $0 <rootfs>" >&2; exit 1; }
require_rootfs "$ROOT"
ROOT="$ROOTFS"

install -d "${ROOT}/usr/share/alsa/ucm2/AYN/Odin2"
install -d "${ROOT}/usr/share/alsa/ucm2/AYN/Thor"
install -d "${ROOT}/usr/share/alsa/ucm2/conf.d/sm8550"
install -d "${ROOT}/lib/firmware/qcom/sm8550/ayn/odin2"
install -d "${ROOT}/usr/share/pipewire/pipewire.conf.d"
install -d "${ROOT}/usr/share/pipewire/pipewire-pulse.conf.d"

cp -a "${HERE}/ucm2/AYN/Odin2/." "${ROOT}/usr/share/alsa/ucm2/AYN/Odin2/"
cp -a "${HERE}/ucm2/AYN/Thor/." "${ROOT}/usr/share/alsa/ucm2/AYN/Thor/" 2>/dev/null || true
cp -a "${HERE}/ucm2/conf.d/sm8550/." "${ROOT}/usr/share/alsa/ucm2/conf.d/sm8550/"

cp -a "${HERE}/firmware/qcom/sm8550/ayn/odin2/." "${ROOT}/lib/firmware/qcom/sm8550/ayn/odin2/"
cp -a "${HERE}/firmware/qcom/sm8550/AYN-Odin2-tplg.bin" "${ROOT}/lib/firmware/qcom/sm8550/"
ln -sfn AYN-Odin2-tplg.bin "${ROOT}/lib/firmware/qcom/sm8550/AYN-Thor-tplg.bin"

if [[ -f "${HERE}/pipewire/pipewire.conf.d/99-sm8550-buffers.conf" ]]; then
  cp -a "${HERE}/pipewire/pipewire.conf.d/99-sm8550-buffers.conf" \
    "${ROOT}/usr/share/pipewire/pipewire.conf.d/"
fi
if [[ -f "${HERE}/pipewire/pipewire-pulse.conf.d/99-sm8550-buffers.conf" ]]; then
  cp -a "${HERE}/pipewire/pipewire-pulse.conf.d/99-sm8550-buffers.conf" \
    "${ROOT}/usr/share/pipewire/pipewire-pulse.conf.d/"
fi

install -d "${ROOT}/usr/share/wireplumber/wireplumber.conf.d"
if [[ -f "${HERE}/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" ]]; then
  cp -a "${HERE}/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" \
    "${ROOT}/usr/share/wireplumber/wireplumber.conf.d/"
fi

echo "Installed SM8550 audio drop-in into ${ROOT}"
echo "Ensure packages: pipewire pipewire-pulse wireplumber pipewire-alsa alsa-ucm-conf alsa-utils"
echo "Verify: cat /proc/asound/cards ; pactl list cards"
