#!/usr/bin/env bash
# Install x11-utils tools into live STORAGE + refresh gamescope-session / launch-steam.
# Prefer copying from this repo staging (same arm64 host); fall back to apt download.
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/system_files"
STAGE="$REPO/scripts/staging-x11-utils"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -d "$ROOT/usr" ]] || { echo "ERROR: bad root $ROOT"; exit 1; }
[[ "${EUID}" -eq 0 ]] || { echo "ERROR: run as root (sudo)"; exit 1; }

install -m 0755 "$SRC/usr/bin/gamescope-session" "$ROOT/usr/bin/gamescope-session"
install -m 0755 "$SRC/usr/libexec/steamos-ubuntu/launch-steam" \
  "$ROOT/usr/libexec/steamos-ubuntu/launch-steam"

install_bins_from() {
  local from="$1"
  mkdir -p "$ROOT/usr/bin"
  for b in xwininfo xprop xdpyinfo xdriinfo; do
    [[ -x "$from/usr/bin/$b" ]] || continue
    install -m 0755 "$from/usr/bin/$b" "$ROOT/usr/bin/$b"
  done
}

if [[ -x "$ROOT/usr/bin/xwininfo" ]]; then
  echo "xwininfo already present: $ROOT/usr/bin/xwininfo"
elif [[ -x "$STAGE/usr/bin/xwininfo" ]]; then
  echo "Installing x11 tools from repo staging..."
  install_bins_from "$STAGE"
elif command -v apt-get >/dev/null; then
  echo "Downloading x11-utils..."
  cd "$TMP"
  apt-get download x11-utils
  dpkg-deb -x x11-utils_*.deb "$TMP/x11"
  install_bins_from "$TMP/x11"
else
  echo "ERROR: no staging xwininfo and no apt-get"; exit 1
fi

ls -la "$ROOT/usr/bin/xwininfo" "$ROOT/usr/bin/xprop"

echo "Done. sudo reboot"
echo "Expect in /var/tmp/steamos-session.log: xwininfo tree dumps + no 'xwininfo: not found'"
echo "Also copy: console_log.txt connection_log.txt (from Steam logs/)"
