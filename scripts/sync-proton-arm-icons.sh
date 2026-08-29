#!/usr/bin/env bash
# Regenerate Proton ARM Easy Manager icon sizes from vendor/eparm.png (master).
# The install script uses data/icons/eparm.png first — keep it in sync with the root master.
#
# Usage:
#   ./scripts/sync-proton-arm-icons.sh
#   EPARM_MASTER=/path/to/new.png ./scripts/sync-proton-arm-icons.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="${ROOT_DIR}/vendor/Proton-ARM-Easy-Manager"
MASTER="${EPARM_MASTER:-${VENDOR}/eparm.png}"
ICONS="${VENDOR}/data/icons"

log() { printf '==> [proton-arm-icons] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$MASTER" ]] || die "Master icon not found: ${MASTER} (set EPARM_MASTER=...)"

mkdir -p "$ICONS"
cp -f "$MASTER" "${ICONS}/eparm.png"
log "Synced master → ${ICONS}/eparm.png"

if python3 - <<'PY' "$MASTER" "$ICONS"
import sys
from pathlib import Path
try:
    from PIL import Image
except ImportError:
    sys.exit(2)

master, icons = Path(sys.argv[1]), Path(sys.argv[2])
img = Image.open(master)
if img.mode not in ("RGBA", "RGB"):
    img = img.convert("RGBA")
resample = getattr(Image, "Resampling", Image).LANCZOS
for size in (16, 24, 32, 48, 64, 128, 256, 512):
    out = icons / f"eparm-{size}.png"
    resized = img.resize((size, size), resample)
    resized.save(out, "PNG")
    print(f"wrote {out}")
PY
then
  log "Generated eparm-{16..512}.png with PIL"
elif command -v convert >/dev/null 2>&1; then
  for size in 16 24 32 48 64 128 256 512; do
    convert "$MASTER" -resize "${size}x${size}" "${ICONS}/eparm-${size}.png"
  done
  log "Generated sizes with ImageMagick convert"
else
  for size in 16 24 32 48 64 128 256 512; do
    cp -f "${ICONS}/eparm.png" "${ICONS}/eparm-${size}.png"
  done
  log "PIL/ImageMagick missing — copied eparm.png to all eparm-*.png (install python3-pil for crisp sizes)"
fi

log "Done"
