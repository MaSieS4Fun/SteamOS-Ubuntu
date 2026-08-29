#!/usr/bin/env bash
# Stage host libs that vendor Turnip (built on host) needs but Ubuntu rootfs
# may not provide at the same SONAME (e.g. libdisplay-info.so.2 vs .so.3).
# Usage: sudo ./scripts/fix-turnip-runtime-libs.sh /media/odin2/STORAGE
set -euo pipefail

ROOTFS="${1:-}"
[[ -n "$ROOTFS" && -d "${ROOTFS}/usr/lib" ]] || {
  echo "Usage: $0 <rootfs>" >&2
  exit 1
}
[[ "${EUID}" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

LIB="${ROOTFS}/usr/lib/aarch64-linux-gnu"
HOST=/usr/lib/aarch64-linux-gnu
mkdir -p "$LIB"

# Exact SONAMEs from: readelf -d …/libvulkan_freedreno.so | grep NEEDED
NEED=(
  libxcb-keysyms.so.1
  libdisplay-info.so.2
)

stage() {
  local so="$1" src real base
  if [[ -e "${LIB}/${so}" ]]; then
    echo "OK already: ${so}"
    return 0
  fi
  src="${HOST}/${so}"
  [[ -e "$src" ]] || {
    echo "MISSING on host: ${src}" >&2
    return 1
  }
  real="$(readlink -f "$src")"
  base="$(basename "$real")"
  cp -a "$real" "${LIB}/"
  ln -sfn "$base" "${LIB}/${so}"
  # preserve intermediate link names (e.g. libdisplay-info.so.0.2.0)
  if [[ -L "$src" ]]; then
    ln -sfn "$base" "${LIB}/$(basename "$src")"
  fi
  echo "staged ${so} ← ${real}"
}

fail=0
for so in "${NEED[@]}"; do
  stage "$so" || fail=$((fail + 1))
done

ldconfig -r "$ROOTFS" 2>/dev/null || true

# Verify Turnip can resolve all NEEDED
miss=0
while read -r so; do
  [[ "$so" == ld-linux* ]] && continue
  if [[ ! -e "${LIB}/${so}" && ! -e "${ROOTFS}/lib/aarch64-linux-gnu/${so}" ]]; then
    echo "STILL MISSING: ${so}"
    miss=$((miss + 1))
  fi
done < <(readelf -d "${LIB}/libvulkan_freedreno.so" | awk '/NEEDED/{gsub(/[][]/,"",$NF); print $NF}')

if (( fail || miss )); then
  echo "FAIL — Turnip still cannot load (${fail} stage fails, ${miss} missing)" >&2
  exit 1
fi

echo "PASS — Turnip runtime libs present under ${LIB}"
echo "Reboot (or re-login greetd) and check /var/tmp/steamos-session.log"
