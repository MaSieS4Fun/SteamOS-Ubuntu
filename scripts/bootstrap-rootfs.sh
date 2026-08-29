#!/usr/bin/env bash
# Bootstrap Ubuntu Resolute rootfs with debootstrap (no podman/docker).
# Called by ../create-image.sh as root.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT_DIR}/output"
ROOTFS="${ROOTFS:-${OUT}/rootfs}"
SUITE="${SUITE:-resolute}"
ARCH="${ARCH:-arm64}"
MIRROR="${MIRROR:-http://ports.ubuntu.com/ubuntu-ports}"
COMPONENTS="${COMPONENTS:-main,restricted,universe,multiverse}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"

command -v debootstrap >/dev/null || die "debootstrap not installed (apt install debootstrap)"

# debootstrap needs a suite script; Ubuntu suites symlink to gutsy
DEB_SCRIPTS="$(dirname "$(readlink -f "$(command -v debootstrap)" 2>/dev/null || echo /usr/sbin/debootstrap)")"
# usual path
SCRIPT_DIR="/usr/share/debootstrap/scripts"
if [[ ! -e "${SCRIPT_DIR}/${SUITE}" ]]; then
  if [[ -e "${SCRIPT_DIR}/gutsy" ]]; then
    log "Creating temporary debootstrap script link for ${SUITE}"
    ln -sfn gutsy "${SCRIPT_DIR}/${SUITE}"
  else
    die "No debootstrap script for ${SUITE} and gutsy missing"
  fi
fi

mkdir -p "$OUT"
if [[ -d "$ROOTFS" ]]; then
  log "Removing previous rootfs ${ROOTFS}"
  rm -rf "$ROOTFS"
fi
mkdir -p "$ROOTFS"

log "debootstrap ${SUITE} (${ARCH}) from ${MIRROR}"
debootstrap \
  --arch="$ARCH" \
  --components="$COMPONENTS" \
  --variant=minbase \
  --include=sudo,systemd,systemd-sysv,dbus,ca-certificates,curl,wget,locales \
  "$SUITE" \
  "$ROOTFS" \
  "$MIRROR"

