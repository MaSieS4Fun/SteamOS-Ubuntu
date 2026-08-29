#!/usr/bin/env bash
# Restore working HiFi (DisplayPort, Speaker) + fixed watcher (no fight Pro Audio).
set -euo pipefail
ROOT=/home/steam/Desktop/SteamOS-Ubuntu
[[ "${EUID}" -eq 0 ]] || exec pkexec "$0" "$@"

echo "==> Install UCM HiFi (Speaker + DisplayPort, no Headphones)"
install -D -m 0644 "$ROOT/vendor/audio/ucm2/AYN/Odin2/HiFi.conf" \
  /usr/share/alsa/ucm2/AYN/Odin2/HiFi.conf
install -D -m 0644 "$ROOT/vendor/audio/ucm2/AYN/Thor/HiFi.conf" \
  /usr/share/alsa/ucm2/AYN/Thor/HiFi.conf
install -D -m 0644 \
  "$ROOT/system_files/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" \
  /usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf
install -D -m 0755 \
  "$ROOT/system_files/usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink" \
  /usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink

UID_STEAM=$(id -u steam)
export XDG_RUNTIME_DIR=/run/user/$UID_STEAM

echo "==> Restart PipeWire / WirePlumber / watcher"
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
  systemctl --user restart pipewire.socket pipewire pipewire-pulse wireplumber 2>/dev/null || true
sleep 2
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
  systemctl --user restart sm8550-prefer-speaker-sink.service 2>/dev/null || true
sleep 1
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
  /usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink --once || true

echo "==> Profiles / sinks"
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
  pactl list cards | sed -n '/Profiles:/,/Active Profile:/p'
echo "---"
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR pactl list sinks short
echo "==> Done. Expect HiFi (DisplayPort, Speaker) + pro-audio."
