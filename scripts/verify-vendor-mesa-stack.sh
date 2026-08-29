#!/usr/bin/env bash
# Verify vendor Mesa stack on a rootfs (mounted SD or output/rootfs).
#
# Hard fail: missing runtime files, broken dri_gbm linkage, dummy libgbm,
#            known-broken STORAGE gallium/Turnip hashes.
# Advisory:  STORAGE1 golden MD5 / build-id (a fresh meson compile never matches).
#            Set MESA_REQUIRE_GOLDEN=1 to make golden hashes fatal.
#
# Usage:
#   ./scripts/verify-vendor-mesa-stack.sh /media/odin2/STORAGE
#   ./scripts/verify-vendor-mesa-stack.sh /home/odin2/Desktop/SteamOS-Ubuntu/output/rootfs
#
# Exit 0 = PASS, 1 = FAIL.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
MESA_VER="${MESA_VER:-26.1.6}"
GOLDEN_FILE="${GOLDEN_FILE:-${ROOT_DIR}/config/mesa-golden.sha256}"
REQUIRE_GOLDEN="${MESA_REQUIRE_GOLDEN:-0}"

# Hashes that produced CEF BMainLoop stall on STORAGE (must never ship).
BROKEN_GALLIUM_MD5="051a0a6c0b573141eb623031358b2f15"
BROKEN_TURNIP_MD5="4f11ac85c576eb59a5dea198390bef8b"
BROKEN_GALLIUM_BID="9a32443eed9beedb556d17c1b563ddd208fe54de"
GOLDEN_GALLIUM_BID="9370272e461689dbee8373432a7e9292e3bae92f"

log() { printf '==> [mesa-verify] %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || {
  echo "Usage: $0 <rootfs>" >&2
  exit 1
}

LIB="${ROOTFS}/usr/lib/aarch64-linux-gnu"
GALLIUM="${LIB}/libgallium-${MESA_VER}.so"
TURNIP="${LIB}/libvulkan_freedreno.so"
errors=0

check_file() {
  local rel="$1" path="${ROOTFS}/${1#./}"
  [[ -e "$path" ]] || { fail "missing ${rel}"; }
}

log "Rootfs: ${ROOTFS}"

for req in \
  "${LIB}/libvulkan_freedreno.so" \
  "${LIB}/libgallium-${MESA_VER}.so" \
  "${LIB}/libEGL_mesa.so.0" \
  "${LIB}/libGLX_mesa.so.0" \
  "${LIB}/libgbm.so.1" \
  "${LIB}/dri/msm_dri.so" \
  "${LIB}/gbm/dri_gbm.so"
do
  if [[ ! -e "$req" ]]; then
    fail "missing ${req#"$ROOTFS"}"
  fi
done

gallium_md5="$(md5sum "$GALLIUM" | awk '{print $1}')"
turnip_md5="$(md5sum "$TURNIP" | awk '{print $1}')"
log "libgallium md5: ${gallium_md5}"
log "Turnip md5:     ${turnip_md5}"
if [[ "$gallium_md5" == "$BROKEN_GALLIUM_MD5" || "$turnip_md5" == "$BROKEN_TURNIP_MD5" ]]; then
  fail "known-broken STORAGE Mesa blobs on disk — reinstall vendor Mesa"
fi

if [[ -f "$GOLDEN_FILE" ]]; then
  log "Golden reference (${GOLDEN_FILE#"$ROOT_DIR"/}) — advisory unless MESA_REQUIRE_GOLDEN=1"
  while read -r expected rel _; do
    [[ -z "${expected:-}" || "$expected" == \#* ]] && continue
    path="${ROOTFS}/${rel}"
    [[ -e "$path" ]] || { fail "golden target missing: ${rel}"; }
    got="$(md5sum "$path" | awk '{print $1}')"
    if [[ "$got" == "$expected" ]]; then
      printf '  OK  %s\n' "$rel"
    else
      printf '  DIFF %s  got=%s ref=%s\n' "$rel" "$got" "$expected"
      if [[ "$REQUIRE_GOLDEN" == "1" ]]; then
        errors=$((errors + 1))
      else
        log "  (fresh meson compile is expected to differ from STORAGE1 reference)"
      fi
    fi
  done <"$GOLDEN_FILE"
fi

if command -v readelf >/dev/null 2>&1; then
  bid="$(readelf -n "$GALLIUM" 2>/dev/null | awk '/Build ID/{print $3; exit}')"
  log "libgallium build-id: ${bid:-unknown}"
  if [[ "${bid:-}" == "$BROKEN_GALLIUM_BID" ]]; then
    fail "known-broken STORAGE gallium build-id"
  fi
  if [[ "${bid:-}" != "$GOLDEN_GALLIUM_BID" ]]; then
    log "gallium build-id != STORAGE1 reference (ok for a new compile)"
    if [[ "$REQUIRE_GOLDEN" == "1" ]]; then
      errors=$((errors + 1))
    fi
  fi
  if ! readelf -d "${LIB}/gbm/dri_gbm.so" 2>/dev/null | grep -q "libgallium-${MESA_VER}"; then
    warn "dri_gbm.so not linked to libgallium-${MESA_VER}"
    errors=$((errors + 1))
  fi
fi

icd="${ROOTFS}/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
[[ -f "$icd" ]] || icd="${ROOTFS}/usr/share/vulkan/icd.d/freedreno_icd.json"
[[ -f "$icd" ]] || { fail "missing Turnip ICD json"; }

if [[ -f "$TURNIP" ]] && command -v readelf >/dev/null 2>&1; then
  while read -r so; do
    [[ "$so" == ld-linux* ]] && continue
    if [[ ! -e "${LIB}/${so}" && ! -e "${ROOTFS}/lib/aarch64-linux-gnu/${so}" ]]; then
      warn "Turnip NEEDED missing: ${so}"
      errors=$((errors + 1))
    fi
  done < <(readelf -d "$TURNIP" | awk '/NEEDED/{gsub(/[][]/,"",$NF); print $NF}')
fi

status_file="${ROOTFS}/var/lib/dpkg/status"
if [[ -f "$status_file" ]]; then
  for pkg in libgbm1 libgbm-dev; do
    ver="$(awk -v pkg="$pkg" '
      $1=="Package:" && $2==pkg {in_pkg=1; next}
      in_pkg && $1=="Version:" {print $2; exit}
      in_pkg && $0=="" {in_pkg=0}
    ' "$status_file")"
    if [[ -z "${ver:-}" ]]; then
      warn "${pkg} missing from dpkg status"
      errors=$((errors + 1))
    elif [[ "$ver" == 99:* ]]; then
      warn "${pkg} is still a vendor dummy (${ver})"
      errors=$((errors + 1))
    else
      log "${pkg}: ${ver}"
    fi
  done
fi

if (( errors > 0 )); then
  fail "${errors} check(s) failed — incomplete vendor Mesa / dummy libgbm / broken linkage"
fi

log "PASS — vendor Mesa runtime present, libgbm real, dri_gbm→gallium OK"
exit 0