# Apt sources for Resolute pockets
cat >"${ROOTFS}/etc/apt/sources.list" <<EOF
deb ${MIRROR} ${SUITE} ${COMPONENTS//,/ }
deb ${MIRROR} ${SUITE}-updates ${COMPONENTS//,/ }
deb ${MIRROR} ${SUITE}-security ${COMPONENTS//,/ }
deb ${MIRROR} ${SUITE}-backports ${COMPONENTS//,/ }
EOF

# Bind mounts for chroot package install
mount --bind /dev "${ROOTFS}/dev"
mount --bind /dev/pts "${ROOTFS}/dev/pts"
mount -t proc proc "${ROOTFS}/proc"
mount -t sysfs sysfs "${ROOTFS}/sys"
mount -t tmpfs tmpfs "${ROOTFS}/run"
mkdir -p "${ROOTFS}/run/lock"

cleanup() {
  umount -l "${ROOTFS}/dev/pts" 2>/dev/null || true
  umount -l "${ROOTFS}/dev" 2>/dev/null || true
  umount -l "${ROOTFS}/proc" 2>/dev/null || true
  umount -l "${ROOTFS}/sys" 2>/dev/null || true
  umount -l "${ROOTFS}/run" 2>/dev/null || true
}
trap cleanup EXIT

# Copy package lists + build scripts into chroot
install -d "${ROOTFS}/tmp/packages" "${ROOTFS}/tmp/build_files"
cp -a "${ROOT_DIR}/packages/." "${ROOTFS}/tmp/packages/"
cp -a "${ROOT_DIR}/build_files/." "${ROOTFS}/tmp/build_files/"
chmod +x "${ROOTFS}/tmp/build_files/"*.sh

# Overlay system_files (Mesa apt pin is NOT here — applied later by build-vendor-mesa)
log "Applying system_files overlay"
cp -a "${ROOT_DIR}/system_files/." "${ROOTFS}/"
# Belt-and-suspenders: never pin Mesa before package install
rm -f "${ROOTFS}/etc/apt/preferences.d/99-block-ubuntu-mesa"

# DNS for apt inside chroot (real upstream NS — not 127.0.0.53 stub)
"${ROOT_DIR}/scripts/inject-chroot-dns.sh" "$ROOTFS"

log "Installing package sets inside chroot"
chroot "$ROOTFS" /bin/bash -c '
  set -euo pipefail
  export DEBIAN_FRONTEND=noninteractive
  export STEAM_USER=steam STEAM_PASS=steam
  apt-get update -y
  /tmp/build_files/00-install-packages.sh
  /tmp/build_files/05-purge-distro-firmware.sh
  /tmp/build_files/10-create-steam-user.sh
  /tmp/build_files/20-enable-services.sh
  /tmp/build_files/25-disable-snap.sh
  /tmp/build_files/30-brave-and-mozilla-repos.sh
  /tmp/build_files/40-desktop-polish.sh
  /tmp/build_files/99-cleanup.sh
  rm -rf /tmp/packages /tmp/build_files
'

export KERNEL_VER="${KERNEL_VER:-7.0.14}"
export UI="${UI:-plain}"
log "Integrating kernel (modules + firmware) KERNEL_VER=${KERNEL_VER}"
KERN_BUILD="$("${ROOT_DIR}/scripts/ensure-kernel.sh")"
KERN_BUILD="$(printf '%s\n' "${KERN_BUILD}" | awk 'NF{p=$0} END{print p}')"
[[ -f "${KERN_BUILD}/boot/KERNEL" ]] || die "ensure-kernel returned invalid tree: ${KERN_BUILD}"
"${ROOT_DIR}/scripts/install-kernel-into-rootfs.sh" "$ROOTFS" "$KERN_BUILD"

if [[ "${SKIP_AUDIO:-0}" == "1" ]]; then
  log "SKIP_AUDIO=1 — skipping vendor/audio"
else
  log "Installing vendor audio"
  "${ROOT_DIR}/vendor/audio/scripts/install-into-rootfs.sh" "$ROOTFS"
fi

log "Staging SteamARM"
install -d "${ROOTFS}/usr/share/sm8550-steamos/steam-arm"
cp -a "${ROOT_DIR}/vendor/SteamARM/." "${ROOTFS}/usr/share/sm8550-steamos/steam-arm/"
chmod +x "${ROOTFS}/usr/share/sm8550-steamos/steam-arm/install-steam-arm"
ln -sfn /usr/share/sm8550-steamos/steam-arm/install-steam-arm \
  "${ROOTFS}/usr/local/bin/install-steam-arm"

# Full vendor userspace (same as OCI path) — compile mesa/gamescope/mangohud/steam
log "Building vendor userspace stack (mesa → gamescope → mangohud → steam)"
"${ROOT_DIR}/scripts/build-vendor-stack.sh" "$ROOTFS"

log "Ensuring Xwayland (gamescope → Steam)"
"${ROOT_DIR}/scripts/ensure-xwayland-into-rootfs.sh" "$ROOTFS"

# Refresh session wrappers after vendor installs
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/bin/gamescope-session" \
  "${ROOTFS}/usr/bin/gamescope-session"
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/local/bin/steamos-greetd-session" \
  "${ROOTFS}/usr/local/bin/steamos-greetd-session"

chmod +x \
  "${ROOTFS}/usr/bin/gamescope-session" \
  "${ROOTFS}/usr/bin/steamos-session-select" \
  "${ROOTFS}/usr/bin/steamos-desktop-to-gamescope" \
  "${ROOTFS}/usr/bin/steamos-desktop-gamescope" \
  "${ROOTFS}/usr/local/bin/steamos-greetd-session" 2>/dev/null || true

install -d "${ROOTFS}/var/lib/steamos-ubuntu"
echo gamescope-session > "${ROOTFS}/var/lib/steamos-ubuntu/session"

echo steamos-ubuntu > "${ROOTFS}/etc/hostname"
# Debian/Ubuntu: /etc/os-release → ../usr/lib/os-release
# BUILD_ID fills Steam sOSBuildId. Do NOT set VARIANT_ID=steamdeck (forces beta
# OS branch + update-check dialog on every Gaming Mode login).
install -d "${ROOTFS}/usr/lib"
cat >"${ROOTFS}/usr/lib/os-release" <<'EOF'
PRETTY_NAME="SteamOS-Ubuntu Resolute"
NAME="SteamOS-Ubuntu"
VERSION_ID="26.04"
VERSION="26.04 (Resolute)"
VERSION_CODENAME=resolute
ID=steamos-ubuntu
ID_LIKE="ubuntu debian"
HOME_URL="https://github.com/local/SteamOS-Ubuntu"
UBUNTU_CODENAME=resolute
BUILD_ID=20260825.1
EOF
ln -sfn ../usr/lib/os-release "${ROOTFS}/etc/os-release"

truncate -s 0 "${ROOTFS}/etc/machine-id" 2>/dev/null || true
rm -f "${ROOTFS}/var/lib/dbus/machine-id" 2>/dev/null || true

log "Finalize handheld defaults (Deck mode, MangoHud steam, boot trim)"
"${ROOT_DIR}/scripts/finalize-handheld-rootfs.sh" "$ROOTFS"

# Drop mounts before packing
cleanup
trap - EXIT

log "Packing ${OUT}/steamos-ubuntu-resolute-arm64.tar.gz"
tar -C "$ROOTFS" -cf - . | gzip -1 > "${OUT}/steamos-ubuntu-resolute-arm64.tar.gz"

if [[ "${SKIP_IMG:-0}" == "1" ]]; then
  log "Skipping .img (--rootfs-only)"
else
  log "Creating GPT disk image (VFAT BOOT + ext4 STORAGE)"
  "${ROOT_DIR}/scripts/make-disk-image.sh" "$ROOTFS" "$KERN_BUILD"
fi

cat <<EOF

========================================================================
  SteamOS-Ubuntu image ready (debootstrap)
------------------------------------------------------------------------
  Rootfs : ${ROOTFS}
  Tarball: ${OUT}/steamos-ubuntu-resolute-arm64.tar.gz
  Image  : ${OUT}/steamos-ubuntu-resolute-arm64.img
           p1 VFAT BOOT | p2 ext4 STORAGE
  Kernel : ${KERN_BUILD}
  User   : steam / steam
========================================================================
EOF
