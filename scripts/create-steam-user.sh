#!/usr/bin/env bash
# Create steam:steam on a live host or mounted rootfs
set -euo pipefail
ROOT="${1:-/}"
STEAM_USER="${STEAM_USER:-steam}"
STEAM_PASS="${STEAM_PASS:-steam}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

if [[ "${ROOT}" == "/" ]]; then
  export STEAM_USER STEAM_PASS
  exec "$(cd "$(dirname "$0")/.." && pwd)/build_files/10-create-steam-user.sh"
fi

# chroot path
cp "$(cd "$(dirname "$0")/.." && pwd)/build_files/10-create-steam-user.sh" "${ROOT}/tmp/10-create-steam-user.sh"
chroot "${ROOT}" env STEAM_USER="${STEAM_USER}" STEAM_PASS="${STEAM_PASS}" bash /tmp/10-create-steam-user.sh
rm -f "${ROOT}/tmp/10-create-steam-user.sh"
