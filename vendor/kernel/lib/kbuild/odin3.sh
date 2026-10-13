#!/usr/bin/env bash
# AYN Odin 3 (SM8750) inside the existing ABL DTB chain — slot 0.
# The same Image keeps Odin 2 / Portal / Mini / Thor / Pocket 6 on slots 1–6.
set -euo pipefail

apply_odin3_board() {
    local src_dir="$1"
    local qcom="${src_dir}/arch/arm64/boot/dts/qcom"
    local mk="${qcom}/Makefile"
    local src="${ROOT}/patches/masi/odin3"
    local patch_dir="${src}/linux"
    local log="${OUTPUT_DIR}/patch-log-odin3.txt"
    local f base failed=0

    [[ -f "${mk}" && -d "${src}" ]] || {
        echo "ERROR: ODIN3 board files missing (${src})" >&2
        return 1
    }

    for f in cq8725s-ayn-common.dtsi cq8725s-ayn-odin3.dts; do
        cp -f "${src}/${f}" "${qcom}/${f}"
    done
    _ensure_dtb_in_makefile "${mk}" "cq8725s-ayn-odin3.dtb"
    echo "  OK   AYN Odin 3 DTS → ABL slot 0 (cq8725s-ayn-odin3.dtb)" >&2

    mkdir -p "${OUTPUT_DIR}"
    : > "${log}"
    echo "==> Odin 3 driver/SoC patches (SM8750, WCN7860, Adreno 830)" >&2
    shopt -s nullglob
    for f in "${patch_dir}"/*.patch; do
        base="$(basename "${f}")"
        if [[ "${base}" == 0039-wifi-ath12k-add-initial-hardware-definition-for-WCN7.patch ]] \
            && grep -q 'pci_d3cold_disable(pdev)' \
                "${src_dir}/drivers/net/wireless/ath/ath12k/wifi7/pci.c" 2>/dev/null \
            && grep -q 'ATH12K_HW_WCN7860_HW20' \
                "${src_dir}/drivers/net/wireless/ath/ath12k/core.h" 2>/dev/null; then
            echo "  SKIP ${base} (WCN7860 already in tree)" >&2
            continue
        fi
        if patch -p1 --dry-run -R -d "${src_dir}" -f < "${f}" >/dev/null 2>&1; then
            echo "  SKIP ${base}" >&2
            continue
        fi
        if patch -p1 --dry-run -d "${src_dir}" -f < "${f}" >/dev/null 2>&1; then
            if patch -p1 -d "${src_dir}" -f < "${f}" >> "${log}" 2>&1; then
                echo "  OK   ${base}" >&2
            else
                echo "  FAIL ${base}" >&2
                failed=1
            fi
        else
            echo "  FAIL ${base} (see ${log})" >&2
            patch -p1 --dry-run -d "${src_dir}" -f < "${f}" >> "${log}" 2>&1 || true
            failed=1
        fi
    done
    shopt -u nullglob
    [[ "${failed}" -eq 0 ]] || return 1

    # 0039 adds the WCN7860 probe case. The ath12k overlay runs earlier,
    # before that case exists, so the D3cold disable has to land here.
    python3 - "${src_dir}" "${ROOT}/scripts/apply-masi-72-overlays.py" <<'PY'
import importlib.util
import sys
from pathlib import Path

src = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("masi72", sys.argv[2])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
raise SystemExit(0 if mod._wcn7860_stay_powered(src) else 1)
PY

    # PMIH0108 is HAP530. The SM8550 driver rejects that revision and the
    # motor never probes. This file is the ROCKNIX/Qualcomm driver that
    # accepts it, with the same global rumble exports rsinput already calls.
    install -D -m 644 "${src}/haptics/qcom-hv-haptics.c" \
        "${src_dir}/drivers/input/misc/qcom-hv-haptics.c"
    install -D -m 644 "${src}/haptics/qcom_hv_haptics.h" \
        "${src_dir}/include/linux/soc/qcom/qcom_hv_haptics.h"
    echo "  OK   PMIH0108 HAP530 haptics (Odin 3 rumble)" >&2
}

apply_odin3_kconfig() {
    local src_dir="$1" cfg="${src_dir}/.config" sc="${src_dir}/scripts/config" sym
    [[ -f "${cfg}" && -x "${sc}" ]] || return 0

    echo "==> Odin 3 / SM8750 built-in (ABL slot 0; SM8550 config stays)" >&2
    for sym in \
        PINCTRL_SM8750 PINCTRL_SM8650_LPASS_LPI \
        INTERCONNECT_QCOM_SM8750 \
        QCOM_CPUCP_MBOX \
        SM_GCC_8750 SM_GPUCC_8750 SM_DISPCC_8750 \
        SM_CAMCC_8750 SM_VIDEOCC_8750 SM_TCSRCC_8750 \
        SND_SOC_WCD939X SND_SOC_WCD939X_SDW \
        TYPEC_MUX_WCD939X_USBSS \
        PHY_QCOM_M31_EUSB \
        PM_DEBUG DPM_WATCHDOG PSTORE_RAM PSTORE_CONSOLE
    do
        "${sc}" --file "${cfg}" --enable "${sym}" 2>/dev/null || true
    done
    "${sc}" --file "${cfg}" --set-val DPM_WATCHDOG_TIMEOUT 60 2>/dev/null || true
    make -C "${src_dir}" ARCH=arm64 olddefconfig
}

# Optional. The ABL image the tester already boots may already have these blobs.
# A sibling "ODIN3 Kernel/firmware" pack is copied when present.
stage_odin3_firmware() {
    local fw_out="$1"
    local candidate src="" path

    for candidate in \
        "${ODIN3_FIRMWARE_DIR:-}" \
        "${ROOT}/../ODIN3 Kernel/firmware"
    do
        [[ -n "${candidate}" && -d "${candidate}/qcom/sm8750" ]] || continue
        src="${candidate}"
        break
    done

    if [[ -z "${src}" ]]; then
        echo "  NOTE Odin 3 firmware pack not found (set ODIN3_FIRMWARE_DIR)" >&2
        _odin3_ensure_adreno "${fw_out}"
        _odin3_overlay_hdmi_tplg "${fw_out}"
        return 0
    fi

    echo "==> Odin 3 firmware from ${src}" >&2
    for path in qcom/sm8750 qcom/vpu ath12k/WCN7860 qca \
        qcom/gen80000_sqe.fw qcom/gen80000_gmu.bin \
        qcom/gen80000_aqe.fw qcom/gen80000_zap.mbn
    do
        [[ -e "${src}/${path}" ]] || continue
        mkdir -p "${fw_out}/$(dirname "${path}")"
        cp -a "${src}/${path}" "${fw_out}/${path}"
        echo "  + ${path}" >&2
    done
    _odin3_ensure_adreno "${fw_out}"
    _odin3_overlay_hdmi_tplg "${fw_out}"
    return 0
}

# The firmware pack's SM8750-AYN-tplg.bin has no HDMI PCM. ALSA then only
# offers Off and Pro Audio. The topology with MultiMedia4 lives with the UCM.
_odin3_overlay_hdmi_tplg() {
    local fw_out="$1"
    local src="${ROOT}/../audio/ODIN3/firmware/qcom/sm8750/SM8750-AYN-tplg.bin"
    [[ -f "$src" ]] || return 0
    mkdir -p "${fw_out}/qcom/sm8750"
    cp -f "$src" "${fw_out}/qcom/sm8750/SM8750-AYN-tplg.bin"
    echo "  + qcom/sm8750/SM8750-AYN-tplg.bin (HDMI MultiMedia4)" >&2
}

# Turnip reads the GPU ID only after the GMU firmware loads. SQE alone is not enough.
_odin3_ensure_adreno() {
    local fw_out="$1" name src
    for name in gen80000_sqe.fw gen80000_gmu.bin gen80000_aqe.fw; do
        [[ -f "${fw_out}/qcom/${name}" ]] && continue
        for src in \
            "${CACHE_DIR:-${ROOT}/.cache}/firmware-armbian/qcom/${name}" \
            "${ROOT}/../ODIN3 Kernel/firmware/qcom/${name}"
        do
            [[ -f "${src}" ]] || continue
            mkdir -p "${fw_out}/qcom"
            cp -f "${src}" "${fw_out}/qcom/${name}"
            echo "  + qcom/${name} (Adreno 830)" >&2
            break
        done
        [[ -f "${fw_out}/qcom/${name}" ]] || \
            echo "  NOTE missing qcom/${name} — Adreno 830 stays down" >&2
    done
}

stage_odin3_ucm() {
    local out_dir="$1"
    local src="${ROOT}/payload/odin3-ucm"
    [[ -d "${src}" ]] || return 0
    rm -rf "${out_dir}/ucm"
    mkdir -p "${out_dir}/ucm"
    cp -a "${src}/." "${out_dir}/ucm/"
    echo "  OK   ucm/ (Odin 3 speakers + HDMI) → copy to /usr/share/alsa/ucm2/" >&2
}
