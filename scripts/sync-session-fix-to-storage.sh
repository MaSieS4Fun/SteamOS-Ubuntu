#!/usr/bin/env bash
# Sync latest Gaming Mode / OOBE / boot-trim fixes onto a mounted STORAGE rootfs.
# Thin wrapper around finalize-handheld-rootfs.sh (full image defaults).
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
exec "$REPO/scripts/finalize-handheld-rootfs.sh" "$ROOT"
