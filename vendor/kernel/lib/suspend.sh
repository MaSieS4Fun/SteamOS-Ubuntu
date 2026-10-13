#!/usr/bin/env bash
# Userspace hooks for SM8550 deep suspend (systemd). Replaces fake-suspend / keepalive.
set -euo pipefail

# Devices validated for deep suspend in ROCKNIX PR #2954
_suspend_device_allowed() {
    local model compat=""
    if [[ "${SUSPEND_DEEP_ALL:-0}" == "1" ]]; then
        return 0
    fi
    if [[ -r /proc/device-tree/compatible ]]; then
        compat="$(tr '\0' ' ' </proc/device-tree/compatible 2>/dev/null || true)"
    fi
    model="$(cat /sys/firmware/devicetree/base/model 2>/dev/null || true)"
    case "${compat} ${model}" in
        *odin2*|*Odin*2*|*ayn,odin2*|*ayn,odin2mini*|*ayn,odin2portal*|*ayn,thor*|*Thor*|*retroidpocket,rp6*|*RP6*|*Retroid*Pocket*6*)
            return 0
            ;;
    esac
    return 1
}

disable_fake_suspend_and_keepalive() {
    local u
    for u in \
        masi-ufs-gaming-keepalive.service \
        rocknix-fake-suspend.service \
        fake-suspend.service
    do
        if systemctl list-unit-files "${u}" &>/dev/null; then
            systemctl disable --now "${u}" 2>/dev/null || true
            systemctl mask "${u}" 2>/dev/null || true
            echo "  disabled/masked ${u}" >&2
        fi
    done
    rm -f /usr/bin/masi-ufs-gaming-keepalive \
          /usr/lib/systemd/system/masi-ufs-gaming-keepalive.service \
          /etc/systemd/system/masi-ufs-gaming-keepalive.service \
          /etc/systemd/system/masi-ufs-gaming-keepalive.service 2>/dev/null || true
}

install_deep_suspend_config() {
    disable_fake_suspend_and_keepalive

    [[ "${SUSPEND_DEEP:-0}" == "1" ]] || {
        echo "  deep-suspend: SUSPEND_DEEP=0 — userspace not installed" >&2
        return 0
    }

    if ! _suspend_device_allowed; then
        # A shared image may already carry the SM8550 deep drop-in.
        # On SM8750 that drop-in selects deep again after the kernel
        # default, and the power key does not wake the device.
        local id=""
        if [[ -r /proc/device-tree/compatible ]]; then
            id="$(tr '\0' ' ' </proc/device-tree/compatible 2>/dev/null || true)"
        fi
        id="${id} $(cat /sys/firmware/devicetree/base/model 2>/dev/null || true)"
        if [[ "${id}" == *sm8750* || "${id}" == *odin3* || "${id}" == *"Odin 3"* ]]; then
            mkdir -p /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d
            rm -f /etc/systemd/sleep.conf.d/masi-deep-suspend.conf
            install -m644 "${ROOT}/config/sleep/masi-s2idle-suspend.conf" \
                /etc/systemd/sleep.conf.d/masi-s2idle-suspend.conf
            install -m644 "${ROOT}/config/sleep/masi-logind-suspend.conf" \
                /etc/systemd/logind.conf.d/masi-suspend.conf
            if [[ -w /sys/power/mem_sleep ]]; then
                echo s2idle > /sys/power/mem_sleep || true
            fi
            systemctl daemon-reload 2>/dev/null || true
            echo "  suspend: SM8750 uses s2idle (deep does not wake)" >&2
            return 0
        fi
        echo "  deep-suspend: device not in the validated set (Odin2/Mini/Portal/Thor/RP6)" >&2
        echo "  deep-suspend: kernel patches still applied; set SUSPEND_DEEP_ALL=1 to force userspace" >&2
        return 0
    fi

    [[ -d /etc/systemd ]] || {
        echo "  deep-suspend: no systemd — skip sleep.conf.d" >&2
        return 0
    }

    mkdir -p /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d

    install -m644 "${ROOT}/config/sleep/masi-deep-suspend.conf" \
        /etc/systemd/sleep.conf.d/masi-deep-suspend.conf
    install -m644 "${ROOT}/config/sleep/masi-logind-suspend.conf" \
        /etc/systemd/logind.conf.d/masi-suspend.conf

    local hook_src="${ROOT}/../../odin-overlay/usr/lib/systemd/system-sleep/10-sm8550-deep-suspend"
    if [[ ! -f "${hook_src}" ]]; then
        hook_src="${ROOT}/../odin-overlay/usr/lib/systemd/system-sleep/10-sm8550-deep-suspend"
    fi
    if [[ -f "${hook_src}" ]]; then
        install -D -m755 "${hook_src}" \
            /usr/lib/systemd/system-sleep/10-sm8550-deep-suspend
    fi

    systemctl daemon-reload 2>/dev/null || true
    echo "  deep-suspend: systemd sleep + logind (mem / power key) + USB/BT hook" >&2
}
