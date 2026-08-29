#!/usr/bin/env bash
# Replace broken gallium / Turnip .so with a known-good copy (atomic pair).
# Use when dummy Mesa debs left an orphan gallium build on disk.
#
# Golden source (first match):
#   --from /media/odin2/STORAGE1
#   GOLDEN_ROOTFS env
#   output/work/mesa-*/src/... build tree
#   ../SteamOS-Ubuntu-no-giroscopio/output/work/mesa-*/
#
# Usage:
#   sudo ./scripts/sync-vendor-mesa-golden.sh /media/odin2/STORAGE
#   sudo ./scripts/sync-vendor-mesa-golden.sh /media/odin2/STORAGE --from /media/odin2/STORAGE1
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS=""
GOLDEN_ROOTFS="${GOLDEN_ROOTFS:-}"
MESA_VER="${MESA_VER:-26.1.6}"
FROM_EXPLICIT=""

log() { printf '==> [mesa-sync] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) GOLDEN_ROOTFS="$2"; FROM_EXPLICIT=1; shift 2 ;;
    -*) die "Unknown option: $1" ;;
    *)
      if [[ -z "$ROOTFS" ]]; then ROOTFS="$1"; else die "Extra arg: $1"; fi
      shift
      ;;
  esac
done

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs> [--from <golden-rootfs>]"
[[ "${EUID}" -eq 0 ]] || die "Run as root"

LIB="${ROOTFS}/usr/lib/aarch64-linux-gnu"
QUAR="${ROOTFS}/usr/share/sm8550-steamos/quarantine-bad-mesa"
mkdir -p "$LIB" "$QUAR"

resolve_golden_file() {
  local name="$1"
  local candidates=()

  if [[ -n "$GOLDEN_ROOTFS" ]]; then
    candidates+=("${GOLDEN_ROOTFS}/usr/lib/aarch64-linux-gnu/${name}")
  fi

  local build="${ROOT_DIR}/output/work/mesa-${MESA_VER}"
  case "$name" in
    libgallium-*.so)
      candidates+=("${build}/src/gallium/targets/dri/${name}")
      ;;
    libvulkan_freedreno.so)
      candidates+=("${build}/src/freedreno/vulkan/${name}")
      ;;
  esac

  local ref="${ROOT_DIR}/../SteamOS-Ubuntu-no-giroscopio/output/work/mesa-${MESA_VER}"
  case "$name" in
    libgallium-*.so)
      candidates+=("${ref}/src/gallium/targets/dri/${name}")
      candidates+=("${ROOT_DIR}/../SteamOS-Ubuntu-no-giroscopio/output/rootfs/usr/lib/aarch64-linux-gnu/${name}")
      ;;
    libvulkan_freedreno.so)
      candidates+=("${ref}/src/freedreno/vulkan/${name}")
      candidates+=("${ROOT_DIR}/../SteamOS-Ubuntu-no-giroscopio/output/rootfs/usr/lib/aarch64-linux-gnu/${name}")
      ;;
  esac

  local c
  for c in "${candidates[@]}"; do
    [[ -f "$c" ]] || continue
    printf '%s\n' "$c"
    return 0
  done
  return 1
}

install_one() {
  local dest_name="$1"
  local dest="${LIB}/${dest_name}"
  local src
  src="$(resolve_golden_file "$dest_name")" || die "No golden source for ${dest_name} (use --from STORAGE1 or build no-giroscopio)"

  if [[ -f "$dest" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    log "Quarantine old $(basename "$dest")"
    cp -a "$dest" "${QUAR}/${dest_name}.${ts}.bak"
  fi

  log "Install ${dest_name} ← ${src}"
  install -m 0755 "$src" "$dest"
  md5sum "$dest" "$src" | awk 'NR==1{g=$1} NR==2{w=$1} END{if(g==w) print "  md5 OK"; else {print "  md5 MISMATCH"; exit 1}}'
}

# Optional: sync entire vendor Mesa blob set from a golden rootfs.
sync_mesa_tree() {
  local golden_lib="${GOLDEN_ROOTFS}/usr/lib/aarch64-linux-gnu"
  [[ -d "$golden_lib" ]] || return 0
  log "Syncing vendor Mesa libs from golden rootfs"
  local pat
  for pat in 'libEGL_mesa.so*' 'libGLX_mesa.so*' 'libgbm.so*' 'libgallium-*.so' \
             'libvulkan_freedreno.so' 'libdrm_freedreno.so*' 'libGLESv2_mesa.so*'; do
    local f base
    for f in "${golden_lib}"/${pat}; do
      [[ -e "$f" ]] || continue
      base="$(basename "$f")"
      if [[ -L "$f" ]]; then
        local tgt
        tgt="$(readlink "$f")"
        ln -sfn "$tgt" "${LIB}/${base}"
      else
        install -m 0755 "$f" "${LIB}/${base}"
      fi
    done
  done
  if [[ -d "${GOLDEN_ROOTFS}/usr/lib/aarch64-linux-gnu/dri" ]]; then
    cp -a "${GOLDEN_ROOTFS}/usr/lib/aarch64-linux-gnu/dri/." "${LIB}/dri/"
  fi
  if [[ -d "${GOLDEN_ROOTFS}/usr/lib/aarch64-linux-gnu/gbm" ]]; then
    cp -a "${GOLDEN_ROOTFS}/usr/lib/aarch64-linux-gnu/gbm/." "${LIB}/gbm/"
  fi
}

if [[ -n "$GOLDEN_ROOTFS" && -d "${GOLDEN_ROOTFS}/usr/lib/aarch64-linux-gnu" ]]; then
  sync_mesa_tree
else
  install_one "libgallium-${MESA_VER}.so"
  install_one "libvulkan_freedreno.so"
fi

ldconfig -r "$ROOTFS" 2>/dev/null || true

if [[ -x "${ROOT_DIR}/scripts/verify-vendor-mesa-stack.sh" ]]; then
  "${ROOT_DIR}/scripts/verify-vendor-mesa-stack.sh" "$ROOTFS"
fi

log "Done — reboot SD and test Gaming Mode"
