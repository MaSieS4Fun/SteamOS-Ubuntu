#!/usr/bin/env bash
# Rebuild a NEW disk image from a backup .img (does NOT touch a flashed SD).
# Applies current finalize: root ownership, Mesa blockers, no BOX64 binary bake.
#
# Usage:
#   sudo ./scripts/rebuild-image-from-backup.sh /path/to/backup.img
#
# Pass the backup path explicitly. Do not rely on files outside this project
# unless you choose them. Output: output/steamos-ubuntu-resolute-arm64.img
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT_DIR}/output"
ROOTFS="${OUT}/rootfs"
# Backup must be passed explicitly (do not probe outside this project tree).
BACKUP="${1:-}"

log() { printf '==> [from-backup] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -n "$BACKUP" ]] || die "Usage: $0 /path/to/backup.img  (pass the image path explicitly)"
[[ -f "$BACKUP" ]] || die "Backup image not found: $BACKUP"
[[ -x "${ROOT_DIR}/scripts/finalize-handheld-rootfs.sh" ]] || die "missing finalize"
[[ -x "${ROOT_DIR}/scripts/make-disk-image.sh" ]] || die "missing make-disk-image"

chmod +x "${ROOT_DIR}/scripts/"*.sh

MNT_BOOT="$(mktemp -d /tmp/steamos-bak-boot.XXXXXX)"
MNT_ROOT="$(mktemp -d /tmp/steamos-bak-root.XXXXXX)"
LOOP=""

cleanup() {
  set +e
  if [[ -n "$LOOP" ]]; then
    umount "${MNT_BOOT}" 2>/dev/null
    umount "${MNT_ROOT}" 2>/dev/null
    losetup -d "$LOOP" 2>/dev/null
  fi
  rmdir "${MNT_BOOT}" "${MNT_ROOT}" 2>/dev/null
}
trap cleanup EXIT

log "Backup source (read-only): $BACKUP"
log "Attaching loop device…"
LOOP="$(losetup -fP --show "$BACKUP")"
# Prefer PARTLABEL=STORAGE; fall back to p2
ROOT_PART=""
BOOT_PART=""
for p in "${LOOP}p2" "${LOOP}p1" "${LOOP}p3"; do
  [[ -b "$p" ]] || continue
  lbl="$(blkid -o value -s LABEL "$p" 2>/dev/null || true)"
  case "$lbl" in
    STORAGE|storage) ROOT_PART="$p" ;;
    BOOT|boot) BOOT_PART="$p" ;;
  esac
done
[[ -n "$ROOT_PART" ]] || ROOT_PART="${LOOP}p2"
[[ -n "$BOOT_PART" ]] || BOOT_PART="${LOOP}p1"
[[ -b "$ROOT_PART" ]] || die "No STORAGE partition on $BACKUP"

log "Mounting $ROOT_PART (ro)…"
mount -o ro "$ROOT_PART" "$MNT_ROOT"
[[ -d "${MNT_ROOT}/usr" ]] || die "Backup rootfs has no /usr"

log "Copying rootfs → ${ROOTFS} (this takes a while)…"
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"
rsync -aHAX --info=progress2 "$MNT_ROOT"/ "$ROOTFS"/
umount "$MNT_ROOT"

# Drop any baked box64 binary from the backup; keep update-box64 + install-fexemu scripts only
log "Ensuring BOX64 binary is NOT present (script-only policy)"
rm -f \
  "${ROOTFS}/usr/local/bin/box64" \
  "${ROOTFS}/usr/local/bin/box64-bash" \
  "${ROOTFS}/usr/local/bin/box64-python" \
  "${ROOTFS}/usr/local/bin/box64-configurator" \
  "${ROOTFS}/etc/binfmt.d/box64.conf" \
  "${ROOTFS}/usr/lib/binfmt.d/box64.conf" \
  "${ROOTFS}/usr/share/applications/box64-configurator.desktop" \
  "${ROOTFS}/usr/local/share/applications/box64-configurator.desktop" \
  2>/dev/null || true
rm -rf "${ROOTFS}/usr/lib/box64-x86_64-linux-gnu" 2>/dev/null || true
# Keep /usr/bin/update-box64 if present; re-install ARM-Manager scripts (no compile)
if [[ -x "${ROOT_DIR}/scripts/install-vendor-arm-manager.sh" ]]; then
  log "Refreshing ARM-Manager (includes update-box64 script, no binary)"
  "${ROOT_DIR}/scripts/install-vendor-arm-manager.sh" "$ROOTFS" || true
fi

log "Finalize (ownership + Mesa blockers + session defaults)…"
"${ROOT_DIR}/scripts/finalize-handheld-rootfs.sh" "$ROOTFS"

log "Ensuring kernel tree for disk image…"
export KERNEL_VER="${KERNEL_VER:-7.0.14}"
export UI="${UI:-plain}"
KERN_BUILD="$("${ROOT_DIR}/scripts/ensure-kernel.sh")"
KERN_BUILD="$(printf '%s\n' "${KERN_BUILD}" | awk 'NF{p=$0} END{print p}')"
[[ -f "${KERN_BUILD}/boot/KERNEL" ]] || die "kernel tree missing: ${KERN_BUILD}"

log "Creating NEW GPT image (will not write to SD)…"
"${ROOT_DIR}/scripts/make-disk-image.sh" "$ROOTFS" "$KERN_BUILD"

IMG="${OUT}/steamos-ubuntu-resolute-arm64.img"
[[ -f "$IMG" ]] || die "Image not produced"
log "DONE: $IMG"
ls -lh "$IMG"
cat <<EOF

Flash this NEW image to a card when ready (example):
  sudo dd if=${IMG} of=/dev/sdX bs=4M status=progress conv=fsync

Source backup was not modified: ${BACKUP}
EOF
