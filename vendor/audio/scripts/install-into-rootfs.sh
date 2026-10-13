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

# AYN Odin 3 (SM8750). Helpers exit on any other card, so this is safe on Odin 2 / Thor.
ODIN3="${HERE}/ODIN3"
if [[ -d "${ODIN3}/ucm2" ]]; then
  echo "Installing Odin 3 (SM8750) audio drop-in"
  install -d "${ROOT}/usr/share/alsa/ucm2"
  cp -a "${ODIN3}/ucm2/." "${ROOT}/usr/share/alsa/ucm2/"
  if [[ -d "${ODIN3}/firmware" ]]; then
    install -d "${ROOT}/lib/firmware"
    cp -a "${ODIN3}/firmware/." "${ROOT}/lib/firmware/"
  fi
  if [[ -d "${ODIN3}/wireplumber" ]]; then
    install -d "${ROOT}/usr/share/wireplumber"
    cp -a "${ODIN3}/wireplumber/." "${ROOT}/usr/share/wireplumber/"
  fi
  if [[ -d "${ODIN3}/systemd/user" ]]; then
    install -d "${ROOT}/usr/lib/systemd/user"
    cp -a "${ODIN3}/systemd/user/." "${ROOT}/usr/lib/systemd/user/"
  fi
  install -d "${ROOT}/usr/libexec/audio-odin3"
  install -m 0755 "${ODIN3}/scripts/wait-sm8750-audio" \
    "${ROOT}/usr/libexec/audio-odin3/wait-sm8750-audio"
  install -m 0755 "${ODIN3}/scripts/sm8750-audio-profile" \
    "${ROOT}/usr/libexec/audio-odin3/sm8750-audio-profile"
  install -d "${ROOT}/usr/lib/systemd/user/default.target.wants" \
    "${ROOT}/usr/lib/systemd/user/wireplumber.service.wants"
  ln -sfn ../sm8750-audio-profile.service \
    "${ROOT}/usr/lib/systemd/user/default.target.wants/sm8750-audio-profile.service"
  ln -sfn ../sm8750-audio-ready.service \
    "${ROOT}/usr/lib/systemd/user/wireplumber.service.wants/sm8750-audio-ready.service"
  [[ -f "${ROOT}/usr/share/alsa/ucm2/AYN/Odin3/HiFi.conf" ]] \
    || { echo "ERROR: Odin 3 UCM missing after install" >&2; exit 1; }
  [[ -f "${ROOT}/lib/firmware/qcom/sm8750/SM8750-AYN-tplg.bin" ]] \
    || { echo "ERROR: Odin 3 topology firmware missing after install" >&2; exit 1; }
  [[ -e "${ROOT}/usr/share/alsa/ucm2/conf.d/sm8750/SM8750-AYN.conf" ]] \
    || { echo "ERROR: Odin 3 UCM card link missing" >&2; exit 1; }
  echo "Installed Odin 3 audio into ${ROOT}"
fi

echo "Ensure packages: pipewire pipewire-pulse wireplumber pipewire-alsa alsa-ucm-conf alsa-utils"
echo "Verify: cat /proc/asound/cards ; pactl list cards"
