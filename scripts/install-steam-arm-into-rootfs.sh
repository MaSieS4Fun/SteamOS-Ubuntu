#!/usr/bin/env bash
# Install Steam ARM (Deck OOBE-capable) into rootfs — image bake on Ubuntu.
#
# Uses vendor/SteamARM/install-steam-arm (clean: download + links + launchers;
# does NOT install MangoHud). Bootstrap under Xvfb: -steamdeck -exitsteam.
#
# Seed channel: steamdeck_publicbeta
# Require steamui.so + .installed so first boot can show Wi-Fi OOBE offline.
#
# Usage: sudo ./scripts/install-steam-arm-into-rootfs.sh <rootfs>
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
SHARE_DST="/usr/share/sm8550-steamos/steam-arm"
BOOTSTRAP_TIMEOUT="${STEAM_ARM_BOOTSTRAP_TIMEOUT:-900}"
STEAM_CHANNEL="${STEAM_ARM_CHANNEL:-steamdeck_publicbeta}"

log() { printf '==> [steam-arm] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ -x "${ROOT_DIR}/vendor/SteamARM/install-steam-arm" ]] || die "Missing vendor/SteamARM/install-steam-arm"
[[ "${EUID}" -eq 0 ]] || die "Run as root"

install -d "${ROOTFS}${SHARE_DST}"
cp -a "${ROOT_DIR}/vendor/SteamARM/." "${ROOTFS}${SHARE_DST}/"
chmod +x "${ROOTFS}${SHARE_DST}/install-steam-arm"
ln -sfn "${SHARE_DST}/install-steam-arm" "${ROOTFS}/usr/local/bin/install-steam-arm"
install -d "${ROOTFS}/usr/share/sm8550-resolute"
ln -sfn ../sm8550-steamos/steam-arm "${ROOTFS}/usr/share/sm8550-resolute/steam-arm"

# Session helpers (SteamOS-style)
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/bin/gamescope-session" \
  "${ROOTFS}/usr/bin/gamescope-session"

grep -q '^steam:' "${ROOTFS}/etc/passwd" || die "steam user missing in rootfs"

cleanup() {
  umount -l "${ROOTFS}/proc" 2>/dev/null || true
  umount -l "${ROOTFS}/sys" 2>/dev/null || true
  umount -l "${ROOTFS}/dev/pts" 2>/dev/null || true
  umount -l "${ROOTFS}/dev" 2>/dev/null || true
  umount -l "${ROOTFS}/run" 2>/dev/null || true
}
trap cleanup EXIT

mount -t proc proc "${ROOTFS}/proc" 2>/dev/null || true
mount -t sysfs sysfs "${ROOTFS}/sys" 2>/dev/null || true
mount --bind /dev "${ROOTFS}/dev" 2>/dev/null || true
mount --bind /dev/pts "${ROOTFS}/dev/pts" 2>/dev/null || true
mount -t tmpfs tmpfs "${ROOTFS}/run" 2>/dev/null || true
# Real upstream DNS for curl/Steam bake (not 127.0.0.53 / NM runtime symlink)
"${ROOT_DIR}/scripts/inject-chroot-dns.sh" "$ROOTFS"
# Fail early if chroot still cannot resolve (avoids opaque install-steam-arm errors)
if ! chroot "$ROOTFS" getent hosts client-update.steamstatic.com >/dev/null 2>&1; then
  echo "--- resolv.conf in rootfs ---" >&2
  cat "${ROOTFS}/etc/resolv.conf" >&2 || true
  die "No DNS inside chroot for client-update.steamstatic.com (fix host DNS, then retry)"
fi
log "chroot DNS OK for Steam CDN"

chroot "$ROOTFS" env DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends xvfb libgtk2.0-0t64 2>/dev/null || true

STEAM_HOME="/home/steam"
STEAM_DIR="${STEAM_HOME}/.local/share/Steam"
STEAM_BIN="${STEAM_DIR}/steamrtarm64/steam"

log "1/2 Seed ${STEAM_CHANNEL} (extract)"
chroot "$ROOTFS" runuser -u steam -- env \
  HOME="${STEAM_HOME}" USER=steam \
  STEAM_ARM_SHARE="${SHARE_DST}" \
  STEAM_ARM_NONINTERACTIVE=1 \
  STEAM_ARM_MODE=steamos \
  STEAM_ARM_CHANNEL="${STEAM_CHANNEL}" \
  STEAM_ARM_SKIP_BOOTSTRAP_RUN=1 \
  "${SHARE_DST}/install-steam-arm"

[[ -x "${ROOTFS}${STEAM_BIN}" ]] || die "steamrtarm64/steam missing after extract"

install -d "${ROOTFS}${STEAM_DIR}/package"
printf '%s\n' "${STEAM_CHANNEL}" > "${ROOTFS}${STEAM_DIR}/package/beta"
chown steam:steam "${ROOTFS}${STEAM_DIR}/package/beta" 2>/dev/null || true

log "2/2 Finish updater (-steamdeck -exitsteam, timeout=${BOOTSTRAP_TIMEOUT}s)"
set +e
chroot "$ROOTFS" runuser -u steam -- env \
  HOME="${STEAM_HOME}" USER=steam SteamDeck=1 \
  LD_LIBRARY_PATH="${STEAM_DIR}/steamrtarm64" \
  setsid bash -lc "
    Xvfb :90 -screen 0 1280x800x24 >/tmp/xvfb-steam-deck.log 2>&1 &
    xvfb_pid=\$!
    export DISPLAY=:90 HOME=${STEAM_HOME} SteamDeck=1
    export LD_LIBRARY_PATH=${STEAM_DIR}/steamrtarm64
    sleep 1
    timeout --signal=TERM --kill-after=45 ${BOOTSTRAP_TIMEOUT} \
      ${STEAM_BIN} -steamdeck -exitsteam \
      >/tmp/steam-deck-bootstrap.stdout 2>/tmp/steam-deck-bootstrap.stderr
    rc=\$?
    kill \$xvfb_pid 2>/dev/null || true
    exit \$rc
  "
steam_rc=$?
set -e
log "Deck bootstrap exit code: ${steam_rc}"

# Soft-clean (keep packages + UI); first-boot markers cleared in finalize-handheld-rootfs.sh
rm -rf \
  "${ROOTFS}${STEAM_DIR}/logs" \
  "${ROOTFS}${STEAM_DIR}/appcache/httpcache" \
  "${ROOTFS}${STEAM_DIR}/appcache/cefdata" \
  "${ROOTFS}${STEAM_DIR}/config/htmlcache" 2>/dev/null || true
find "${ROOTFS}${STEAM_HOME}" \( -type s -o -type p \) -delete 2>/dev/null || true
# Do not enable CEF remote debugging in the image (slows Steam start).
rm -f "${ROOTFS}${STEAM_DIR}/.cef-enable-remote-debugging" 2>/dev/null || true
# Bake under Xvfb may set CompletedOOBE — clear so first handheld boot is language/Wi-Fi.
rm -f \
  "${ROOTFS}${STEAM_HOME}/.steam/registry.vdf" \
  "${ROOTFS}${STEAM_DIR}/registry.vdf" \
  "${ROOTFS}${STEAM_DIR}/config/loginusers.vdf" \
  2>/dev/null || true

# Keep PATH shim (launch-steam), not a raw symlink to steamrtarm64/steam —
# absolute /home/steam/... links look dangling on the host and break finalize overlay.
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/bin/steam" \
  "${ROOTFS}/usr/bin/steam"
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"
chown -R steam:steam "${ROOTFS}${STEAM_HOME}" 2>/dev/null || true

UI="${ROOTFS}${STEAM_DIR}/steamrtarm64/steamui.so"
mapfile -t INSTALLED < <(find "${ROOTFS}${STEAM_DIR}/package" -maxdepth 1 -name 'steam_client_*_linuxarm64.installed' 2>/dev/null || true)

if [[ ! -f "$UI" ]]; then
  echo "--- bootstrap stdout (tail) ---" >&2
  tail -n 40 "${ROOTFS}/tmp/steam-deck-bootstrap.stdout" 2>/dev/null >&2 || true
  echo "--- bootstrap stderr (tail) ---" >&2
  tail -n 40 "${ROOTFS}/tmp/steam-deck-bootstrap.stderr" 2>/dev/null >&2 || true
  die "Bake incomplete: missing steamui.so (the bake requires this for offline Deck OOBE)"
fi
if ((${#INSTALLED[@]} == 0)); then
  echo "--- bootstrap stdout (tail) ---" >&2
  tail -n 40 "${ROOTFS}/tmp/steam-deck-bootstrap.stdout" 2>/dev/null >&2 || true
  echo "--- bootstrap stderr (tail) ---" >&2
  tail -n 40 "${ROOTFS}/tmp/steam-deck-bootstrap.stderr" 2>/dev/null >&2 || true
  die "Bake incomplete: no .installed manifest — first boot would re-download"
fi

install -d "${ROOTFS}${STEAM_HOME}/.config/steamos-ubuntu"
{
  date -Iseconds
  echo "channel=${STEAM_CHANNEL}"
  echo "steamui=ok"
  echo "installed=${INSTALLED[0]#"$ROOTFS"}"
  echo "pattern=steamos-ubuntu"
} > "${ROOTFS}${STEAM_HOME}/.config/steamos-ubuntu/steam-arm-bootstrap.txt"
chown -R steam:steam "${ROOTFS}${STEAM_HOME}/.config" 2>/dev/null || true

# Persist marker for image QA
install -d "${ROOTFS}/usr/share/sm8550-steamos"
cp "${ROOTFS}${STEAM_HOME}/.config/steamos-ubuntu/steam-arm-bootstrap.txt" \
  "${ROOTFS}/usr/share/sm8550-steamos/steam-deck-bake-ok.txt"

# Proton-CachyOS no longer needed — Proton 11 ARM works without manual patches.
# Opt-in only: INSTALL_PROTON_CACHYOS=1
if [[ "${INSTALL_PROTON_CACHYOS:-0}" == "1" ]]; then
  log "INSTALL_PROTON_CACHYOS=1 — installing Proton-CachyOS ARM"
  "${ROOT_DIR}/scripts/install-proton-cachyos-arm.sh" "$ROOTFS" \
    || log "WARN: Proton-CachyOS install failed (Steam still baked)"
fi

log "PASS — Steam Deck client baked (offline OOBE / Wi-Fi in Steam)"
log "  channel=${STEAM_CHANNEL}"
log "  ${STEAM_BIN}"
log "  ${INSTALLED[0]#"$ROOTFS"}"
