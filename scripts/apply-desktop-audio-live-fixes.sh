#!/usr/bin/env bash
# Live apply: drop duplicate Gaming Mode launcher + restore HiFi UCM (no DP JackHWMute).
# Usage: sudo ./scripts/apply-desktop-audio-live-fixes.sh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "${EUID}" -eq 0 ]] || { echo "Run as root"; exit 1; }

log() { printf '==> %s\n' "$*"; }

log "Remove duplicate steamos-gaming-mode.desktop"
rm -f \
  /usr/share/applications/steamos-gaming-mode.desktop \
  /home/steam/Desktop/steamos-gaming-mode.desktop \
  /etc/skel/Desktop/steamos-gaming-mode.desktop \
  2>/dev/null || true
update-desktop-database /usr/share/applications 2>/dev/null || true

log "Install Odin2/Thor HiFi.conf from vendor/audio"
install -D -m 0644 \
  "${ROOT_DIR}/vendor/audio/ucm2/AYN/Odin2/HiFi.conf" \
  /usr/share/alsa/ucm2/AYN/Odin2/HiFi.conf
install -D -m 0644 \
  "${ROOT_DIR}/vendor/audio/ucm2/AYN/Thor/HiFi.conf" \
  /usr/share/alsa/ucm2/AYN/Thor/HiFi.conf
rm -f /usr/share/alsa/ucm2/AYN/Odin2/HiFi.conf.bak.* 2>/dev/null || true

install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink" \
  /usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink

# WirePlumber HiFi priority (DisplayPort only — no Headphones combo)
if [[ -f "${ROOT_DIR}/system_files/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" ]]; then
  install -D -m 0644 \
    "${ROOT_DIR}/system_files/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" \
    /usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf
fi

log "Restart PipeWire/WirePlumber for user steam"
STEAM_UID="$(id -u steam 2>/dev/null || echo 1000)"
export XDG_RUNTIME_DIR="/run/user/${STEAM_UID}"
if [[ -d "$XDG_RUNTIME_DIR" ]]; then
  sudo -u steam env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    systemctl --user restart pipewire.socket pipewire pipewire-pulse wireplumber 2>/dev/null \
    || sudo -u steam env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
      systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null \
    || true
fi

sleep 2
log "Profiles now:"
sudo -u steam env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
  pactl list cards 2>/dev/null | awk '/Profiles:/,/Active Profile:/' || true

log "Done. Profiles expected:"
log "  HiFi (DisplayPort)  = HDMI/DP only"
log "  Pro Audio           = speakers + headphones"
log "Watcher switches HiFi↔Pro Audio on HDMI plug/unplug."
