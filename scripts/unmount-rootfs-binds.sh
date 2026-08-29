#!/usr/bin/env bash
# Unmount chroot helper mounts under a rootfs (proc/sys/dev/run).
# Safe to call repeatedly. Does not remove the directories (empty mountpoints stay).
#
# Usage: unmount-rootfs-binds.sh <rootfs>
set -euo pipefail

ROOTFS="${1:-}"
[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || {
  echo "Usage: $0 <rootfs>" >&2
  exit 1
}
[[ "$ROOTFS" == "/" ]] && {
  echo "Refusing to operate on live /" >&2
  exit 1
}
ROOTFS="$(cd "$ROOTFS" && pwd)"
ROOTFS="${ROOTFS%/}"

# Never touch host mounts: every target must be strictly under ROOTFS/
under_rootfs() {
  local mp="$1"
  [[ "$mp" == "${ROOTFS}/"* ]]
}

umount_mp() {
  local mp="$1"
  under_rootfs "$mp" || return 0
  if mountpoint -q "$mp" 2>/dev/null; then
    umount -l "$mp" 2>/dev/null || umount "$mp" 2>/dev/null || true
  fi
}

# Deepest first (known chroot helpers)
for mp in \
  "${ROOTFS}/dev/pts" \
  "${ROOTFS}/dev/shm" \
  "${ROOTFS}/proc" \
  "${ROOTFS}/sys" \
  "${ROOTFS}/run" \
  "${ROOTFS}/dev"
do
  umount_mp "$mp"
done

# Leftover binds only if their mount TARGET path is under this rootfs
if command -v findmnt >/dev/null 2>&1; then
  mapfile -t leftovers < <(
    findmnt -Rnn -o TARGET --target "$ROOTFS" 2>/dev/null \
      | sed 's/[[:space:]].*//' \
      | grep -E "^${ROOTFS}/" \
      | sort -r
  )
  for mp in "${leftovers[@]:-}"; do
    [[ -n "$mp" ]] || continue
    umount_mp "$mp"
  done
fi
