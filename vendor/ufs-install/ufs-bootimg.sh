#!/usr/bin/env bash
# MaSi ABL boot/KERNEL helpers for UFS ROCKNIX install.
# SD keeps dual-boot KERNEL (root=UUID=...).
# ROCKNIX always gets root=PARTLABEL=STORAGE (UFS boot must not depend on SD UUID).
set -euo pipefail

UFS_INTERNAL_CMDLINE='clk_ignore_unused pd_ignore_unused quiet rw rootwait root=PARTLABEL=STORAGE rootfstype=ext4 errors=remount-ro mem_sleep_default=deep ufshcd_core.uic_cmd_timeout=3000'

read_bootimg_cmdline() {
    local kernel="$1"
    [[ -f "$kernel" ]] || return 1
    if command -v abootimg >/dev/null 2>&1; then
        abootimg -i "$kernel" 2>/dev/null | sed -n 's/^\* cmdline = //p' | head -1
        return 0
    fi
    strings "$kernel" 2>/dev/null | grep -m1 '^clk_ignore_unused' || return 1
}

# Build ROCKNIX cmdline from an existing KERNEL (keeps suspend/debug extras, forces PARTLABEL root).
build_ufs_rocknix_cmdline() {
    local src="${1:-}"
    local cmdline token
    local -a out=()

    if [[ -n "$src" && -f "$src" ]]; then
        cmdline="$(read_bootimg_cmdline "$src" || true)"
    fi

    if [[ -z "${cmdline:-}" ]]; then
        printf '%s' "$UFS_INTERNAL_CMDLINE"
        return 0
    fi

    for token in $cmdline; do
        case "$token" in
            root=*|rootfstype=*|errors=*|masi.ufsroot=*|masi.sdroot=*|masi.root=*)
                continue
                ;;
            *)
                out+=("$token")
                ;;
        esac
    done

    out+=("root=PARTLABEL=STORAGE" "rootfstype=ext4" "errors=remount-ro")
    printf '%s' "${out[*]}"
}

# Pack KERNEL for ROCKNIX: same zImage/initrd as src, UFS-only cmdline.
install_kernel_for_ufs_rocknix() {
    local src="$1" dst="$2"
    local cmdline work zimage initrd cfg

    command -v abootimg >/dev/null 2>&1 || return 1
    [[ -f "$src" ]] || return 1

    cmdline="$(build_ufs_rocknix_cmdline "$src")"

    work="$(mktemp -d)"
    if ! (
        cd "${work}"
        cp "${src}" bootimg.in
        abootimg -x bootimg.in >/dev/null 2>&1
    ); then
        rm -rf "${work}"
        return 1
    fi

    zimage="${work}/zImage"
    initrd="${work}/initrd.img"
    cfg="${work}/bootimg.cfg"
    if [[ ! -f "${zimage}" || ! -f "${initrd}" || ! -f "${cfg}" ]]; then
        rm -rf "${work}"
        return 1
    fi

    {
        grep -E '^(bootsize|pagesize|kerneladdr|ramdiskaddr|secondaddr|tagsaddr|name) ' "${cfg}"
        printf 'cmdline = %s\n' "${cmdline}"
    } > "${cfg}.new"
    mv -f "${cfg}.new" "${cfg}"

    mkdir -p "$(dirname "${dst}")"
    if ! abootimg --create "${dst}" -f "${cfg}" -k "${zimage}" -r "${initrd}" >/dev/null 2>&1; then
        rm -rf "${work}"
        return 1
    fi
    rm -rf "${work}"
    [[ -s "${dst}" ]]
}

# Legacy alias
patch_kernel_for_internal_boot() {
    local src="$1" dst="$2"
    # Optional third arg (old callers passed cmdline) — ignored; rebuilt from src.
    install_kernel_for_ufs_rocknix "$src" "$dst"
}

# ROCKNIX KERNEL after install: must be PARTLABEL only (not SD UUID).
verify_ufs_rocknix_kernel_cmdline() {
    local kernel="$1" cmdline

    cmdline="$(read_bootimg_cmdline "${kernel}" || true)"
    [[ -n "${cmdline}" ]] || return 1
    [[ "${cmdline}" == *'root=PARTLABEL=STORAGE'* ]] || return 1
    [[ "${cmdline}" != *'root=UUID='* ]] || return 1
    [[ "${cmdline}" != *'masi.ufsroot='* ]] || return 1
}

# Accept dual-boot SD KERNEL or UFS ROCKNIX KERNEL.
verify_internal_kernel_cmdline() {
    local kernel="$1" cmdline

    cmdline="$(read_bootimg_cmdline "${kernel}" || true)"
    [[ -n "${cmdline}" ]] || return 1
    if [[ "${cmdline}" == *'masi.ufsroot=PARTLABEL=STORAGE'* ]]; then
        [[ "${cmdline}" == *'root=UUID='* ]] || return 1
        return 0
    fi
    [[ "${cmdline}" == *'root=PARTLABEL=STORAGE'* ]] || return 1
}

describe_kernel_root() {
    local kernel="$1" cmdline

    cmdline="$(read_bootimg_cmdline "${kernel}" || true)"
    if [[ -z "${cmdline}" ]]; then
        echo "unknown (could not read bootimg cmdline)"
    elif [[ "${cmdline}" == *'root=PARTLABEL=STORAGE'* && "${cmdline}" != *'root=UUID='* ]]; then
        echo "UFS ROCKNIX (root=PARTLABEL=STORAGE)"
    elif [[ "${cmdline}" == *'masi.ufsroot=PARTLABEL=STORAGE'* && "${cmdline}" == *'root=UUID='* ]]; then
        echo "microSD dual-boot (root=UUID + masi.ufsroot)"
    elif [[ "${cmdline}" == *'root=UUID='* ]]; then
        echo "microSD only (legacy — not safe for UFS ROCKNIX)"
    else
        echo "other: ${cmdline}"
    fi
}
