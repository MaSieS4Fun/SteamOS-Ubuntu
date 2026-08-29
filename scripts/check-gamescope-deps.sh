#!/usr/bin/env bash
# Compatibility wrapper → ensure-gamescope-libs.sh
# Usage: check-gamescope-deps.sh <rootfs|/ > [gamescope] [--check-only]
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${ROOT_DIR}/scripts/ensure-gamescope-libs.sh" "$@"
