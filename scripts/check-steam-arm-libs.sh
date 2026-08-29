#!/usr/bin/env bash
# Check SteamARM shared-library deps on a rootfs / live STORAGE tree.
# Usage: sudo ./scripts/check-steam-arm-libs.sh [/media/odin2/STORAGE]
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
S="${ROOT}/home/steam/.local/share/Steam"
R="${S}/steamrtarm64"
export LD_LIBRARY_PATH="${R}:${S}/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

[[ -d "$R" ]] || { echo "ERROR: missing $R"; exit 1; }

echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo

missing=0
for b in steam steamui.so steamwebhelper libvideo.so libSDL3.so.0 libtier0_s.so; do
  f="$R/$b"
  if [[ ! -e "$f" ]]; then
    echo "MISSING FILE: $f"
    missing=1
    continue
  fi
  miss="$(ldd "$f" 2>/dev/null | grep 'not found' || true)"
  if [[ -n "$miss" ]]; then
    echo "BROKEN: $b"
    echo "$miss"
    missing=1
  else
    echo "OK: $b"
  fi
done

echo
echo "=== system vpx / openal (hygiene; Steam usually ships its own libvpx) ==="
ls -la "${ROOT}/usr/lib/aarch64-linux-gnu/libvpx.so"* 2>/dev/null | head -8 || true
ls -la "${ROOT}/usr/lib/aarch64-linux-gnu/libopenal.so"* 2>/dev/null | head -4 || true
ls -la "$R"/libvpx.so* 2>/dev/null | head -4 || true

# Resolute hygiene: Steam sometimes expects libvpx.so.6 on the system path
if [[ ! -e "${ROOT}/usr/lib/aarch64-linux-gnu/libvpx.so.6" ]]; then
  if [[ -e "${ROOT}/usr/lib/aarch64-linux-gnu/libvpx.so.12" ]]; then
    echo "NOTE: no libvpx.so.6 — on Resolute you can: ln -s libvpx.so.12 .../libvpx.so.6"
  elif [[ -e "${ROOT}/usr/lib/aarch64-linux-gnu/libvpx.so.9" ]]; then
    echo "NOTE: no libvpx.so.6 — symlink to libvpx.so.9 if needed"
  fi
fi

if [[ "$missing" -ne 0 ]]; then
  echo
  echo "RESULT: missing libs/files — install/fix those first"
  exit 2
fi
echo
echo "RESULT: no 'not found' in key SteamARM binaries"
