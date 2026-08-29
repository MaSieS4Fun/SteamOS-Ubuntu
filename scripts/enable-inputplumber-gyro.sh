#!/usr/bin/env bash
# Enable AYN Layout + masi-motion IMU → deck-uhid (after gamepad-only is verified).
set -euo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${_HERE}/.." && pwd)"
IP_SRC="${ROOT_DIR}/system_files/etc/inputplumber"
IMU_YAML="${IP_SRC}/optional/02-ayn-controller+imu.yaml"
IMU_MAP="${IP_SRC}/capability_maps.d/imu_generic.yaml"

log() { printf '==> [enable-gyro] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root: sudo $0"
[[ -f "${IMU_YAML}" ]] || die "Missing ${IMU_YAML}"
[[ -f "${IMU_MAP}" ]] || die "Missing ${IMU_MAP}"

if [[ ! -f /run/masi/qcom-motion.ready ]]; then
  log "WARN: qcom-motion not ready — install/start masi-motion first"
fi

log "Install IMU capability map"
install -d /etc/inputplumber/capability_maps.d /usr/share/inputplumber/capability_maps
install -m 0644 "${IMU_MAP}" /etc/inputplumber/capability_maps.d/imu_generic.yaml
install -m 0644 "${IMU_MAP}" /usr/share/inputplumber/capability_maps/imu_generic.yaml

log "Switch composite to gamepad + IMU (passthrough: false on gamepad)"
install -m 0644 "${IMU_YAML}" /etc/inputplumber/devices.d/02-ayn-controller.yaml
if [[ -d /usr/share/inputplumber/devices.d ]]; then
  install -m 0644 "${IMU_YAML}" /usr/share/inputplumber/devices.d/02-ayn-controller.yaml
fi

install -d /etc/systemd/system/inputplumber.service.d
install -m 0644 \
  "${ROOT_DIR}/system_files/etc/systemd/system/inputplumber.service.d/masi-motion.conf" \
  /etc/systemd/system/inputplumber.service.d/masi-motion.conf

systemctl daemon-reload
systemctl restart qcom-motion.service 2>/dev/null || true
sleep 2
systemctl restart inputplumber.service
sleep 2

log "Verify:"
inputplumber device 0 info 2>/dev/null || true
grep -l 'Sunshine gamepad (virtual) motion sensors' /sys/class/input/event*/device/name 2>/dev/null || \
  log "WARN: IMU node not found — rebuild qcom-motion (masi-motion build.sh)"
