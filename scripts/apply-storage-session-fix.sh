#!/usr/bin/env bash
# Push session/MangoHud fixes onto mounted STORAGE (or any rootfs).
# Fixes: system MangoHud control=mangohud, MANGOHUD leaking into steamwebhelper/CEF.
#
# Usage: sudo ./scripts/apply-storage-session-fix.sh [/media/odin2/STORAGE]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-/media/odin2/STORAGE}"
SRC="${ROOT_DIR}/system_files"
GOLDEN="${GOLDEN_ROOTFS:-${ROOT_DIR}/../SteamOS-Ubuntu-no-giroscopio/output/rootfs}"

log() { printf '==> [session-fix] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -d "${ROOTFS}/usr" ]] || die "Usage: $0 [rootfs]"

log "Installing gamescope-session + greetd + launch-steam (wayland: modeset)"
install -D -m 0755 "${SRC}/usr/bin/gamescope-session" "${ROOTFS}/usr/bin/gamescope-session"
install -D -m 0755 "${SRC}/usr/local/bin/steamos-greetd-session" \
  "${ROOTFS}/usr/local/bin/steamos-greetd-session"
install -D -m 0755 \
  "${SRC}/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"

log "OOBE: steamos-update (apply→0 + CompletedOOBE) + polkit helpers + sudoers"
install -D -m 0755 \
  "${SRC}/usr/bin/steamos-update" \
  "${ROOTFS}/usr/bin/steamos-update"
install -D -m 0755 \
  "${SRC}/usr/bin/steamos-polkit-helpers/steamos-set-timezone" \
  "${ROOTFS}/usr/bin/steamos-polkit-helpers/steamos-set-timezone"
install -D -m 0755 \
  "${SRC}/usr/bin/steamos-polkit-helpers/steamos-update" \
  "${ROOTFS}/usr/bin/steamos-polkit-helpers/steamos-update"
install -D -m 0755 \
  "${SRC}/usr/bin/steamos-polkit-helpers/steamos-select-branch" \
  "${ROOTFS}/usr/bin/steamos-polkit-helpers/steamos-select-branch"
install -D -m 0755 \
  "${SRC}/usr/bin/steamos-polkit-helpers/jupiter-biosupdate" \
  "${ROOTFS}/usr/bin/steamos-polkit-helpers/jupiter-biosupdate"
# Stub dock updater (delete → exit 127 → "Error de actualización" in Gaming Mode)
install -D -m 0755 \
  "${SRC}/usr/bin/jupiter-dock-updater" \
  "${ROOTFS}/usr/bin/jupiter-dock-updater"
install -D -m 0755 \
  "${SRC}/usr/bin/steamos-polkit-helpers/jupiter-dock-updater" \
  "${ROOTFS}/usr/bin/steamos-polkit-helpers/jupiter-dock-updater"
rm -f "${ROOTFS}/var/lib/steamos-ubuntu/oobe-os-update-acked" 2>/dev/null || true
install -D -m 0644 \
  "${SRC}/etc/polkit-1/rules.d/50-steamos-oobe-helpers.rules" \
  "${ROOTFS}/etc/polkit-1/rules.d/50-steamos-oobe-helpers.rules"
install -d -m 0750 -o root -g root "${ROOTFS}/etc/sudoers.d"
# Drop the broken NOPASSWD:ALL rule; keep only OOBE helper paths
rm -f "${ROOTFS}/etc/sudoers.d/99-steam-user" 2>/dev/null || true
install -D -m 0440 \
  "${SRC}/etc/sudoers.d/99-steam-oobe-helpers" \
  "${ROOTFS}/etc/sudoers.d/99-steam-oobe-helpers"
chown root:root "${ROOTFS}/etc/sudoers.d/99-steam-oobe-helpers"
if [[ -x "${ROOTFS}/usr/bin/timedatectl" ]]; then
  log "Pre-set timezone Europe/Madrid (OOBE timezone step)"
  chroot "${ROOTFS}" timedatectl set-timezone Europe/Madrid 2>/dev/null || true
fi
if [[ -x "${ROOT_DIR}/scripts/install-vendor-mesa-blockers.sh" ]]; then
  log "Vendor Mesa blockers + apt-mark hold"
  "${ROOT_DIR}/scripts/install-vendor-mesa-blockers.sh" "$ROOTFS" || true
fi

# ARM: steam-mode=oobe + arm-steam-oobe-update-guard → Steam DisplayManager X11.
log "Restore steam-mode=deck; drop ARM OOBE guard artifacts"
mkdir -p "${ROOTFS}/var/lib/steamos-ubuntu"
echo deck >"${ROOTFS}/var/lib/steamos-ubuntu/steam-mode"
echo gamescope-session >"${ROOTFS}/var/lib/steamos-ubuntu/session"
rm -f \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/arm-steam-oobe-update-guard" \
  "${ROOTFS}/var/lib/steamos-ubuntu/arm-oobe-did-reboot" \
  2>/dev/null || true

# ARM CDN update hangs on Retry — inhibit bootstrapper in $HOME (not /usr)
STEAM_DIR="${ROOTFS}/home/steam/.local/share/Steam"
if [[ -d "$STEAM_DIR" ]]; then
  mkdir -p "${STEAM_DIR}/steamrtarm64"
  printf '%s\n' \
    '# Steam ARM: skip broken client CDN self-update (Retry loop).' \
    'BootStrapperInhibitAll=enable' \
    'BootStrapperForceSelfUpdate=disable' \
    | tee "${STEAM_DIR}/steam.cfg" "${STEAM_DIR}/steamrtarm64/steam.cfg" >/dev/null
fi

if [[ -f "${SRC}/usr/share/sm8550-steamos/MangoHud/steam/MangoHud.conf" ]]; then
  install -D -m 0644 \
    "${SRC}/usr/share/sm8550-steamos/MangoHud/steam/MangoHud.conf" \
    "${ROOTFS}/usr/share/sm8550-steamos/MangoHud/steam/MangoHud.conf"
fi

STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "${ROOTFS}/etc/passwd")"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "${ROOTFS}/etc/passwd")"
USER_MANGO="${ROOTFS}/home/steam/.config/MangoHud/steam"
STEAM_MANGO="${ROOTFS}/home/steam/.local/share/Steam/config/mangohud.conf"

