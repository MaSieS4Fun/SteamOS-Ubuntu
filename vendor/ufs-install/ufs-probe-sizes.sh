#!/usr/bin/env bash
# Probe UFS Android sizing limits for the Easy UFS Installer GUI.
# Prints KEY=value lines.
# Geometry comes from sysfs (512-byte sectors). parted hangs on some UFS LUNs.
set -euo pipefail

# shellcheck source=ufs-disk.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ufs-disk.sh"

MIN_ANDROID_GIB=16
RECOMMENDED_ANDROID_GIB=64
BOOT_PART_GIB=2
MIN_LINUX_ROOT_GIB=16

DEVICE="$(detect_ufs_device)"
[[ -n "$DEVICE" ]] || {
  echo "ERROR=No internal UFS disk with userdata partition found"
  exit 1
}

disk=${DEVICE##*/}
found=0
part_start=0
part_size=0
for part_sysfs in "/sys/block/${disk}/${disk}"*; do
  [[ -d "$part_sysfs" ]] || continue
  [[ -r "${part_sysfs}/uevent" ]] || continue
  part_label=$(awk -F= '$1=="PARTNAME" {print $2; exit}' "${part_sysfs}/uevent")
  [[ "$part_label" == "userdata" ]] || continue
  part_start=$(<"${part_sysfs}/start")
  part_size=$(<"${part_sysfs}/size")
  found=1
  break
done
(( found )) || {
  echo "ERROR=userdata partition missing on ${DEVICE}"
  exit 1
}

# sysfs start/size are 512-byte sectors even when the UFS logical block is 4096.
UD_START_MB=$(( (part_start * 512 + 1048575) / 1048576 ))
UD_END_MB=$(( (part_start * 512 + part_size * 512) / 1048576 ))
disk_sectors=$(<"/sys/block/${disk}/size")
DISK_END_MB=$(( disk_sectors * 512 / 1048576 ))

DISK_TOTAL_GIB=$(( (DISK_END_MB + 1023) / 1024 ))
ORIG_ANDROID_GIB=$(( (UD_END_MB - UD_START_MB + 1023) / 1024 ))
min_linux_reserve_gib=$(( BOOT_PART_GIB + MIN_LINUX_ROOT_GIB ))
MAX_ANDROID_GIB=$(( ORIG_ANDROID_GIB - min_linux_reserve_gib ))
(( MAX_ANDROID_GIB < MIN_ANDROID_GIB )) && MAX_ANDROID_GIB=$MIN_ANDROID_GIB

REC=$RECOMMENDED_ANDROID_GIB
(( REC > MAX_ANDROID_GIB )) && REC=$MAX_ANDROID_GIB
(( REC < MIN_ANDROID_GIB )) && REC=$MIN_ANDROID_GIB

RK="$(part_by_label "$DEVICE" ROCKNIX || true)"
ST="$(part_by_label "$DEVICE" STORAGE || true)"
EXISTING=0
[[ -n "$RK" && -n "$ST" ]] && EXISTING=1

echo "DEVICE=${DEVICE}"
echo "SOC=$(detect_soc_family)"
echo "BOARD=$(read_board_id)"
echo "DISK_TOTAL_GIB=${DISK_TOTAL_GIB}"
echo "ORIG_ANDROID_GIB=${ORIG_ANDROID_GIB}"
echo "MIN_ANDROID_GIB=${MIN_ANDROID_GIB}"
echo "MAX_ANDROID_GIB=${MAX_ANDROID_GIB}"
echo "RECOMMENDED_ANDROID_GIB=${REC}"
echo "BOOT_PART_GIB=${BOOT_PART_GIB}"
echo "MIN_LINUX_ROOT_GIB=${MIN_LINUX_ROOT_GIB}"
echo "EXISTING_INSTALL=${EXISTING}"
exit 0
