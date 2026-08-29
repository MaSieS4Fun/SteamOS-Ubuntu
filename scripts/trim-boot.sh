#!/usr/bin/env bash
# Boot trim is part of finalize-handheld-rootfs.sh (image build + STORAGE sync).
# Kept as a named entry point for docs / habit.
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$REPO/scripts/finalize-handheld-rootfs.sh" "$ROOT"
