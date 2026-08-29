#!/usr/bin/env bash
# EMERGENCY — revert broken quiet-session patches on a mounted SD/rootfs.
#
# Copy-paste (adjust SD path if needed):
#
#   SD=/run/media/steam/STORAGE
#   sudo mount -o remount,rw "$SD"
#   sudo bash "$SD/home/steam/Desktop/SteamOS-Ubuntu/scripts/restore-working-session.sh" "$SD"
#
set -euo pipefail

SD="${1:-/run/media/steam/STORAGE}"
PROJ="${SD}/home/steam/Desktop/SteamOS-Ubuntu"
SRC="${PROJ}/system_files"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root —  sudo bash $0 ${SD}" >&2
  exit 1
fi

for d in "${SD}/usr" "${SRC}/usr/local/bin/steamos-greetd-session"; do
  [[ -e "$d" ]] || { echo "ERROR: missing $d"; exit 1; }
done

mount -o remount,rw "${SD}" 2>/dev/null || true

echo "==> Copying known-good session scripts"
install -m 0755 "${SRC}/usr/local/bin/steamos-greetd-session" "${SD}/usr/local/bin/steamos-greetd-session"
install -m 0755 "${SRC}/usr/bin/gamescope-session" "${SD}/usr/bin/gamescope-session"
install -m 0755 "${SRC}/usr/libexec/steamos-ubuntu/launch-steam" "${SD}/usr/libexec/steamos-ubuntu/launch-steam"

echo "==> Removing broken helpers"
rm -f "${SD}/usr/libexec/steamos-ubuntu/session-common.sh"
rm -f "${SD}/etc/systemd/system/multi-user.target.wants/steamos-quiet-console.service"
rm -f "${SD}/etc/systemd/system/steamos-quiet-console.service"

echo "==> Force Gaming Mode"
mkdir -p "${SD}/var/lib/steamos-ubuntu"
printf '%s\n' 'gamescope-session' > "${SD}/var/lib/steamos-ubuntu/session"

sync "${SD}" 2>/dev/null || sync

if grep -q 'session_exec_detached\|session_reexec_detached\|session-common' \
    "${SD}/usr/local/bin/steamos-greetd-session" "${SD}/usr/bin/gamescope-session" 2>/dev/null; then
  echo "ERROR: restore failed — broken code still in session scripts" >&2
  exit 1
fi

if ! grep -q 'exec /usr/bin/gamescope-session' "${SD}/usr/local/bin/steamos-greetd-session"; then
  echo "ERROR: greetd script missing exec gamescope-session" >&2
  exit 1
fi

if grep -q 'session_debug' "${SD}/usr/libexec/steamos-ubuntu/launch-steam" 2>/dev/null; then
  echo "ERROR: launch-steam still references session_debug (breaks Steam with set -e)" >&2
  exit 1
fi

echo ""
echo "OK — SD repaired. Safely eject and boot the handheld."
echo "Last line of greetd script:"
tail -1 "${SD}/usr/local/bin/steamos-greetd-session"
