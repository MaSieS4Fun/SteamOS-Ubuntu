#!/usr/bin/env bash
# Apply Decky PluginLoader systemd drop-ins on a live handheld or mounted rootfs.
# Fixes aarch64 + FEX: root unit must see steam user's FEX RootFS (Config.json).
#
# Usage:
#   sudo ./scripts/apply-decky-plugin-loader-fix.sh
#   sudo ./scripts/apply-decky-plugin-loader-fix.sh /media/odin2/STORAGE
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-/}"
[[ "$ROOTFS" == "/" ]] || ROOTFS="${ROOTFS%/}"
DROP_DIR="${ROOT_DIR}/vendor/system-fixes/LSFG-VK/plugin_loader.service.d"

log() { printf '==> [decky-fix] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root (sudo)"
[[ -d "$DROP_DIR" ]] || die "Missing ${DROP_DIR}"

for f in fast-stop.conf fex-steam-rootfs.conf; do
  [[ -f "${DROP_DIR}/${f}" ]] || continue
  install -D -m 0644 "${DROP_DIR}/${f}" \
    "${ROOTFS}/etc/systemd/system/plugin_loader.service.d/${f}"
  log "Installed plugin_loader.service.d/${f}"
done

if [[ "$ROOTFS" == "/" ]]; then
  systemctl daemon-reload
  if systemctl is-enabled plugin_loader.service &>/dev/null; then
    systemctl restart plugin_loader.service || systemctl start plugin_loader.service
    systemctl --no-pager -l status plugin_loader.service || true
  else
    log "plugin_loader.service not enabled; drop-ins installed (enable after Decky install)"
  fi
else
  log "Rootfs only — reload/restart on device after reboot"
fi
