#!/usr/bin/env bash
# Install masi-motion (SSC → uinput IMU) + InputPlumber (gamepad default).
#
# Desktop: gamepad-only (GYRO-FIX optional DSU). Gaming Mode hooks enable IMU.
#   sudo ./scripts/install-masi-motion.sh
#   sudo ./vendor/gyro-desktop/install.sh
#
set -euo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${_HERE}/.." && pwd)"
MM_DIR="${ROOT_DIR}/vendor/masi-motion"
IP_SCRIPT="${ROOT_DIR}/scripts/install-inputplumber.sh"
ENABLE_GYRO=0

for arg; do
  case "${arg}" in
    --with-gyro) ENABLE_GYRO=1 ;;
    --without-gyro) ENABLE_GYRO=0 ;;
  esac
done

log() { printf '==> [masi-motion+ip] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root (sudo ./scripts/install-masi-motion.sh)"
[[ -x "${MM_DIR}/install.sh" ]] || die "Missing ${MM_DIR}/install.sh"
[[ -x "${IP_SCRIPT}" ]] || die "Missing ${IP_SCRIPT}"

MM_ARGS=()
for arg; do
  case "${arg}" in
    --with-gyro|--without-gyro) ;;
    *) MM_ARGS+=("${arg}") ;;
  esac
done

log "Step 1/2 — masi-motion (odin2-dsu-v9)"
"${MM_DIR}/install.sh" "${MM_ARGS[@]+"${MM_ARGS[@]}"}"

log "Step 2/2 — InputPlumber (gamepad default)"
"${IP_SCRIPT}"

install -d /etc/systemd/system/inputplumber.service.d
install -m 0644 \
  "${ROOT_DIR}/system_files/etc/systemd/system/inputplumber.service.d/masi-motion.conf" \
  /etc/systemd/system/inputplumber.service.d/masi-motion.conf
systemctl daemon-reload
systemctl reset-failed inputplumber.service 2>/dev/null || true
systemctl enable --now inputplumber.service 2>/dev/null || systemctl restart inputplumber.service || true

if [[ "${ENABLE_GYRO}" -eq 1 ]]; then
  log "Enabling IMU composite (--with-gyro)"
  "${ROOT_DIR}/scripts/enable-inputplumber-gyro.sh"
else
  log "Gamepad-only (default). Optional DSU: GYRO-FIX app / vendor/gyro-desktop"
  if [[ -x "${ROOT_DIR}/scripts/restore-inputplumber-gamepad.sh" ]]; then
    # Keep motion available for later; restore script stops motion — skip if gyro-desktop manages it
    true
  fi
fi

if [[ -x "${ROOT_DIR}/vendor/gyro-desktop/install.sh" ]]; then
  log "Install GYRO-FIX desktop helpers"
  "${ROOT_DIR}/vendor/gyro-desktop/install.sh" /
fi

echo ""
log "Verify pad: inputplumber device 0 info"
log "GYRO-FIX: gyro-fix   |  DSU: sudo gyro-fix-dsu on"
