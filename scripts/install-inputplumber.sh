#!/usr/bin/env bash
# Install ShadowBlip InputPlumber + SM8550 handheld CompositeDevices / capability maps.
# Covers AYN Odin 2/3/Thor, Retroid Pocket 6, AYANEO Pocket (SM8550).
#
# Live system:
#   sudo ./scripts/install-inputplumber.sh
#   sudo ./scripts/install-inputplumber.sh /
# Mounted / bake rootfs:
#   sudo ./scripts/install-inputplumber.sh /path/to/rootfs
#
# Optional:
#   INPUTPLUMBER_VERSION=0.78.1   # pin release (default: latest arm64.deb from GitHub)
#   INPUTPLUMBER_DEB=/path/to.deb # use a local .deb instead of downloading
set -euo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${_HERE}/.." && pwd)"
ROOTFS="${1:-/}"
VENDOR_DIR="${ROOT_DIR}/vendor/InputPlumber"
IP_CONF_SRC="${ROOT_DIR}/system_files/etc/inputplumber"
REPO="ShadowBlip/InputPlumber"

log() { printf '==> [inputplumber] %s\n' "$*"; }
warn() { printf '==> [inputplumber] WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -d "${IP_CONF_SRC}/devices.d" ]] || die "Missing ${IP_CONF_SRC}/devices.d"
[[ -f "${IP_CONF_SRC}/capability_maps.d/ayn_mcu.yaml" ]] || die "Missing ayn_mcu.yaml"

if [[ "$ROOTFS" != "/" ]]; then
  ROOTFS="${ROOTFS%/}"
  [[ -d "${ROOTFS}/usr" ]] || die "Not a rootfs: ${ROOTFS}"
fi

path() {
  local p="$1"
  if [[ "$ROOTFS" == "/" ]]; then
    printf '%s\n' "$p"
  else
    printf '%s%s\n' "$ROOTFS" "$p"
  fi
}

arch="$(uname -m)"
case "$arch" in
  aarch64|arm64) DEB_ARCH="arm64" ;;
  x86_64|amd64)  DEB_ARCH="amd64" ;;
  *) die "Unsupported arch: ${arch}" ;;
esac

need_binds=0
resolv_bak=""
ensure_binds() {
  [[ "$ROOTFS" != "/" ]] || return 0
  mountpoint -q "${ROOTFS}/proc" || { mount -t proc proc "${ROOTFS}/proc"; need_binds=1; }
  mountpoint -q "${ROOTFS}/sys" || { mount -t sysfs sysfs "${ROOTFS}/sys"; need_binds=1; }
  mountpoint -q "${ROOTFS}/dev" || { mount --bind /dev "${ROOTFS}/dev"; need_binds=1; }
  # Bake rootfs often has resolv.conf → NetworkManager (dangling in chroot).
  if [[ -x "${ROOT_DIR}/scripts/inject-chroot-dns.sh" ]]; then
    resolv_bak="${ROOTFS}/etc/resolv.conf.bak.inputplumber"
    if [[ ! -e "$resolv_bak" ]]; then
      cp -a "${ROOTFS}/etc/resolv.conf" "$resolv_bak" 2>/dev/null || true
    fi
    "${ROOT_DIR}/scripts/inject-chroot-dns.sh" "$ROOTFS" 2>/dev/null || true
  fi
}

cleanup_binds() {
  # Restore device-facing resolv.conf (NM symlink) after bake apt work
  if [[ -n "$resolv_bak" && -e "$resolv_bak" ]]; then
    rm -f "${ROOTFS}/etc/resolv.conf"
    mv -f "$resolv_bak" "${ROOTFS}/etc/resolv.conf" 2>/dev/null \
      || ln -sfn ../run/NetworkManager/resolv.conf "${ROOTFS}/etc/resolv.conf"
  elif [[ "$ROOTFS" != "/" ]]; then
    # Prefer NM-managed DNS on the handheld image
    rm -f "${ROOTFS}/etc/resolv.conf"
    ln -sfn ../run/NetworkManager/resolv.conf "${ROOTFS}/etc/resolv.conf" 2>/dev/null || true
  fi
  [[ "$need_binds" -eq 1 ]] || return 0
  if [[ -x "${ROOT_DIR}/scripts/unmount-rootfs-binds.sh" ]]; then
    "${ROOT_DIR}/scripts/unmount-rootfs-binds.sh" "$ROOTFS" 2>/dev/null || true
  else
    umount -l "${ROOTFS}/dev" "${ROOTFS}/sys" "${ROOTFS}/proc" 2>/dev/null || true
  fi
}

