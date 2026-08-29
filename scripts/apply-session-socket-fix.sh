#!/usr/bin/env bash
# Copy the -R socket gamescope-session + launch-steam fix onto a live STORAGE rootfs.
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/system_files"
install -m 0755 "$SRC/usr/bin/gamescope-session" "$ROOT/usr/bin/gamescope-session"
install -m 0755 "$SRC/usr/libexec/steamos-ubuntu/launch-steam" \
  "$ROOT/usr/libexec/steamos-ubuntu/launch-steam"
# Drop CEF GPU experiment flags if an old session wrapper still references them — N/A after replace.
echo "Installed socket-mode session into $ROOT"
echo "Reboot into Gaming Mode; wait 60–90s before powering off."
echo "Success signal in /var/tmp/steamos-session.log:"
echo "  gamescope ready: DISPLAY=..."
echo "  (no BMainLoop stall; webhelper progresses past Starting message loop)"
