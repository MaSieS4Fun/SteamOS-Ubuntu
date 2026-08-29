#!/usr/bin/env bash
# Create GPT disk image for ROCKNIX-ABL / SM8550:
#   p1 VFAT  PARTLABEL=BOOT     → boot/KERNEL (+ extras)
#   p2 ext4  PARTLABEL=STORAGE  → rootfs
#
# Usage:
#   sudo ./scripts/make-disk-image.sh [rootfs] [kernel-build]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT_DIR}/output"
ROOTFS="${1:-${OUT}/rootfs}"
BUILD="${2:-}"
IMG="${IMG:-${OUT}/steamos-ubuntu-resolute-arm64.img}"
IMG_SIZE="${IMG_SIZE:-16G}"
BOOT_SIZE_MIB="${BOOT_SIZE_MIB:-512}"
BOOT_LABEL="${BOOT_LABEL:-BOOT}"
ROOT_LABEL="${ROOT_LABEL:-STORAGE}"
WORKDIR="${OUT}/work/disk"
KERN_ROOT="${ROOT_DIR}/vendor/kernel"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -d "${ROOTFS}/usr" ]] || die "Rootfs not found: ${ROOTFS}"
command -v sgdisk >/dev/null || die "Need gdisk/sgdisk"
command -v mkfs.vfat >/dev/null || die "Need dosfstools"
command -v mkfs.ext4 >/dev/null || die "Need e2fsprogs"
command -v losetup >/dev/null || die "Need losetup"

if [[ -z "$BUILD" ]]; then
  BUILD="$("${ROOT_DIR}/scripts/ensure-kernel.sh")"
fi
BUILD="$(printf '%s\n' "${BUILD}" | awk 'NF{p=$0} END{print p}')"
BUILD="${BUILD%/}"
[[ -f "${BUILD}/boot/KERNEL" ]] || die "Missing ${BUILD}/boot/KERNEL"

# Modules+firmware already expected in rootfs; refresh idempotently
"${ROOT_DIR}/scripts/install-kernel-into-rootfs.sh" "$ROOTFS" "$BUILD"

mkdir -p "$OUT" "$WORKDIR"
BOOT_MNT="${WORKDIR}/boot"
ROOT_MNT="${WORKDIR}/root"
mkdir -p "$BOOT_MNT" "$ROOT_MNT"

cleanup() {
  sync || true
  umount -l "$BOOT_MNT" 2>/dev/null || true
  umount -l "$ROOT_MNT" 2>/dev/null || true
  if [[ -n "${LOOPDEV:-}" ]]; then
    losetup -d "$LOOPDEV" 2>/dev/null || true
  fi
}
trap cleanup EXIT

log "Creating sparse GPT image ${IMG} (${IMG_SIZE})"
rm -f "$IMG"
truncate -s "$IMG_SIZE" "$IMG"

# GPT: p1 boot (ESP/FAT type), p2 linux root with PARTLABEL=STORAGE
sgdisk -Z "$IMG" >/dev/null
sgdisk \
  -n "1:0:+${BOOT_SIZE_MIB}M" -t 1:0700 -c "1:${BOOT_LABEL}" \
  -n "2:0:0" -t 2:8300 -c "2:${ROOT_LABEL}" \
  "$IMG" >/dev/null

LOOPDEV="$(losetup -f --show -P "$IMG")"
# wait for partition nodes
for _ in $(seq 1 50); do
  [[ -b "${LOOPDEV}p1" && -b "${LOOPDEV}p2" ]] && break
  sleep 0.1
done
[[ -b "${LOOPDEV}p1" && -b "${LOOPDEV}p2" ]] || die "Loop partitions not ready on ${LOOPDEV}"

log "Formatting ${LOOPDEV}p1 VFAT (${BOOT_LABEL}) + ${LOOPDEV}p2 ext4 (${ROOT_LABEL})"
mkfs.vfat -F 32 -n "$BOOT_LABEL" "${LOOPDEV}p1" >/dev/null
mkfs.ext4 -F -L "$ROOT_LABEL" "${LOOPDEV}p2" >/dev/null

ROOT_UUID="$(blkid -s UUID -o value "${LOOPDEV}p2")"
BOOT_UUID="$(blkid -s UUID -o value "${LOOPDEV}p1")"
[[ -n "$ROOT_UUID" ]] || die "Could not read root UUID"

log "Root UUID=${ROOT_UUID}  Boot UUID=${BOOT_UUID}"

