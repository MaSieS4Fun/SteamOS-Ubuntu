#!/usr/bin/env bash
# One-shot: remount STORAGE + apply polish (needs your sudo password once).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORAGE="${1:-/media/odin2/STORAGE}"
sudo mount -o remount,rw "$STORAGE"
sudo "$ROOT_DIR/scripts/fix-desktop-polish-on-rootfs.sh" "$STORAGE"
echo
echo "Done. Reboot the handheld (or reboot into the image) and retest."