pkg_configured() {
  local pkg="$1"
  if [[ "$ROOTFS" == "/" ]]; then
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'
  else
    chroot "$ROOTFS" dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'
  fi
}

resolve_deb_url() {
  local ver="${INPUTPLUMBER_VERSION:-}"
  if [[ -n "$ver" ]]; then
    ver="${ver#v}"
    printf 'https://github.com/%s/releases/download/v%s/inputplumber_%s-1_%s.deb\n' \
      "$REPO" "$ver" "$ver" "$DEB_ARCH"
    return 0
  fi
  local api="https://api.github.com/repos/${REPO}/releases/latest"
  local url
  url="$(curl -fsSL "$api" | DEB_ARCH="$DEB_ARCH" python3 -c "
import json, os, sys
rel = json.load(sys.stdin)
suffix = '_' + os.environ['DEB_ARCH'] + '.deb'
for a in rel.get('assets', []):
    n = a.get('name', '')
    if n.startswith('inputplumber_') and n.endswith(suffix) and '.sha256' not in n:
        print(a['browser_download_url'])
        break
else:
    sys.exit(1)
" 2>/dev/null)" || true
  if [[ -z "${url:-}" ]]; then
    ver="0.78.1"
    warn "GitHub API unavailable — falling back to v${ver}"
    printf 'https://github.com/%s/releases/download/v%s/inputplumber_%s-1_%s.deb\n' \
      "$REPO" "$ver" "$ver" "$DEB_ARCH"
    return 0
  fi
  printf '%s\n' "$url"
}

stage="$(mktemp -d)"
cleanup_stage() { rm -rf "$stage"; cleanup_binds; }
trap cleanup_stage EXIT

DEB_FILE=""
if [[ -n "${INPUTPLUMBER_DEB:-}" ]]; then
  [[ -f "$INPUTPLUMBER_DEB" ]] || die "INPUTPLUMBER_DEB not found: ${INPUTPLUMBER_DEB}"
  DEB_FILE="$INPUTPLUMBER_DEB"
