#!/usr/bin/env bash
# Live: fix Pro Audio (routing + stop watcher fighting manual profile).
set -euo pipefail
ROOT=/home/steam/Desktop/SteamOS-Ubuntu
[[ "${EUID}" -eq 0 ]] || exec pkexec "$0" "$@"

install -D -m 0755 \
  "$ROOT/system_files/usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink" \
  /usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink

# Optional: keep current UCM (HiFi DP). Re-install if present.
[[ -f "$ROOT/vendor/audio/ucm2/AYN/Odin2/HiFi.conf" ]] && \
  install -D -m 0644 "$ROOT/vendor/audio/ucm2/AYN/Odin2/HiFi.conf" \
    /usr/share/alsa/ucm2/AYN/Odin2/HiFi.conf

UID_STEAM=$(id -u steam)
export XDG_RUNTIME_DIR=/run/user/$UID_STEAM

# Restart user watcher so new logic loads
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
  systemctl --user restart sm8550-prefer-speaker-sink.service 2>/dev/null || true

# Restore speaker/jack mixers now and switch to Pro Audio for a clean test
amixer -c 0 cset name='DISPLAY_PORT_RX_0 Audio Mixer MultiMedia2' 0 >/dev/null 2>&1 || true
amixer -c 0 cset name='PRIMARY_MI2S_RX Audio Mixer MultiMedia1' 1 >/dev/null 2>&1 || true
amixer -c 0 cset name='RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia2' 1 >/dev/null 2>&1 || true

sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
  pactl set-card-profile alsa_card.platform-sound pro-audio 2>/dev/null || true
sleep 1
# Re-apply mixers after profile switch (ACP may touch controls)
amixer -c 0 cset name='DISPLAY_PORT_RX_0 Audio Mixer MultiMedia2' 0 >/dev/null 2>&1 || true
amixer -c 0 cset name='PRIMARY_MI2S_RX Audio Mixer MultiMedia1' 1 >/dev/null 2>&1 || true
amixer -c 0 cset name='RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia2' 1 >/dev/null 2>&1 || true

sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
  pactl set-default-sink alsa_output.platform-sound.pro-output-0 2>/dev/null || true

echo "=== Active profile / sinks (should stay on pro-audio; 2 pro-output*) ==="
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR pactl list cards | sed -n '/Active Profile:/p'
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR pactl list sinks short
echo "Watcher no longer forces HiFi while HDMI stays plugged. Test both Pro Audio outputs."
