# --- paste into scripts/40-customize-image.sh (sm8550-resolute) ---
# Vendor drop-in: AYN Odin2 ALSA UCM + ADSP firmware (vendor/audio)
AUDIO_VENDOR="${PROJECT_ROOT}/vendor/audio"
if [[ -d "${AUDIO_VENDOR}/ucm2" ]]; then
    log "  Installing AYN Odin2/Thor ALSA UCM + firmware (vendor/audio)"
    mkdir -p "${mnt}/usr/share/alsa/ucm2" "${mnt}/lib/firmware"
    cp -a "${AUDIO_VENDOR}/ucm2/." "${mnt}/usr/share/alsa/ucm2/"
    cp -a "${AUDIO_VENDOR}/firmware/." "${mnt}/lib/firmware/"
    if [[ -d "${AUDIO_VENDOR}/pipewire" ]]; then
        mkdir -p "${mnt}/usr/share/pipewire"
        cp -a "${AUDIO_VENDOR}/pipewire/." "${mnt}/usr/share/pipewire/"
    fi
    [[ -f "${mnt}/usr/share/alsa/ucm2/AYN/Odin2/HiFi.conf" ]] \
        || die "AYN Odin2 UCM missing after vendor/audio install"
    [[ -f "${mnt}/lib/firmware/qcom/sm8550/ayn/odin2/adsp.mbn" ]] \
        || die "Odin2 ADSP firmware missing after vendor/audio install"
fi
