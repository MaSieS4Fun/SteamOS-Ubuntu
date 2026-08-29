#!/bin/bash
# quick apply for user
set -e
ROOT=/home/steam/Desktop/SteamOS-Ubuntu
install -D -m 0644 "$ROOT/vendor/audio/ucm2/AYN/Odin2/HiFi.conf" /usr/share/alsa/ucm2/AYN/Odin2/HiFi.conf
install -D -m 0644 "$ROOT/vendor/audio/ucm2/AYN/Thor/HiFi.conf" /usr/share/alsa/ucm2/AYN/Thor/HiFi.conf
install -D -m 0755 "$ROOT/system_files/usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink" \
  /usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink
install -D -m 0644 "$ROOT/system_files/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" \
  /usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf
UID_STEAM=$(id -u steam)
export XDG_RUNTIME_DIR=/run/user/$UID_STEAM
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
  systemctl --user restart pipewire.socket pipewire pipewire-pulse wireplumber || true
sleep 2
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
  /usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink --once || true
echo "=== profiles ==="
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR pactl list cards | sed -n '/Profiles:/,/Active Profile:/p'
echo "=== sinks ==="
sudo -u steam env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR pactl list sinks short
