#!/usr/bin/env bash
# Toggle Steam CEF GPU mode on a mounted rootfs.
# software = pass -cef-disable-gpu to Steam (diagnostic: rule out CEF GPU init hang)
# normal   = remove the override and go back to default CEF GPU behavior
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${2:-/media/odin2/STORAGE}"
MODE="${1:-software}"
MODE_FILE="${ROOTFS}/var/lib/steamos-ubuntu/steam-cef-mode"

log() { printf '==> [cef-mode] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -d "${ROOTFS}/usr" ]] || die "Rootfs not found: ${ROOTFS}"

install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/bin/gamescope-session" \
  "${ROOTFS}/usr/bin/gamescope-session"
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"

mkdir -p "${ROOTFS}/var/lib/steamos-ubuntu"

case "$MODE" in
  software|disable-gpu|cpu)
    printf '%s\n' 'software' >"$MODE_FILE"
    log "Enabled CEF software mode (-cef-disable-gpu)"
    ;;
  normal|gpu|default|off)
    rm -f "$MODE_FILE"
    log "Removed CEF software override"
    ;;
  *)
    die "Usage: $0 <software|normal> [rootfs]"
    ;;
esac

"${ROOT_DIR}/scripts/fix-storage-steam-htmlcache.sh" "$ROOTFS"

log "Updated ${ROOTFS}"
log "Reboot into Gaming Mode and inspect /var/log/steamos-session.log"
log "Expected marker: steam-cef-mode=software -> -cef-disable-gpu"
