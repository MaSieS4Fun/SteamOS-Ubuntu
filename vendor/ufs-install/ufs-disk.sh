#!/usr/bin/env bash
# Internal UFS selection for SM8550 and SM8750 handhelds.
#
# The Linux microSD uses PARTLABEL=STORAGE for its rootfs (and the dock
# copy does too). Those labels are not an internal Linux install.
# Only partitions on the non-removable disk that contains Android userdata
# count.

read_board_id() {
  local board="" model
  if [[ -f /etc/armbian-release ]]; then
    board=$(awk -F= '/^BOARD=/{print $2; exit}' /etc/armbian-release)
  fi
  if [[ -n "$board" ]]; then
    echo "$board"
    return
  fi
  if [[ -r /proc/device-tree/model ]]; then
    model=$(tr -d '\0' < /proc/device-tree/model)
    case "$model" in
      *"Odin 3"*) echo ayn-odin3; return ;;
    esac
  fi
  echo ""
}

detect_soc_family() {
  local family="" compat
  if [[ -r /sys/firmware/devicetree/base/compatible ]]; then
    compat=$(tr '\0' '\n' < /sys/firmware/devicetree/base/compatible)
    if grep -Eq 'qcom,sm8750|qcom,cq8725s' <<<"$compat"; then
      echo sm8750
      return
    fi
    if grep -q 'qcom,sm8550' <<<"$compat"; then
      echo sm8550
      return
    fi
  fi
  if [[ -f /etc/armbian-release ]]; then
    family=$(awk -F= '/^BOARDFAMILY=|^LINUXFAMILY=/{print $2; exit}' /etc/armbian-release)
  fi
  echo "$family"
}

soc_is_supported() {
  case "$1" in
    sm8550|SM8550|sm8750|SM8750) return 0 ;;
    *) return 1 ;;
  esac
}

ufs_part_parent() {
  local name=$1
  lsblk -no PKNAME "/dev/${name}" 2>/dev/null || true
}

part_by_label() {
  local device=$1 label=$2 name got parent
  parent=${device##*/}
  while read -r name got; do
    [[ "$got" == "$label" ]] || continue
    [[ "$(ufs_part_parent "$name")" == "$parent" ]] || continue
    echo "/dev/${name}"
    return 0
  done < <(lsblk -rn -o NAME,PARTLABEL "$device" 2>/dev/null)
  return 1
}

disk_tran() {
  lsblk -dn -o TRAN "$1" 2>/dev/null | awk 'NF{print; exit}'
}

running_root_disk() {
  local src pk
  src=$(findmnt -no SOURCE / 2>/dev/null || true)
  [[ -n "$src" ]] || return 0
  pk=$(lsblk -no PKNAME "$src" 2>/dev/null || true)
  printf '%s\n' "$pk"
}

# True for the Android userdata LUN. False for the SD slot, USB/dock
# disks, and the disk that holds the running rootfs.
is_internal_ufs_candidate() {
  local dev=$1 disk tran root removable
  [[ -b "$dev" ]] || return 1
  disk=${dev##*/}
  [[ "$disk" == mmcblk* ]] && return 1
  tran=$(disk_tran "$dev")
  [[ "$tran" == usb || "$tran" == mmc ]] && return 1
  removable=$(cat "/sys/block/${disk}/removable" 2>/dev/null || echo 1)
  [[ "$removable" == 1 ]] && return 1
  root=$(running_root_disk)
  [[ -n "$root" && "$disk" == "$root" ]] && return 1
  lsblk -rn -o PARTLABEL "$dev" 2>/dev/null | grep -qx userdata
}

detect_ufs_device() {
  local dev
  for dev in /dev/sd? /dev/nvme?n1; do
    [[ -b "$dev" ]] || continue
    if is_internal_ufs_candidate "$dev"; then
      echo "$dev"
      return 0
    fi
  done
  echo ""
  return 0
}

# STORAGE/ROCKNIX on the boot SD or a dock card are not an internal install.
note_foreign_linux_labels() {
  local ufs=$1 name label pk
  while read -r name label; do
    [[ "$label" == "ROCKNIX" || "$label" == "STORAGE" ]] || continue
    pk=$(ufs_part_parent "$name")
    [[ "/dev/${pk}" == "$ufs" ]] && continue
    log "Ignoring ${label} on /dev/${name} (disk ${pk:-unknown}). It is not on internal UFS ${ufs}."
  done < <(lsblk -rn -o NAME,PARTLABEL 2>/dev/null)
}
