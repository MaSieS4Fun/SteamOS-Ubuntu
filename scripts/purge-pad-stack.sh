#!/usr/bin/env bash
# Purge all virtual-pad / gyro overlays so only the native AYN rsinput remains.
# Then optionally reinstall a clean InputPlumber (gamepad-only).
#
#   sudo ./scripts/purge-pad-stack.sh           # wipe only
#   sudo ./scripts/purge-pad-stack.sh --reinstall  # wipe + clean InputPlumber
#
set -euo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${_HERE}/.." && pwd)"
REINSTALL=0

for arg; do
  case "${arg}" in
    --reinstall) REINSTALL=1 ;;
    -h|--help)
      echo "Usage: sudo $0 [--reinstall]"
      exit 0
      ;;
  esac
done

log() { printf '==> [purge-pad] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root: sudo $0"

stop_disable_rm() {
  local unit="$1"
  systemctl stop "${unit}" 2>/dev/null || true
  systemctl disable "${unit}" 2>/dev/null || true
  systemctl reset-failed "${unit}" 2>/dev/null || true
}

log "1/5 Stop & disable pad / motion / InputPlumber units"
for u in \
  inputplumber.service \
  qcom-deck-pad.service \
  qcom-sdl-pad.service \
  qcom-motion.service \
  masi-qcom-sensors.service \
  masi-qcom-qrtr.service \
  masi-inputplumber-refresh.service \
  hexagonrpcd-adsp-rootpd.service \
  hexagonrpcd-adsp-sensorspd.service \
  hexagonrpcd-sdsp.service
do
  stop_disable_rm "$u"
done

# Kill leftover processes (legacy names)
pkill -x qcom-deck-pad 2>/dev/null || true
pkill -x qcom-sdl-pad 2>/dev/null || true
pkill -x qcom-motion 2>/dev/null || true
pkill -x batocera-qcom-motion 2>/dev/null || true
pkill -x inputplumber 2>/dev/null || true
pkill -f 'hexagonrpcd.*adsp' 2>/dev/null || true
sleep 1

log "2/5 Remove systemd units + drop-ins"
rm -f /etc/systemd/system/inputplumber.service
rm -rf /etc/systemd/system/inputplumber.service.d
rm -f /etc/systemd/system/multi-user.target.wants/inputplumber.service
rm -f /etc/systemd/system/multi-user.target.wants/qcom-*.service
rm -f /etc/systemd/system/multi-user.target.wants/masi-*.service
rm -f /etc/systemd/system/graphical.target.wants/qcom-*.service
rm -f /usr/lib/systemd/system/qcom-deck-pad.service \
  /usr/lib/systemd/system/qcom-sdl-pad.service \
  /usr/lib/systemd/system/qcom-motion.service \
  /usr/lib/systemd/system/masi-qcom-sensors.service \
  /usr/lib/systemd/system/masi-qcom-qrtr.service \
  /usr/lib/systemd/system/masi-inputplumber-refresh.service \
  /lib/systemd/system/qcom-deck-pad.service \
  /lib/systemd/system/qcom-sdl-pad.service \
  /lib/systemd/system/qcom-motion.service \
  /lib/systemd/system/masi-qcom-*.service 2>/dev/null || true
# Distro hexagonrpcd units from meson install — disable only, do not delete package files
systemctl disable hexagonrpcd-adsp-rootpd.service hexagonrpcd-adsp-sensorspd.service \
  hexagonrpcd-sdsp.service 2>/dev/null || true

log "3/5 Remove configs, udev, binaries, docs"
rm -rf /etc/inputplumber
rm -f /etc/udev/rules.d/70-qcom-sdl-pad.rules \
  /etc/udev/rules.d/*qcom*pad*.rules \
  /etc/udev/rules.d/*deck-pad*.rules 2>/dev/null || true
rm -f /etc/tmpfiles.d/masi-qcom.conf
rm -f /etc/polkit-1/rules.d/50-qcom-sdl-pad.rules
rm -f /etc/sudoers.d/qcom-sdl-pad
rm -f /etc/profile.d/qcom-sdl-pad.sh
rm -f /etc/sdl2/qcom-gamecontrollerdb.txt 2>/dev/null || true

# Binaries (leave hexagonrpcd/libssc if present — harmless when services off)
for bin in \
  qcom-deck-pad qcom-deck-pad-start \
  qcom-sdl-pad qcom-sdl-pad-start qcom-sdl-pad-gamescope \
  qcom-motion qcom-motion-start batocera-qcom-motion \
  masi-qcom-sensors qcom-sensors-rpc-supervisor \
  run-with-gyro-pad gyro-fix gyro-fix-apply \
  qcom-motion-settings qcom-motion-settings-apply \
  sdl-sensor-check
do
  rm -f "/usr/bin/${bin}" "/usr/local/bin/${bin}"
done

rm -rf /usr/share/doc/masi-motion /usr/share/doc/giroscopio /usr/share/doc/masi-qcom-gyro
rm -f /usr/share/applications/gyro-fix.desktop \
  /usr/local/share/applications/gyro-fix.desktop \
  /usr/share/applications/qcom-motion-settings.desktop 2>/dev/null || true

# Ready markers / runtime
rm -f /run/masi/qcom-motion.ready /run/masi/qcom-sensors.ready
rm -rf /run/masi 2>/dev/null || true

log "4/5 Remove InputPlumber package (if installed)"
if dpkg -l inputplumber 2>/dev/null | grep -q '^ii'; then
  apt-get remove -y --purge inputplumber 2>/dev/null \
    || dpkg --purge inputplumber 2>/dev/null \
    || true
fi
rm -rf /usr/share/inputplumber /etc/inputplumber
rm -f /usr/bin/inputplumber /usr/lib/systemd/system/inputplumber.service

udevadm control --reload-rules 2>/dev/null || true
systemctl daemon-reload
sleep 1

log "5/5 Native pad only (no virtual Deck/DualSense)"
echo "Remaining AYN / gamepad-ish nodes:"
grep -H . /sys/class/input/event*/device/name 2>/dev/null | grep -iE 'AYN|Gamepad|Steam|Sunshine|InputPlumber|Valve|DualSense' || true
echo ""
if systemctl is-active --quiet inputplumber.service 2>/dev/null; then
  die "inputplumber still active after purge"
fi
log "InputPlumber is OFF. Native AYN Odin2 Gamepad should work in desktop."
log "Gaming Mode needs InputPlumber for Deck layout — reinstall next."

if [[ "${REINSTALL}" -eq 1 ]]; then
  log "Reinstalling clean InputPlumber (gamepad-only, no IMU)"
  # Do not install masi-motion drop-in during clean path: temporarily skip if present
  "${ROOT_DIR}/scripts/install-inputplumber.sh" /
  # Ensure no IMU yaml leaked
  rm -f /etc/inputplumber/devices.d/02-ayn-controller+imu.yaml \
    /usr/share/inputplumber/devices.d/02-ayn-controller+imu.yaml 2>/dev/null || true
  # Prefer gamepad-only from tree
  install -m 0644 \
    "${ROOT_DIR}/system_files/etc/inputplumber/devices.d/02-ayn-controller.yaml" \
    /etc/inputplumber/devices.d/02-ayn-controller.yaml
  systemctl restart inputplumber.service
  sleep 2
  echo ""
  log "Verify:"
  inputplumber devices list 2>/dev/null || true
  inputplumber device 0 info 2>/dev/null || true
  grep -n 'passthrough\|imu\|deck' /etc/inputplumber/devices.d/02-ayn-controller.yaml || true
  echo ""
  log "Done. Test buttons in Gaming Mode."
else
  echo ""
  log "Wipe complete. When ready:"
  echo "  sudo ${ROOT_DIR}/scripts/purge-pad-stack.sh --reinstall"
  echo "  # or:"
  echo "  sudo ${ROOT_DIR}/scripts/install-inputplumber.sh"
fi
