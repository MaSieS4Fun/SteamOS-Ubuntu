#!/usr/bin/env bash
# Probe UFS Android sizing limits for the Easy UFS Installer GUI.
# Prints KEY=value lines.
set -euo pipefail

MIN_ANDROID_GIB=16
RECOMMENDED_ANDROID_GIB=64
BOOT_PART_GIB=2
MIN_LINUX_ROOT_GIB=16

part_by_label() {
  local device=$1 label=$2
  lsblk -rn -o NAME,PARTLABEL "$device" | awk -v l="$label" '$2==l {print "/dev/"$1; exit}'
}

detect_ufs_device() {
  local d
  for d in /dev/sda /dev/sdb /dev/nvme0n1; do
    [[ -b "$d" ]] || continue
    if lsblk -rn -o PARTLABEL "$d" 2>/dev/null | grep -qx userdata; then
      echo "$d"
      return 0
    fi
  done
  # Fallback: first non-mmc disk with userdata
  while read -r name; do
    [[ -n "$name" ]] || continue
    [[ "$name" == mmcblk* ]] && continue
    if lsblk -rn -o PARTLABEL "/dev/${name}" 2>/dev/null | grep -qx userdata; then
      echo "/dev/${name}"
      return 0
    fi
  done < <(lsblk -dn -o NAME)
  return 1
}

DEVICE="$(detect_ufs_device)" || {
  echo "ERROR=No internal UFS disk with userdata partition found"
  exit 1
}

UD_PART="$(part_by_label "$DEVICE" userdata || true)"
[[ -n "$UD_PART" ]] || {
  echo "ERROR=userdata partition missing on ${DEVICE}"
  exit 1
}

UD_NUM="${UD_PART##*[!0-9]}"
# Start/end in MiB via parted
mapfile -t PART_LINE < <(parted -s "$DEVICE" unit MiB print 2>/dev/null | awk -v n="$UD_NUM" '$1==n {print $2,$3; exit}')
[[ ${#PART_LINE[@]} -ge 1 ]] || {
  echo "ERROR=Could not read userdata geometry"
  exit 1
}
# parted prints e.g. 1234MiB
read -r UD_START_RAW UD_END_RAW <<<"${PART_LINE[0]}"
UD_START_MB="${UD_START_RAW%MiB}"
UD_END_MB="${UD_END_RAW%MiB}"
UD_START_MB="${UD_START_MB%.*}"
UD_END_MB="${UD_END_MB%.*}"

DISK_END_RAW="$(parted -s "$DEVICE" unit MiB print 2>/dev/null | awk '/^Disk /{print $3; exit}')"
DISK_END_MB="${DISK_END_RAW%MiB}"
DISK_END_MB="${DISK_END_MB%.*}"

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
echo "DISK_TOTAL_GIB=${DISK_TOTAL_GIB}"
echo "ORIG_ANDROID_GIB=${ORIG_ANDROID_GIB}"
echo "MIN_ANDROID_GIB=${MIN_ANDROID_GIB}"
echo "MAX_ANDROID_GIB=${MAX_ANDROID_GIB}"
echo "RECOMMENDED_ANDROID_GIB=${REC}"
echo "BOOT_PART_GIB=${BOOT_PART_GIB}"
echo "MIN_LINUX_ROOT_GIB=${MIN_LINUX_ROOT_GIB}"
echo "EXISTING_INSTALL=${EXISTING}"
exit 0
