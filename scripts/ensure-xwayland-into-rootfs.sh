#!/usr/bin/env bash
# Ensure /usr/bin/Xwayland exists WITHOUT pulling Ubuntu Mesa (libgbm/dri_gbm).
# apt-get install xwayland depends on libgbm1→mesa-libgallium and overwrites
# vendor Mesa 26.1.6 GBM — Xwayland then SIGSEGV under gamescope.
#
# Strategy: extract only the Xwayland binary (+ xserver-common data) from debs,
# or copy from the build host. Never apt-install the package with deps.
#
# Usage: sudo ./scripts/ensure-xwayland-into-rootfs.sh <rootfs>
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
MESA_VER="${MESA_VER:-26.1.6}"

log() { printf '==> [xwayland] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ "${EUID}" -eq 0 ]] || die "Run as root"

XW="${ROOTFS}/usr/bin/Xwayland"
LIB="${ROOTFS}/usr/lib/aarch64-linux-gnu"

chroot_prep() {
  mkdir -p "${ROOTFS}/dev/pts" "${ROOTFS}/proc" "${ROOTFS}/tmp"
  mountpoint -q "${ROOTFS}/proc" || mount -t proc proc "${ROOTFS}/proc"
  mountpoint -q "${ROOTFS}/dev" || mount --bind /dev "${ROOTFS}/dev"
  mountpoint -q "${ROOTFS}/dev/pts" || mount -t devpts devpts "${ROOTFS}/dev/pts" 2>/dev/null || true
  "${ROOT_DIR}/scripts/inject-chroot-dns.sh" "${ROOTFS}" 2>/dev/null || true
}

chroot_cleanup() {
  umount -l "${ROOTFS}/dev/pts" 2>/dev/null || true
  umount -l "${ROOTFS}/dev" 2>/dev/null || true
  umount -l "${ROOTFS}/proc" 2>/dev/null || true
}

# Remove stock GBM/DRI that apt may have dropped (linked to libgallium-26.0*)
scrub_stock_gbm() {
  local f
  for f in \
    "${LIB}/gbm/dri_gbm.so" \
    "${LIB}/libgbm.so.1.0.0"
  do
    if [[ -f "$f" ]] && readelf -d "$f" 2>/dev/null | grep -q "libgallium-26.0"; then
      log "removing stock Mesa artifact: ${f#"$ROOTFS"}"
      rm -f "$f"
    fi
  done
  # dri_gbm must match vendor gallium
  if [[ -f "${LIB}/gbm/dri_gbm.so" ]] && ! readelf -d "${LIB}/gbm/dri_gbm.so" 2>/dev/null | grep -q "libgallium-${MESA_VER}"; then
    log "removing mismatched dri_gbm.so"
    rm -f "${LIB}/gbm/dri_gbm.so"
  fi
}

restore_vendor_mesa_gbm() {
  local build="${ROOT_DIR}/output/work/mesa-${MESA_VER}"
  if [[ -f "${build}/build.ninja" ]]; then
    log "re-installing vendor Mesa GBM/DRI into rootfs (DESTDIR)"
    DESTDIR="$ROOTFS" meson install -C "$build" --no-rebuild >/dev/null
    return 0
  fi
  log "WARN: no mesa build at ${build} — run: sudo ./scripts/build-vendor-mesa.sh ${ROOTFS}"
  return 1
}

extract_xwayland_deb() {
  chroot_prep
  local tmp
  tmp="$(mktemp -d "${ROOTFS}/tmp/xw-XXXXXX")"
  # path inside chroot
  local ctmp="${tmp#"$ROOTFS"}"
  log "downloading xwayland/xserver-common debs (extract only, no deps)"
  chroot "${ROOTFS}" bash -c "
    set -e
    cd '${ctmp}'
    apt-get update -y >/dev/null || true
    apt-get download xwayland xserver-common
    for deb in ./*.deb; do
      dpkg-deb -x \"\$deb\" ./out
    done
  " || { chroot_cleanup; rm -rf "$tmp"; return 1; }

  if [[ -x "${tmp}/out/usr/bin/Xwayland" ]]; then
    install -D -m 0755 "${tmp}/out/usr/bin/Xwayland" "$XW"
    log "extracted Xwayland from deb"
  fi
  # xkb / server data from xserver-common — safe, no mesa
  if [[ -d "${tmp}/out/usr/lib/xorg" ]]; then
    mkdir -p "${ROOTFS}/usr/lib"
    cp -a "${tmp}/out/usr/lib/xorg" "${ROOTFS}/usr/lib/" 2>/dev/null || true
  fi
  if [[ -d "${tmp}/out/usr/share/X11" ]]; then
    mkdir -p "${ROOTFS}/usr/share"
    cp -a "${tmp}/out/usr/share/X11" "${ROOTFS}/usr/share/" 2>/dev/null || true
  fi
  # Register package without configuring deps (avoids libgbm pull)
  chroot "${ROOTFS}" bash -c "
    cd '${ctmp}'
    dpkg --force-depends --force-conflicts -i xwayland*.deb xserver-common*.deb 2>/dev/null || true
  " || true

  rm -rf "$tmp"
  chroot_cleanup
  [[ -x "$XW" ]]
}

copy_from_host() {
  [[ -x /usr/bin/Xwayland ]] || return 1
  log "staging Xwayland binary from build host"
  install -D -m 0755 /usr/bin/Xwayland "$XW"
  for d in /usr/share/X11/xkb; do
    if [[ -d "$d" && ! -d "${ROOTFS}${d}" ]]; then
      mkdir -p "$(dirname "${ROOTFS}${d}")"
      cp -a "$d" "${ROOTFS}${d}" 2>/dev/null || true
    fi
  done
  return 0
}

verify_gbm_stack() {
  local gbm="${LIB}/libgbm.so.1"
  local dri_gbm="${LIB}/gbm/dri_gbm.so"
  [[ -e "$gbm" ]] || { log "MISSING libgbm.so.1"; return 1; }
  if [[ -f "$dri_gbm" ]] && readelf -d "$dri_gbm" | grep -q "libgallium-26.0"; then
    log "FAIL: dri_gbm still linked to stock gallium 26.0"
    return 1
  fi
  if [[ -f "$dri_gbm" ]] && ! readelf -d "$dri_gbm" | grep -q "libgallium-${MESA_VER}"; then
    log "WARN: dri_gbm.so not linked to libgallium-${MESA_VER}"
  fi
  return 0
}

# --- main ---
scrub_stock_gbm || true

if [[ ! -x "$XW" ]]; then
  log "Xwayland missing — extracting deb (no Mesa deps)"
  extract_xwayland_deb || copy_from_host || true
fi

[[ -x "$XW" ]] || die "Xwayland still missing at ${XW}"

# Always scrub again (extract may have been preceded by a bad apt install)
scrub_stock_gbm || true
if ! verify_gbm_stack; then
  restore_vendor_mesa_gbm || true
  scrub_stock_gbm || true
fi

if ! verify_gbm_stack; then
  die "Vendor Mesa GBM broken after Xwayland install — re-run: sudo ./scripts/build-vendor-mesa.sh ${ROOTFS}"
fi

ldconfig -r "$ROOTFS" 2>/dev/null || true
install -d "${ROOTFS}/usr/share/sm8550-steamos"
{
  echo "xwayland=$(readlink -f "$XW" 2>/dev/null || echo "$XW")"
  readelf -d "${LIB}/gbm/dri_gbm.so" 2>/dev/null | awk '/libgallium/{print "dri_gbm_needs="$NF}' || echo "dri_gbm=missing"
} > "${ROOTFS}/usr/share/sm8550-steamos/xwayland-ok.txt"
log "PASS — Xwayland present; GBM stack not polluted by stock Mesa"