elif [[ -d "$VENDOR_DIR" ]]; then
  shopt -s nullglob
  cached=("${VENDOR_DIR}"/inputplumber_*_"${DEB_ARCH}".deb)
  shopt -u nullglob
  if [[ ${#cached[@]} -gt 0 ]]; then
    DEB_FILE="${cached[-1]}"
    log "Using vendor deb: ${DEB_FILE}"
  fi
fi

if [[ -z "$DEB_FILE" ]]; then
  url="$(resolve_deb_url)"
  DEB_FILE="${stage}/inputplumber.deb"
  log "Downloading ${url}"
  curl -fsSL -o "$DEB_FILE" "$url" || die "Download failed (need network)"
  # Cache for offline / DNS-flaky rebakes
  mkdir -p "$VENDOR_DIR"
  cache_name="$(basename "$url")"
  [[ "$cache_name" == *.deb ]] || cache_name="inputplumber_${INPUTPLUMBER_VERSION:-0.78.1}-1_${DEB_ARCH}.deb"
  cp -a "$DEB_FILE" "${VENDOR_DIR}/${cache_name}"
  log "Cached ${VENDOR_DIR}/${cache_name}"
fi

log "Installing runtime deps (libevdev / libiio)"
if [[ "$ROOTFS" == "/" ]]; then
  apt-get update -y 2>/dev/null || true
  apt-get install -y --no-install-recommends \
    libevdev2 libiio0 libiio-utils \
    || apt-get install -y --no-install-recommends libevdev2 libiio0 \
    || true
else
  ensure_binds
  chroot "$ROOTFS" apt-get update -y 2>/dev/null || true
  chroot "$ROOTFS" apt-get install -y --no-install-recommends \
    libevdev2 libiio0 libiio-utils \
    || chroot "$ROOTFS" apt-get install -y --no-install-recommends libevdev2 libiio0 \
    || true
fi

log "Installing InputPlumber deb"
if [[ "$ROOTFS" == "/" ]]; then
  dpkg -i "$DEB_FILE" || apt-get -y -f install
else
  mkdir -p "${ROOTFS}/tmp/inputplumber"
  cp -a "$DEB_FILE" "${ROOTFS}/tmp/inputplumber/inputplumber.deb"
  ensure_binds
  chroot "$ROOTFS" bash -c 'dpkg -i /tmp/inputplumber/inputplumber.deb || apt-get -y -f install'
  rm -rf "${ROOTFS}/tmp/inputplumber"
fi

[[ -x "$(path /usr/bin/inputplumber)" ]] || die "inputplumber binary missing after install"
pkg_configured inputplumber || die "inputplumber package not fully configured (missing deps? libiio0)"
pkg_configured libiio0 || warn "libiio0 not marked installed — InputPlumber may fail at runtime"

log "Install SM8550 device layouts + capability maps"
install -d "$(path /etc/inputplumber/devices.d)" \
  "$(path /etc/inputplumber/capability_maps.d)" \
  "$(path /usr/share/inputplumber/capability_maps)"
for _map in "${IP_CONF_SRC}/capability_maps.d/"*.yaml; do
  [[ -f "$_map" ]] || continue
  install -m 0644 "$_map" "$(path /etc/inputplumber/capability_maps.d/$(basename "$_map"))"
  install -m 0644 "$_map" "$(path /usr/share/inputplumber/capability_maps/$(basename "$_map"))"
done
for _dev in "${IP_CONF_SRC}/devices.d/"*.yaml; do
  [[ -f "$_dev" ]] || continue
  # Never install optional IMU overlays from devices.d (name sorts before gamepad-only).
  case "$(basename "$_dev")" in
    *+imu*) continue ;;
  esac
  install -m 0644 "$_dev" "$(path /etc/inputplumber/devices.d/$(basename "$_dev"))"
done
# Purge leftover IMU composites from earlier broken installs
rm -f "$(path /etc/inputplumber/devices.d/50-ayn_odin2.yaml)" \
  "$(path /etc/inputplumber/devices.d/02-ayn-controller+imu.yaml)" \
  "$(path /usr/share/inputplumber/devices.d/02-ayn-controller+imu.yaml)"

# Order InputPlumber after qcom-motion when the IMU composite is the default.
MM_DROPIN_SRC="${ROOT_DIR}/system_files/etc/systemd/system/inputplumber.service.d/masi-motion.conf"
install_masi_dropin() {
  local dest_dir
  dest_dir="$(path /etc/systemd/system/inputplumber.service.d)"
  [[ -f "$MM_DROPIN_SRC" ]] || return 0
  install -d "$dest_dir"
  install -m 0644 "$MM_DROPIN_SRC" "${dest_dir}/masi-motion.conf"
}

log "Enable inputplumber.service"
if [[ "$ROOTFS" == "/" ]]; then
  # Legacy giroscopio/qcom-deck-pad installs masked InputPlumber — undo that.
  if systemctl is-enabled inputplumber.service 2>&1 | grep -qi masked; then
    log "Unmasking inputplumber.service (legacy deck-pad stack)"
    systemctl unmask inputplumber.service
  fi
  install_masi_dropin
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable inputplumber.service
  systemctl restart inputplumber.service || systemctl start inputplumber.service
  sleep 1
  if systemctl is-active --quiet inputplumber.service; then
    log "inputplumber.service is active"
  else
    warn "inputplumber.service failed to start — check: journalctl -u inputplumber -b"
    systemctl status inputplumber.service --no-pager -l 2>/dev/null || true
  fi
else
  rm -f "${ROOTFS}/etc/systemd/system/inputplumber.service"
  # Keep / recreate drop-in (do not wipe masi-motion ordering).
  rm -f "${ROOTFS}/etc/systemd/system/inputplumber.service.d/"*.conf 2>/dev/null || true
  install_masi_dropin
  mkdir -p "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
  ln -sfn /usr/lib/systemd/system/inputplumber.service \
    "${ROOTFS}/etc/systemd/system/multi-user.target.wants/inputplumber.service"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --root="$ROOTFS" enable inputplumber.service 2>/dev/null || true
  fi
fi

install -d "$(path /usr/share/sm8550-steamos)"
{
  date -Iseconds
  echo "inputplumber=installed"
  echo "maps=ayn_mcu,imu_generic,ayaneo_mcu_xbox,ayaneo_mcu_japanese,ayaneo_mcu_xbox_standard"
  echo "devices=ayn,ayaneo,retroid_pocket_6"
} >"$(path /usr/share/sm8550-steamos/inputplumber-ok.txt)"

log "Done"
log "  Config:  $(path /etc/inputplumber/)"
log "  Maps:    ayn_mcu + imu_generic + ayaneo_mcu_*"
log "  Devices: AYN (gamepad+IMU default) / Retroid / AYANEO"
log "  Drop-in:  inputplumber.service.d/masi-motion.conf"
log "  Verify:  inputplumber devices list"
