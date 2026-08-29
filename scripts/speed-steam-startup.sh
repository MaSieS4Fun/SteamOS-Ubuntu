#!/usr/bin/env bash
# Steam startup fixes are part of finalize-handheld-rootfs.sh (steamos-manager + launch-steam).
# Kept as a named entry point for docs / habit.
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$REPO/scripts/finalize-handheld-rootfs.sh" "$ROOT"