log "Reset user MangoHud → control=mangoapp"
mkdir -p "$USER_MANGO" "$(dirname "$STEAM_MANGO")"
if [[ -f "${ROOTFS}/usr/share/sm8550-steamos/MangoHud/steam/MangoHud.conf" ]]; then
  install -D -m 0644 \
    "${ROOTFS}/usr/share/sm8550-steamos/MangoHud/steam/MangoHud.conf" \
    "${USER_MANGO}/MangoHud.conf"
else
  printf '%s\n' 'control=mangoapp' 'preset=0' >"${USER_MANGO}/MangoHud.conf"
  chmod 0644 "${USER_MANGO}/MangoHud.conf"
fi
rm -f "$STEAM_MANGO"
ln "${USER_MANGO}/MangoHud.conf" "$STEAM_MANGO" 2>/dev/null \
  || cp -a "${USER_MANGO}/MangoHud.conf" "$STEAM_MANGO"

if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
  chown -R "${STEAM_UID}:${STEAM_GID}" "${ROOTFS}/home/steam/.config/MangoHud" 2>/dev/null || true
  chown "${STEAM_UID}:${STEAM_GID}" "$STEAM_MANGO" 2>/dev/null || true
  chown "${STEAM_UID}:${STEAM_GID}" \
    "${STEAM_DIR}/steam.cfg" \
    "${STEAM_DIR}/steamrtarm64/steam.cfg" 2>/dev/null || true
  chown "${STEAM_UID}:${STEAM_GID}" \
    "${ROOTFS}/var/lib/steamos-ubuntu/steam-mode" \
    "${ROOTFS}/var/lib/steamos-ubuntu/session" 2>/dev/null || true
fi

log "Clear Steam CEF htmlcache"
"${ROOT_DIR}/scripts/fix-storage-steam-htmlcache.sh" "$ROOTFS"

if [[ -d "${GOLDEN}/usr/lib/aarch64-linux-gnu" ]]; then
  log "Sync full vendor Mesa tree from ${GOLDEN}"
  GOLDEN_ROOTFS="$GOLDEN" "${ROOT_DIR}/scripts/sync-vendor-mesa-golden.sh" "$ROOTFS" --from "$GOLDEN" || true
fi

if [[ -x "${ROOT_DIR}/scripts/verify-vendor-mesa-stack.sh" ]]; then
  "${ROOT_DIR}/scripts/verify-vendor-mesa-stack.sh" "$ROOTFS" || true
fi

log "MangoHud.conf:"
cat "${USER_MANGO}/MangoHud.conf"
log "Done — reboot SD and enter Gaming Mode"
