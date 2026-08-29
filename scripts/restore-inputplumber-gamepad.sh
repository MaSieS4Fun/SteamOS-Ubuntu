#!/usr/bin/env bash
# Hard restore: gamepad-only InputPlumber (no IMU yaml, motion stack stopped).
set -euo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${_HERE}/.." && pwd)"
IP_SRC="${ROOT_DIR}/system_files/etc/inputplumber"
GAMEPAD_YAML="${IP_SRC}/optional/02-ayn-controller-gamepad-only.yaml"

log() { printf '==> [restore-gamepad] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root: sudo $0"
[[ -f "${GAMEPAD_YAML}" ]] || die "Missing ${GAMEPAD_YAML}"

log "Stop motion stack so IMU cannot reattach to composite"
systemctl stop qcom-motion.service 2>/dev/null || true
systemctl disable qcom-motion.service 2>/dev/null || true
sleep 1

log "Purge leftover IMU-named composites"
rm -f /etc/inputplumber/devices.d/02-ayn-controller+imu.yaml \
  /etc/inputplumber/devices.d/*imu*.yaml \
  /usr/share/inputplumber/devices.d/02-ayn-controller+imu.yaml \
  /usr/share/inputplumber/devices.d/*imu*.yaml 2>/dev/null || true

log "Install gamepad-only composite (passthrough: true, no IMU)"
install -d /etc/inputplumber/devices.d
install -m 0644 "${GAMEPAD_YAML}" /etc/inputplumber/devices.d/02-ayn-controller.yaml
if [[ -d /usr/share/inputplumber/devices.d ]]; then
  install -m 0644 "${GAMEPAD_YAML}" /usr/share/inputplumber/devices.d/02-ayn-controller.yaml
fi

if [[ -f "${ROOT_DIR}/system_files/etc/systemd/system/inputplumber.service.d/masi-motion.conf" ]]; then
  install -d /etc/systemd/system/inputplumber.service.d
  install -m 0644 \
    "${ROOT_DIR}/system_files/etc/systemd/system/inputplumber.service.d/masi-motion.conf" \
    /etc/systemd/system/inputplumber.service.d/masi-motion.conf
fi

log "Restart inputplumber cleanly"
systemctl daemon-reload
systemctl reset-failed inputplumber.service 2>/dev/null || true
systemctl stop inputplumber.service 2>/dev/null || true
sleep 1
systemctl start inputplumber.service
sleep 2

if ! systemctl is-active --quiet inputplumber.service; then
  die "inputplumber failed — journalctl -u inputplumber -n 40"
fi
log "inputplumber.service is active"

echo ""
log "Active device configs:"
ls -la /etc/inputplumber/devices.d/ || true
echo ""
log "Composite:"
inputplumber devices list 2>/dev/null || true
inputplumber device 0 info 2>/dev/null || true
echo ""
log "YAML check (must NOT contain group: imu):"
grep -n 'imu\|passthrough' /etc/inputplumber/devices.d/02-ayn-controller.yaml || true
echo ""
log "Done. Gyro again: sudo ./scripts/enable-inputplumber-gyro.sh"