# Write fstab into rootfs before copy
cat >"${ROOTFS}/etc/fstab" <<EOF
# SteamOS-Ubuntu — GPT PARTLABEL layout (ROCKNIX-ABL)
UUID=${ROOT_UUID}  /      ext4  defaults,noatime  0 1
UUID=${BOOT_UUID}  /boot  vfat  defaults,umask=0022,shortname=winnt  0 2
proc               /proc  proc  defaults          0 0
sysfs              /sys   sysfs defaults          0 0
devtmpfs           /dev   devtmpfs defaults,mode=0755 0 0
tmpfs              /tmp   tmpfs defaults,nosuid,nodev 0 0
EOF

# Stage boot partition contents from vendor kernel build/boot/
STAGE_BOOT="${WORKDIR}/boot-stage"
rm -rf "$STAGE_BOOT"
mkdir -p "$STAGE_BOOT"
rsync -a "${BUILD}/boot/" "$STAGE_BOOT/"
rm -f "${STAGE_BOOT}/LinuxLoader.cfg" 2>/dev/null || true

# Rewrite KERNEL cmdline so this image's root UUID is embedded (not update.sh)
if command -v abootimg >/dev/null; then
  log "Embedding root=UUID=${ROOT_UUID} into boot/KERNEL (unified cmdline, ABL DTB select)"
  (
    export ROOT="$KERN_ROOT"
    export CMDLINE_QUIET="${CMDLINE_QUIET:-1}"
    # shellcheck source=/dev/null
    source "${KERN_ROOT}/config/defaults.conf"
    # shellcheck source=/dev/null
    source "${KERN_ROOT}/lib/cmdline.sh"
    # shellcheck source=/dev/null
    source "${KERN_ROOT}/lib/bootimg.sh"
    export ROOT_UUID="$ROOT_UUID"
    RELEASE="$(basename "$(find "${BUILD}/modules" -mindepth 1 -maxdepth 1 -type d | head -1)")"
    repack_bootimg_local_uuid "${STAGE_BOOT}/KERNEL" "${STAGE_BOOT}/KERNEL" "${RELEASE}" \
      || die "KERNEL cmdline rewrite failed"
    abootimg -i "${STAGE_BOOT}/KERNEL" 2>/dev/null | sed -n 's/^\* cmdline = //p' | head -1 \
      > "${OUT}/boot/cmdline.txt" || true
  )
else
  log "WARN: abootimg missing — copying KERNEL as built (apt install abootimg)"
fi

log "Fixing system ownership before copy (root:root)"
if [[ -x "${ROOT_DIR}/scripts/fix-rootfs-ownership.sh" ]]; then
  "${ROOT_DIR}/scripts/fix-rootfs-ownership.sh" "$ROOTFS"
else
  die "missing scripts/fix-rootfs-ownership.sh"
fi

log "Copying rootfs → ext4 (PARTLABEL=${ROOT_LABEL})"
mount "${LOOPDEV}p2" "$ROOT_MNT"
rsync -aHAX --info=stats2 "$ROOTFS"/ "$ROOT_MNT"/
# Ensure /boot mountpoint exists empty on rootfs (real files live on VFAT)
mkdir -p "${ROOT_MNT}/boot"
# Don't leave a nested KERNEL on ext4 /boot — ABL reads VFAT partition
find "${ROOT_MNT}/boot" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
sync
umount "$ROOT_MNT"

log "Installing build/boot → VFAT (PARTLABEL=${BOOT_LABEL})"
mount "${LOOPDEV}p1" "$BOOT_MNT"
# VFAT cannot chown/chmod — do not use rsync -a (EPERM on ownership).
rsync -rltD --delete "${STAGE_BOOT}/" "$BOOT_MNT/"
sync
ls -lh "${BOOT_MNT}/KERNEL"
umount "$BOOT_MNT"

# Stash copy for reference
install -d "${OUT}/boot"
cp -a "${STAGE_BOOT}/KERNEL" "${OUT}/boot/KERNEL"
echo "$ROOT_UUID" > "${OUT}/boot/root-uuid.txt"
ln -sfn "$BUILD" "${OUT}/kernel-current"

# Done — cleanup trap will detach loop
trap - EXIT
cleanup

cat <<EOF

========================================================================
  Disk image ready (GPT)
------------------------------------------------------------------------
  Image : ${IMG}
  p1    : VFAT  PARTLABEL=${BOOT_LABEL}   (/boot/KERNEL)
  p2    : ext4  PARTLABEL=${ROOT_LABEL}   (rootfs)
  root  : UUID=${ROOT_UUID}
  size  : ${IMG_SIZE} (sparse bake size — not the physical SD)

  After flash, first boot runs steamos-expand-rootfs.service:
    growpart + resize2fs on STORAGE → fills the rest of the card.
    No reboot. Completes before greetd/Steam.

  Flash example:
    sudo dd if=${IMG} of=/dev/sdX bs=4M status=progress conv=fsync

  ABL: Vol Down → Set the Device → Linux → START
========================================================================
EOF
