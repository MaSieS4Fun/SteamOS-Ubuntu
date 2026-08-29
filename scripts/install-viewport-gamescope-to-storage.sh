#!/usr/bin/env bash
# Install prebuilt viewport gamescope from /tmp/gamescope-stage into STORAGE rootfs.
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
STAGE="${2:-/tmp/gamescope-stage}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[[ -x "$STAGE/usr/local/bin/gamescope" ]] || { echo "missing $STAGE/usr/local/bin/gamescope — rebuild first"; exit 1; }
[[ -d "$ROOT/usr" ]] || { echo "missing rootfs $ROOT"; exit 1; }
install -d "$ROOT/usr/local/bin"
install -m 0755 "$STAGE/usr/local/bin/gamescope" "$ROOT/usr/local/bin/gamescope"
if [[ -d "$STAGE/usr/local/lib" ]]; then
  rsync -a "$STAGE/usr/local/lib/" "$ROOT/usr/local/lib/"
fi
if [[ -d "$STAGE/usr/local/share" ]]; then
  rsync -a "$STAGE/usr/local/share/" "$ROOT/usr/local/share/"
fi
install -m 0755 "$REPO/system_files/usr/bin/gamescope-session" "$ROOT/usr/bin/gamescope-session"
install -m 0755 "$REPO/system_files/usr/libexec/steamos-ubuntu/launch-steam" \
  "$ROOT/usr/libexec/steamos-ubuntu/launch-steam"
echo "OK: installed viewport gamescope → $ROOT"
"$ROOT/usr/local/bin/gamescope" --version 2>&1 | head -3 || true
strings "$ROOT/usr/local/bin/gamescope" | grep -E 'VIEWPORT_SUPPORTED|VROVERLAY_FORWARDING|GAMESCOPE_PID' | sort -u
