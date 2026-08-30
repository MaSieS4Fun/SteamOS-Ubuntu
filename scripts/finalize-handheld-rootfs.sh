#!/usr/bin/env bash
# Finalize a SteamOS-Ubuntu rootfs before packing the disk image.
# Steam Deck session (steam-mode=deck), Wayland DisplayManager targets,
# fixed MangoHud steam configs, boot trim, Steam startup fixes.
#
# Called by build-image.sh / bootstrap-rootfs.sh. Also usable on a mounted STORAGE:
#   sudo ./scripts/finalize-handheld-rootfs.sh /media/odin2/STORAGE
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
SRC="${ROOT_DIR}/system_files"

log() { printf '==> [finalize] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -d "$SRC" ]] || die "Missing system_files"

mask_unit() {
  local u="$1"
  mkdir -p "${ROOTFS}/etc/systemd/system"
  ln -sfn /dev/null "${ROOTFS}/etc/systemd/system/${u}"
  rm -f \
    "${ROOTFS}/etc/systemd/system/multi-user.target.wants/${u}" \
    "${ROOTFS}/etc/systemd/system/network-online.target.wants/${u}" \
    "${ROOTFS}/etc/systemd/system/sysinit.target.wants/${u}" \
    "${ROOTFS}/etc/systemd/system/sockets.target.wants/${u}" \
    "${ROOTFS}/etc/systemd/system/timers.target.wants/${u}" \
    2>/dev/null || true
}

# --- 1) Re-apply system_files (session/OOBE/boot overlays; skip Mesa pin if present) ---
log "Overlay system_files"
# Absolute symlinks like /usr/bin/steam → /home/steam/... look dangling on the host
# (target only exists inside the image). GNU cp refuses to overwrite them without this.
[[ -L "${ROOTFS}/usr/bin/steam" ]] && rm -f "${ROOTFS}/usr/bin/steam"
cp -a --remove-destination "${SRC}/." "${ROOTFS}/"

log "Quiet boot (kernel cmdline + journald; panel text ≠ session log)"
install -D -m 0644 \
  "${SRC}/etc/sysctl.d/20-quiet-console.conf" \
  "${ROOTFS}/etc/sysctl.d/20-quiet-console.conf"
install -D -m 0644 \
  "${SRC}/etc/systemd/system.conf.d/10-quiet-boot.conf" \
  "${ROOTFS}/etc/systemd/system.conf.d/10-quiet-boot.conf"
install -D -m 0644 \
  "${SRC}/etc/systemd/journald.conf.d/50-quiet-console.conf" \
  "${ROOTFS}/etc/systemd/journald.conf.d/50-quiet-console.conf"
for u in plymouth-start.service plymouth-read-write.service \
           plymouth-quit.service plymouth-quit-wait.service plymouth-quit-on-ready.service; do
  mask_unit "$u"
done
rm -f \
  "${ROOTFS}/etc/systemd/system/multi-user.target.wants/steamos-quiet-console.service" \
  "${ROOTFS}/etc/systemd/system/steamos-quiet-console.service" \
  2>/dev/null || true
install -D -m 0755 \
  "${SRC}/usr/libexec/steamos-ubuntu/steamos-panel-hold" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/steamos-panel-hold"
install -D -m 0644 \
  "${SRC}/etc/systemd/system/steamos-panel-hold.service" \
  "${ROOTFS}/etc/systemd/system/steamos-panel-hold.service"
mkdir -p "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
ln -sfn /etc/systemd/system/steamos-panel-hold.service \
  "${ROOTFS}/etc/systemd/system/multi-user.target.wants/steamos-panel-hold.service"
rm -f \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/trim-panel-console" \
  "${ROOTFS}/etc/systemd/system/steamos-trim-panel-console.service" \
  "${ROOTFS}/etc/systemd/system/multi-user.target.wants/steamos-trim-panel-console.service" \
  2>/dev/null || true

# Keep vendor Mesa apt pin from system_files / config (do NOT delete).
install -D -m 0644 \
  "${ROOT_DIR}/config/apt-preferences/99-block-ubuntu-mesa" \
  "${ROOTFS}/etc/apt/preferences.d/99-block-ubuntu-mesa"
# Hold list: vendor/system-fixes/MESA/hold pakages.txt
# shellcheck source=lib/mesa-hold-packages.sh
source "${ROOT_DIR}/scripts/lib/mesa-hold-packages.sh"
chroot "$ROOTFS" apt-mark hold "${MESA_HOLD_PKGS[@]}" 2>/dev/null || true
rm -f "${ROOTFS}/etc/apt/preferences.d/99-block-ubuntu-mesa.bak" 2>/dev/null || true
# Drop accidental host pycache from overlay
rm -rf "${ROOTFS}/usr/libexec/steamos-ubuntu/__pycache__" 2>/dev/null || true

# Steam is baked at image build — never auto-run install-steam from a terminal.
rm -f "${ROOTFS}/usr/share/sm8550-steamos/first-login-steam.sh"
for brc in \
  "${ROOTFS}/home/steam/.bashrc" \
  "${ROOTFS}/etc/skel/.bashrc"
do
  [[ -f "$brc" ]] || continue
  if grep -q 'first-login-steam' "$brc" 2>/dev/null; then
    # Remove the hook block (comment + if … fi)
    sed -i '/SteamOS-Ubuntu: fetch Steam ARM on first interactive login/,/^fi$/d' "$brc" 2>/dev/null \
      || sed -i '/first-login-steam/d' "$brc" 2>/dev/null || true
    log "Removed first-login-steam hook from ${brc#"$ROOTFS"}"
  fi
done
rm -f \
  "${ROOTFS}/home/steam/.config/steamos-ubuntu/steam-arm-attempted" \
  "${ROOTFS}/home/steam/.config/steamos-ubuntu/steam-arm-installed" \
  2>/dev/null || true

chmod +x \
  "${ROOTFS}/usr/bin/gamescope-session" \
  "${ROOTFS}/usr/bin/sm8550-prefer-internal-display" \
  "${ROOTFS}/usr/bin/steamos-session-select" \
  "${ROOTFS}/usr/bin/steamos-desktop-to-gamescope" \
  "${ROOTFS}/usr/bin/steamos-desktop-gamescope" \
  "${ROOTFS}/usr/bin/steam" \
  "${ROOTFS}/usr/lib/steamos/steam-set-session" \
  "${ROOTFS}/usr/bin/steamos-update" \
  "${ROOTFS}/usr/bin/steamos-select-branch" \
  "${ROOTFS}/usr/bin/jupiter-biosupdate" \
  "${ROOTFS}/usr/bin/jupiter-initial-firmware-update" \
  "${ROOTFS}/usr/bin/steamos-polkit-helpers/"* \
  "${ROOTFS}/usr/local/bin/steamos-greetd-session" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/steamos-manager" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/notify-stub" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/expand-rootfs" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/volume-keys" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/steamos-panel-hold" \
  2>/dev/null || true

# System Steam launchers/icons as root (OOBE client update must NOT need to write /usr)
log "Bake /usr Steam launchers (root-owned; client lives in /home/steam)"
install -D -m 0755 "${SRC}/usr/bin/steam" "${ROOTFS}/usr/bin/steam"
install -D -m 0755 "${SRC}/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"
install -D -m 0755 "${SRC}/usr/libexec/steamos-ubuntu/patch-steamui-update-check" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/patch-steamui-update-check"
# Home fallback + eager patch if SteamUI chunks already baked in
install -D -m 0755 "${SRC}/usr/libexec/steamos-ubuntu/patch-steamui-update-check" \
  "${ROOTFS}/home/steam/.local/share/steamos-ubuntu/patch-steamui-update-check"
if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
  chown -R "${STEAM_UID}:${STEAM_GID}" \
    "${ROOTFS}/home/steam/.local/share/steamos-ubuntu" 2>/dev/null || true
fi
STEAM_ROOT="${ROOTFS}/home/steam/.local/share/Steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/patch-steamui-update-check" 2>/dev/null || true
ln -sfn /usr/bin/steam "${ROOTFS}/usr/local/bin/steam"
if [[ -f "${SRC}/usr/share/applications/steam.desktop" ]]; then
  install -D -m 0644 "${SRC}/usr/share/applications/steam.desktop" \
    "${ROOTFS}/usr/share/applications/steam.desktop"
  install -D -m 0644 "${SRC}/usr/share/applications/steam.desktop" \
    "${ROOTFS}/usr/local/share/applications/steam.desktop"
fi
if [[ -f "${SRC}/usr/bin/steamos-desktop-to-gamescope" ]]; then
  install -D -m 0755 "${SRC}/usr/bin/steamos-desktop-to-gamescope" \
    "${ROOTFS}/usr/bin/steamos-desktop-to-gamescope"
fi
if [[ -f "${SRC}/usr/bin/steamos-desktop-gamescope" ]]; then
  install -D -m 0755 "${SRC}/usr/bin/steamos-desktop-gamescope" \
    "${ROOTFS}/usr/bin/steamos-desktop-gamescope"
fi
for desk in steamos-gamemode.desktop steambp.desktop; do
  if [[ -f "${SRC}/usr/share/applications/${desk}" ]]; then
    install -D -m 0644 "${SRC}/usr/share/applications/${desk}" \
      "${ROOTFS}/usr/share/applications/${desk}"
  fi
done
# Drop duplicate "Gaming Mode" launcher (same Exec as steamos-gamemode)
rm -f "${ROOTFS}/usr/share/applications/steamos-gaming-mode.desktop" \
  "${ROOTFS}/home/steam/Desktop/steamos-gaming-mode.desktop" \
  "${ROOTFS}/etc/skel/Desktop/steamos-gaming-mode.desktop" \
  2>/dev/null || true
for icon in \
  usr/share/pixmaps/steamos-gamemode.svg \
  usr/share/icons/hicolor/scalable/apps/steamos-gamemode.svg
do
  [[ -f "${SRC}/${icon}" ]] || continue
  install -D -m 0644 "${SRC}/${icon}" "${ROOTFS}/${icon}"
done
# Prefer vendor Steam icons (root-owned; OOBE must not need to install these)
VENDOR_ICONS="${ROOT_DIR}/vendor/SteamARM/icons"
if [[ -f "${VENDOR_ICONS}/steam.png" ]]; then
  install -D -m 0644 "${VENDOR_ICONS}/steam.png" "${ROOTFS}/usr/share/pixmaps/steam.png"
  install -D -m 0644 "${VENDOR_ICONS}/steam.png" \
    "${ROOTFS}/usr/share/icons/hicolor/48x48/apps/steam.png"
fi
if [[ -f "${VENDOR_ICONS}/steam_tray_48.tga" ]]; then
  install -D -m 0644 "${VENDOR_ICONS}/steam_tray_48.tga" \
    "${ROOTFS}/usr/share/pixmaps/steam_tray_48.tga"
fi
if [[ -f "${VENDOR_ICONS}/deck-logo.svg" ]]; then
  install -D -m 0644 "${VENDOR_ICONS}/deck-logo.svg" \
    "${ROOTFS}/usr/share/icons/hicolor/scalable/apps/steamos-gamemode.svg"
  install -D -m 0644 "${VENDOR_ICONS}/deck-logo.svg" \
    "${ROOTFS}/usr/share/pixmaps/steamos-gamemode.svg"
fi
chroot "$ROOTFS" update-desktop-database /usr/share/applications 2>/dev/null || true
chroot "$ROOTFS" gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true

# Plasma defaults: 150% scale + power button → sleep (skel + steam home if empty)
seed_plasma_defaults() {
  local dest="$1"
  install -d "${dest}/.config"
  for f in kdeglobals kwinrc powerdevilrc kscreenlockerrc; do
    if [[ -f "${SRC}/etc/xdg/${f}" && ! -f "${dest}/.config/${f}" ]]; then
      cp -a "${SRC}/etc/xdg/${f}" "${dest}/.config/${f}"
    fi
  done
}
seed_plasma_defaults "${ROOTFS}/etc/skel"
if [[ -d "${ROOTFS}/home/steam" ]]; then
  seed_plasma_defaults "${ROOTFS}/home/steam"
  chown -R --reference="${ROOTFS}/home/steam" "${ROOTFS}/home/steam/.config" 2>/dev/null || true
fi

# --- 2) Boot trim (from trim-boot.sh) ---
log "Mask boot dead weight"
mask_unit NetworkManager-wait-online.service
mask_unit nvmf-autoconnect.service
mask_unit nvmefc-boot-connections.service
mask_unit lvm2-monitor.service
mask_unit lvm2-lvmpolld.socket
mask_unit blk-availability.service
mask_unit ubuntu-advantage.service
mask_unit ua-reboot-cmds.service
mask_unit ua-timer.timer
mask_unit motd-news.timer

# greetd faster-boot drop-in already copied from system_files
install -D -m 0644 \
  "${SRC}/etc/systemd/system/greetd.service.d/faster-boot.conf" \
  "${ROOTFS}/etc/systemd/system/greetd.service.d/faster-boot.conf"
# Keep seatd + no getty on VT1 (from build_files/20); merge without plymouth-quit-wait
cat >"${ROOTFS}/etc/systemd/system/greetd.service.d/10-steamos.conf" <<'EOF'
[Unit]
Conflicts=getty@tty1.service
After=getty@tty1.service
Wants=seatd.service
EOF

# DNS/IP: NetworkManager + DHCP only (no static 1.1.1.1 / stub overrides).
# Steam OOBE Wi-Fi must get address + nameservers from the AP/router.
mkdir -p "${ROOTFS}/etc/NetworkManager/conf.d"
cat >"${ROOTFS}/etc/NetworkManager/conf.d/00-steamos-dns.conf" <<'EOF'
[main]
# Let NM write DHCP DNS into resolv.conf (do not force systemd-resolved / static DNS).
dns=default
rc-manager=symlink
EOF

# Drop any previous resolved-forced / static DNS drop-ins from older images
rm -f "${ROOTFS}/etc/systemd/resolved.conf.d/steamos-dns.conf" 2>/dev/null || true

# resolv.conf: NM will manage via /run/NetworkManager/resolv.conf when Wi-Fi is up.
# Point at NM's runtime file (empty until connected — correct for offline OOBE).
ln -sfn ../run/NetworkManager/resolv.conf "${ROOTFS}/etc/resolv.conf"

# gamescope CAP_SYS_NICE
GS=""
[[ -x "${ROOTFS}/usr/local/bin/gamescope" ]] && GS="/usr/local/bin/gamescope"
[[ -z "$GS" && -x "${ROOTFS}/usr/bin/gamescope" ]] && GS="/usr/bin/gamescope"
if [[ -n "$GS" ]]; then
  if chroot "$ROOTFS" command -v setcap >/dev/null 2>&1; then
    chroot "$ROOTFS" setcap 'cap_sys_nice=eip' "$GS" 2>/dev/null \
      && log "setcap CAP_SYS_NICE on $GS" \
      || log "WARN: setcap failed on gamescope (install libcap2-bin)"
  else
    log "WARN: setcap missing in rootfs — skip CAP_SYS_NICE"
  fi
fi

# --- 3) Session defaults: always Gaming Mode at boot (Steam Deck CLIENTCMD) ---
log "steam-mode=deck; session=gamescope-session (Steam Gamepad UI)"
install -d "${ROOTFS}/var/lib/steamos-ubuntu"
echo gamescope-session >"${ROOTFS}/var/lib/steamos-ubuntu/session"
echo deck >"${ROOTFS}/var/lib/steamos-ubuntu/steam-mode"
# steam (uid of Gaming Mode) must be able to SwitchToDesktop without pkexec hangs
# Use numeric ids from rootfs passwd (host may not have a "steam" account).
STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "${ROOTFS}/etc/passwd" 2>/dev/null || true)"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "${ROOTFS}/etc/passwd" 2>/dev/null || true)"
EXPECTED_STEAM_UID="${STEAM_UID_EXPECTED:-${STEAM_HOST_UID:-1000}}"
EXPECTED_STEAM_GID="${STEAM_GID_EXPECTED:-${STEAM_HOST_GID:-${EXPECTED_STEAM_UID}}}"
g="$(awk -F: '$1=="steam"{print $3; exit}' "${ROOTFS}/etc/group" 2>/dev/null || true)"
[[ -n "$g" ]] && STEAM_GID="$g"
if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
  chown -R "${STEAM_UID}:${STEAM_GID}" "${ROOTFS}/var/lib/steamos-ubuntu"
  if [[ "${STEAM_UID}" != "${EXPECTED_STEAM_UID}" ]]; then
    die "steam uid=${STEAM_UID} but expected ${EXPECTED_STEAM_UID} (host-friendly access would break)"
  fi
  if [[ "${STEAM_GID}" != "${EXPECTED_STEAM_GID}" ]]; then
    die "steam gid=${STEAM_GID} but expected ${EXPECTED_STEAM_GID}"
  fi
else
  log "WARN: steam user not in rootfs passwd — session dir left as root"
fi
chmod 0775 "${ROOTFS}/var/lib/steamos-ubuntu"
chmod 0664 "${ROOTFS}/var/lib/steamos-ubuntu/session" \
  "${ROOTFS}/var/lib/steamos-ubuntu/steam-mode" 2>/dev/null || true
chmod 0755 "${ROOTFS}/usr/lib/steamos/steam-set-session" \
  "${ROOTFS}/usr/bin/steamos-session-select" \
  "${ROOTFS}/usr/bin/steamos-desktop-to-gamescope" \
  "${ROOTFS}/usr/bin/steamos-desktop-gamescope" \
  "${ROOTFS}/usr/bin/steam" 2>/dev/null || true

# --- 3b) Deck session wrappers + fixed MangoHud steam configs (QAM overlay) ---
log "Re-install gamescope-session + launch-steam (Wayland DM + mango paths)"
install -D -m 0755 "${SRC}/usr/bin/gamescope-session" \
  "${ROOTFS}/usr/bin/gamescope-session"
install -D -m 0755 "${SRC}/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"
install -D -m 0755 "${SRC}/usr/libexec/steamos-ubuntu/patch-steamui-update-check" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/patch-steamui-update-check"

MANGO_VENDOR="${ROOT_DIR}/vendor/MangoHud/MangoHud/steam"
MANGO_SYS="${ROOTFS}/usr/share/sm8550-steamos/MangoHud/steam"
if [[ -d "$MANGO_VENDOR" ]]; then
  install -d "$MANGO_SYS"
  cp -a "${MANGO_VENDOR}/." "$MANGO_SYS/"
  log "MangoHud steam presets → /usr/share/sm8550-steamos/MangoHud/steam/"
elif [[ -d "${SRC}/usr/share/sm8550-steamos/MangoHud/steam" ]]; then
  install -d "$MANGO_SYS"
  cp -a "${SRC}/usr/share/sm8550-steamos/MangoHud/steam/." "$MANGO_SYS/"
fi

seed_mango_steam() {
  local home="$1"
  [[ -d "$home" ]] || return 0
  install -d "${home}/.config/MangoHud/steam"
  if [[ -d "$MANGO_SYS" ]]; then
    [[ -f "${home}/.config/MangoHud/steam/presets.conf" ]] \
      || cp -a "${MANGO_SYS}/presets.conf" "${home}/.config/MangoHud/steam/presets.conf" 2>/dev/null || true
    [[ -f "${home}/.config/MangoHud/steam/MangoHud.conf" ]] \
      || cp -a "${MANGO_SYS}/MangoHud.conf" "${home}/.config/MangoHud/steam/MangoHud.conf" 2>/dev/null || true
  fi
  if [[ ! -f "${home}/.config/MangoHud/steam/MangoHud.conf" ]]; then
    printf '%s\n' 'control=mangohud' 'preset=0' >"${home}/.config/MangoHud/steam/MangoHud.conf"
  fi
  # Steam fallback path (same inode when possible)
  install -d "${home}/.local/share/Steam/config"
  local conf="${home}/.config/MangoHud/steam/MangoHud.conf"
  local fallback="${home}/.local/share/Steam/config/mangohud.conf"
  rm -f "$fallback"
  ln "$conf" "$fallback" 2>/dev/null || cp -a "$conf" "$fallback"
}

seed_mango_steam "${ROOTFS}/etc/skel"
seed_mango_steam "${ROOTFS}/home/steam"
if [[ -d "${ROOTFS}/home/steam" ]]; then
  chown -R --reference="${ROOTFS}/home/steam" \
    "${ROOTFS}/home/steam/.config/MangoHud" \
    "${ROOTFS}/home/steam/.local/share/Steam/config" 2>/dev/null || true
  log "MangoHud steam conf → /home/steam/.config/MangoHud/steam/"
fi
# Grow SD root (growpart+resize2fs) before greetd/Steam — no reboot (Rocknix style)
chroot "$ROOTFS" systemctl enable steamos-expand-rootfs.service 2>/dev/null || true
mkdir -p "${ROOTFS}/etc/systemd/system/local-fs.target.wants"
ln -sfn /etc/systemd/system/steamos-expand-rootfs.service \
  "${ROOTFS}/etc/systemd/system/local-fs.target.wants/steamos-expand-rootfs.service" 2>/dev/null || true

# Boot unit forces gaming session before greetd (even if last logout was Plasma)
chroot "$ROOTFS" systemctl enable steamos-force-gaming-boot.service 2>/dev/null || true
ln -sfn /etc/systemd/system/steamos-force-gaming-boot.service \
  "${ROOTFS}/etc/systemd/system/greetd.service.wants/steamos-force-gaming-boot.service" 2>/dev/null \
  || {
    mkdir -p "${ROOTFS}/etc/systemd/system/greetd.service.wants"
    ln -sfn /etc/systemd/system/steamos-force-gaming-boot.service \
      "${ROOTFS}/etc/systemd/system/greetd.service.wants/steamos-force-gaming-boot.service"
  }
# Enable user oneshot for steam (reset to gaming when Plasma runs)
install -d "${ROOTFS}/home/steam/.config/systemd/user/graphical-session.target.wants"
ln -sfn /usr/lib/systemd/user/steamos-gamescope-autologin.service \
  "${ROOTFS}/home/steam/.config/systemd/user/graphical-session.target.wants/steamos-gamescope-autologin.service"
if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
  chown -R "${STEAM_UID}:${STEAM_GID}" "${ROOTFS}/home/steam/.config" 2>/dev/null || true
fi

# --- 4) Steam home: first-boot clean (keep baked client) ---
STEAM_HOME="${ROOTFS}/home/steam"
STEAM_DIR="${STEAM_HOME}/.local/share/Steam"
if [[ -d "$STEAM_HOME" ]]; then
  log "Reset Steam first-boot markers (keep steamui bake)"
  rm -f \
    "${STEAM_HOME}/.steam/registry.vdf" \
    "${STEAM_DIR}/registry.vdf" \
    "${STEAM_DIR}/config/loginusers.vdf" \
    "${STEAM_DIR}/config/DialogConfig.vdf" \
    "${STEAM_DIR}/.cef-enable-remote-debugging" \
    2>/dev/null || true
  # ARM CDN self-update fails (http error 0) → Retry forever. Inhibit in $HOME.
  mkdir -p "${STEAM_DIR}/steamrtarm64"
  printf '%s\n' \
    '# Steam ARM: skip broken client CDN self-update (Retry loop).' \
    'BootStrapperInhibitAll=enable' \
    'BootStrapperForceSelfUpdate=disable' \
    | tee "${STEAM_DIR}/steam.cfg" "${STEAM_DIR}/steamrtarm64/steam.cfg" >/dev/null
  if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
    chown "${STEAM_UID}:${STEAM_GID}" "${STEAM_DIR}/steam.cfg" \
      "${STEAM_DIR}/steamrtarm64/steam.cfg" 2>/dev/null || true
  fi
  find "$STEAM_HOME" \( -name '*.pid' -o -name '*.token' -o -name '*.crash' \) -delete 2>/dev/null || true
  # Drop bake logs / caches that bloat the image
  rm -rf \
    "${STEAM_DIR}/logs" \
    "${STEAM_DIR}/appcache/httpcache" \
    "${STEAM_DIR}/appcache/cefdata" \
    "${STEAM_DIR}/config/htmlcache" \
    2>/dev/null || true
  if [[ -d "${STEAM_DIR}/package" ]]; then
    echo "${STEAM_ARM_CHANNEL:-steamdeck_publicbeta}" >"${STEAM_DIR}/package/beta"
  fi
  # Proton-CachyOS is opt-in only (Proton 11 ARM works stock now)
  if [[ "${INSTALL_PROTON_CACHYOS:-0}" == "1" ]]; then
    log "INSTALL_PROTON_CACHYOS=1 — ensure Proton-CachyOS ARM"
    "${ROOT_DIR}/scripts/install-proton-cachyos-arm.sh" "$ROOTFS" \
      || log "WARN: Proton-CachyOS install skipped/failed"
  else
    # Drop leftover CachyOS tool from older bakes so Steam uses stock Proton 11 ARM
    rm -rf "${STEAM_DIR}/compatibilitytools.d"/proton-cachyos-* 2>/dev/null || true
  fi
  # Desktop polish that must survive Steam bake / OCI order
  install -d "${STEAM_HOME}/Desktop" "${STEAM_HOME}/.config"
  rm -f "${STEAM_HOME}/Desktop/"*howto* "${STEAM_HOME}/Desktop/"*HOW* \
    "${STEAM_HOME}/Desktop/"*kubuntu* "${STEAM_HOME}/Desktop/"*Kubuntu* \
    "${STEAM_HOME}/Desktop/org.kfocus."* "${STEAM_HOME}/Desktop/org.kubuntu."* \
    2>/dev/null || true
  # steambp = nested gamescope via steamos-desktop-gamescope (not session-select)
  rm -f "${STEAM_HOME}/Desktop/steambp.desktop" 2>/dev/null || true
  if [[ -f "${ROOTFS}/usr/share/applications/steamos-gamemode.desktop" ]]; then
    cp -a "${ROOTFS}/usr/share/applications/steamos-gamemode.desktop" \
      "${STEAM_HOME}/Desktop/steamos-gamemode.desktop"
    chmod 0755 "${STEAM_HOME}/Desktop/steamos-gamemode.desktop" || true
  fi
  rm -f "${STEAM_HOME}/Desktop/steamos-gaming-mode.desktop" 2>/dev/null || true
  if [[ -f "${ROOTFS}/usr/share/applications/steambp.desktop" ]]; then
    cp -a "${ROOTFS}/usr/share/applications/steambp.desktop" \
      "${STEAM_HOME}/Desktop/steambp.desktop"
    chmod 0755 "${STEAM_HOME}/Desktop/steambp.desktop" || true
  fi
  if [[ -f "${ROOTFS}/etc/xdg/powerdevilrc" ]]; then
    cp -a "${ROOTFS}/etc/xdg/powerdevilrc" "${STEAM_HOME}/.config/powerdevilrc"
  fi
  # Plasma screen lock OFF by default (no keyboard on handheld lock screen)
  if [[ -f "${ROOTFS}/etc/xdg/kscreenlockerrc" ]]; then
    cp -a "${ROOTFS}/etc/xdg/kscreenlockerrc" "${STEAM_HOME}/.config/kscreenlockerrc"
  fi
  if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
    chown -R "${STEAM_UID}:${STEAM_GID}" "$STEAM_HOME" 2>/dev/null || true
  else
    chown -R steam:steam "$STEAM_HOME" 2>/dev/null || true
  fi
fi

# No saved Wi-Fi in a clean image
if [[ -d "${ROOTFS}/etc/NetworkManager/system-connections" ]]; then
  find "${ROOTFS}/etc/NetworkManager/system-connections" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
fi

# --- 5) steam user groups ---
if grep -q '^steam:' "${ROOTFS}/etc/passwd" 2>/dev/null; then
  chroot "$ROOTFS" usermod -aG \
    sudo,audio,video,render,input,plugdev,netdev,bluetooth,games \
    steam 2>/dev/null || true
fi

# --- 6) Smoke: steamos-manager Variant that used to hang Steam ~40s ---
if chroot "$ROOTFS" python3 -c 'from gi.repository import GLib; GLib.Variant("as", ["power","balanced","performance"])' 2>/dev/null; then
  log "steamos-manager GLib.Variant smoke: OK"
else
  log "WARN: gi.repository.GLib not available in chroot for smoke test"
fi

# --- 6b) greetd = display-manager + session log ready ---
log "Force greetd as display-manager (Plasma must not leave a dead SDDM link)"
# Replace SDDM symlink BEFORE any systemctl preset (greetd postinst fails otherwise)
rm -f "${ROOTFS}/etc/systemd/system/display-manager.service"
ln -sfn /lib/systemd/system/greetd.service \
  "${ROOTFS}/etc/systemd/system/display-manager.service"
mkdir -p "${ROOTFS}/etc/systemd/system/graphical.target.wants"
rm -f "${ROOTFS}/etc/systemd/system/graphical.target.wants/sddm.service"
ln -sfn /lib/systemd/system/greetd.service \
  "${ROOTFS}/etc/systemd/system/graphical.target.wants/greetd.service"
if [[ -x "${ROOTFS}/usr/sbin/greetd" ]]; then
  echo /usr/sbin/greetd >"${ROOTFS}/etc/X11/default-display-manager"
elif [[ -x "${ROOTFS}/usr/bin/greetd" ]]; then
  echo /usr/bin/greetd >"${ROOTFS}/etc/X11/default-display-manager"
fi
for s in gdm sddm lightdm; do
  mask_unit "${s}.service"
done
# Finish half-configured packages without apt --fix-broken (Mesa pin)
chroot "$ROOTFS" dpkg --configure -a 2>/dev/null || true
chroot "$ROOTFS" systemctl enable seatd.service 2>/dev/null || true
# steamos-gpu-perf removed: GMU stalls fixed in vendor/kernel (1030/1031)
# Re-assert DM link after dpkg (postinst may try to preset sddm/greetd)
rm -f "${ROOTFS}/etc/systemd/system/display-manager.service"
ln -sfn /lib/systemd/system/greetd.service \
  "${ROOTFS}/etc/systemd/system/display-manager.service"
if [[ -x "${ROOTFS}/usr/sbin/greetd" ]]; then
  echo /usr/sbin/greetd >"${ROOTFS}/etc/X11/default-display-manager"
elif [[ -x "${ROOTFS}/usr/bin/greetd" ]]; then
  echo /usr/bin/greetd >"${ROOTFS}/etc/X11/default-display-manager"
fi
# Session log (persistent) — also collected under /var/log on the device
install -d -m 0755 "${ROOTFS}/var/log" "${ROOTFS}/var/tmp"
: >"${ROOTFS}/var/log/steamos-session.log"
chmod 666 "${ROOTFS}/var/log/steamos-session.log"
ln -sfn /var/log/steamos-session.log "${ROOTFS}/var/tmp/steamos-session.log"
install -D -m 0644 \
  "${SRC}/usr/lib/tmpfiles.d/steamos-session-log.conf" \
  "${ROOTFS}/usr/lib/tmpfiles.d/steamos-session-log.conf"

# --- 7) Snap must stay dead; Brave is the only browser ---
log "Ensure snap masked / browsers policy"
for u in snapd.service snapd.socket snapd.seeded.service snapd.apparmor.service; do
  mask_unit "$u"
done
rm -rf "${ROOTFS}/snap" "${ROOTFS}/var/snap" "${ROOTFS}/var/lib/snapd" 2>/dev/null || true
# Drop accidental Ubuntu browsers if something re-pulled them
chroot "$ROOTFS" apt-get purge -y firefox firefox-esr chromium chromium-browser epiphany-browser snapd 2>/dev/null || true
if [[ -x "${ROOTFS}/usr/bin/brave-browser" ]] || [[ -x "${ROOTFS}/opt/brave.com/brave/brave" ]]; then
  log "Brave present"
else
  log "WARN: brave-browser missing — rebuild with build_files/30-brave-and-mozilla-repos.sh"
fi

# --- 8) SDL2 gamepad (no pad→mouse) ---
install -D -m 0644 \
  "${SRC}/etc/sdl2/qcom-gamecontrollerdb.txt" \
  "${ROOTFS}/etc/sdl2/qcom-gamecontrollerdb.txt"
install -D -m 0644 \
  "${SRC}/etc/udev/rules.d/70-ayn-odin2-gamepad.rules" \
  "${ROOTFS}/etc/udev/rules.d/70-ayn-odin2-gamepad.rules"
install -d "${ROOTFS}/etc/environment.d" "${ROOTFS}/usr/lib/environment.d"
install -D -m 0644 \
  "${SRC}/usr/lib/environment.d/60-steamos-sdl-gamepad.conf" \
  "${ROOTFS}/usr/lib/environment.d/60-steamos-sdl-gamepad.conf"
cp -a "${ROOTFS}/usr/lib/environment.d/60-steamos-sdl-gamepad.conf" \
  "${ROOTFS}/etc/environment.d/60-steamos-sdl-gamepad.conf"
# Never ship pad→mouse helpers
chroot "$ROOTFS" apt-get purge -y antimicro antimicrox input-remapper xserver-xorg-input-joystick 2>/dev/null || true

# Mesa placeholders for ALL stock Mesa package names (incl. libgbm1/libgbm-dev)
if [[ -x "${ROOT_DIR}/scripts/install-vendor-mesa-dummies.sh" ]]; then
  log "Vendor Mesa apt placeholders"
  "${ROOT_DIR}/scripts/install-vendor-mesa-dummies.sh" "$ROOTFS" || true
fi
# Real vendor libgbm debs + apt-mark hold (isolates Turnip from Ubuntu Mesa / fix --broken)
if [[ -x "${ROOT_DIR}/scripts/install-vendor-mesa-blockers.sh" ]]; then
  log "Vendor Mesa blockers (libgbm debs + hold)"
  "${ROOT_DIR}/scripts/install-vendor-mesa-blockers.sh" "$ROOTFS" || true
fi
# No Valve dock on SM8550 — keep stubs (missing binary → Steam update error dialog)
install -D -m 0755 \
  "${SRC}/usr/bin/jupiter-dock-updater" \
  "${ROOTFS}/usr/bin/jupiter-dock-updater"
install -D -m 0755 \
  "${SRC}/usr/bin/steamos-polkit-helpers/jupiter-dock-updater" \
  "${ROOTFS}/usr/bin/steamos-polkit-helpers/jupiter-dock-updater"
# Steam queries dpkg steamos-updatelevel Version on Settings → Check for updates.
# Missing package → Updater check error: 40 / "Error de actualización".
UPDATELEVEL_DEB="$(echo "${ROOT_DIR}"/vendor/system-fixes/steamos-updatelevel/steamos-updatelevel_*.deb)"
if [[ -f "${UPDATELEVEL_DEB}" ]]; then
  log "Install steamos-updatelevel (${UPDATELEVEL_DEB##*/})"
  cp -f "${UPDATELEVEL_DEB}" "${ROOTFS}/tmp/steamos-updatelevel.deb"
  chroot "${ROOTFS}" dpkg -i /tmp/steamos-updatelevel.deb || true
  rm -f "${ROOTFS}/tmp/steamos-updatelevel.deb"
fi
# Ensure narrow OOBE sudoers (override any NOPASSWD:ALL from earlier stages)
rm -f "${ROOTFS}/etc/sudoers.d/99-steam-user" 2>/dev/null || true
install -D -m 0440 \
  "${SRC}/etc/sudoers.d/99-steam-oobe-helpers" \
  "${ROOTFS}/etc/sudoers.d/99-steam-oobe-helpers"
chown root:root "${ROOTFS}/etc/sudoers.d/99-steam-oobe-helpers"

# Kate/Dolphin root-save: polkit rule + ensure agent is wanted for steam user
install -D -m 0644 \
  "${SRC}/etc/polkit-1/rules.d/60-steamos-desktop-admin.rules" \
  "${ROOTFS}/etc/polkit-1/rules.d/60-steamos-desktop-admin.rules"
_pk_gid="$(awk -F: '$1=="polkitd"{print $3; exit}' "${ROOTFS}/etc/group" 2>/dev/null || true)"
if [[ -n "${_pk_gid}" ]]; then
  chown "0:${_pk_gid}" "${ROOTFS}/etc/polkit-1/rules.d" 2>/dev/null || true
  chmod 750 "${ROOTFS}/etc/polkit-1/rules.d" 2>/dev/null || true
fi
unset _pk_gid
chown root:root "${ROOTFS}/etc/polkit-1/rules.d/"*.rules 2>/dev/null || true
if [[ -f "${ROOTFS}/etc/xdg/autostart/polkit-kde-authentication-agent-1.desktop" ]]; then
  sed -i 's/^X-systemd-skip=true/X-systemd-skip=false/' \
    "${ROOTFS}/etc/xdg/autostart/polkit-kde-authentication-agent-1.desktop" || true
fi
install -D -m 0644 \
  "${SRC}/usr/lib/systemd/user/plasma-polkit-agent.service.d/after-wayland.conf" \
  "${ROOTFS}/usr/lib/systemd/user/plasma-polkit-agent.service.d/after-wayland.conf"
install -D -m 0644 \
  "${SRC}/usr/share/kio/servicemenus/kate-edit-as-admin.desktop" \
  "${ROOTFS}/usr/share/kio/servicemenus/kate-edit-as-admin.desktop"
install -D -m 0755 \
  "${SRC}/usr/local/bin/steamos-greetd-session" \
  "${ROOTFS}/usr/local/bin/steamos-greetd-session"
# Pull plasma-polkit-agent with Plasma workspace (not before Wayland exists)
if [[ -f "${ROOTFS}/usr/lib/systemd/user/plasma-polkit-agent.service" ]]; then
  for wants in \
    "${ROOTFS}/home/steam/.config/systemd/user/plasma-workspace.target.wants" \
    "${ROOTFS}/etc/systemd/user/plasma-workspace.target.wants"
  do
    mkdir -p "$wants"
    ln -sfn /usr/lib/systemd/user/plasma-polkit-agent.service \
      "${wants}/plasma-polkit-agent.service"
  done
  # Drop early graphical-session wants that can race the compositor
  rm -f \
    "${ROOTFS}/home/steam/.config/systemd/user/graphical-session.target.wants/plasma-polkit-agent.service" \
    "${ROOTFS}/etc/systemd/user/graphical-session.target.wants/plasma-polkit-agent.service" \
    2>/dev/null || true
fi
# Packages required for elevation UI
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
  polkit-kde-agent-1 kio-admin kate \
  2>/dev/null || true

# Refresh FEX installer (asks sudo in konsole; source under ~/src/fex-emu)
if [[ -f "${ROOT_DIR}/scripts/install-fexemu.sh" ]]; then
  install -D -m 0755 \
    "${ROOT_DIR}/scripts/install-fexemu.sh" \
    "${ROOTFS}/usr/bin/install-fexemu"
  cat >"${ROOTFS}/usr/share/applications/install-fexemu.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=FEXEmu
Comment=Install/update or uninstall FEX-Emu (x86_64 on ARM)
Exec=konsole -e bash -c 'sudo /usr/bin/install-fexemu; echo; read -r -p "Press Enter to close..."'
Icon=utilities-terminal
Terminal=false
Categories=System;Utility;X-ARM-Manager;
Keywords=fex;fexemu;x86;emulation;wine;arm;box64;
StartupNotify=true
EOF
fi

# Decky PluginLoader (optional — user installs from ARM-Manager; needs Box64/FEX)
if [[ -f "${ROOT_DIR}/scripts/install-decky.sh" ]]; then
  install -D -m 0755 \
    "${ROOT_DIR}/scripts/install-decky.sh" \
    "${ROOTFS}/usr/bin/install-decky"
  if [[ -f "${ROOT_DIR}/vendor/Decky/decky_installer.desktop" ]]; then
    install -D -m 0644 \
      "${ROOT_DIR}/vendor/Decky/decky_installer.desktop" \
      "${ROOTFS}/usr/share/applications/install-decky.desktop"
  fi
fi

# Decky PluginLoader: FEX RootFS + fast-stop + steamos-ubuntu + gaming sudoers
_LSFG_DIR="${ROOT_DIR}/vendor/system-fixes/LSFG-VK/plugin_loader.service.d"
for _drop in fast-stop.conf fex-steam-rootfs.conf; do
  _src="${_LSFG_DIR}/${_drop}"
  [[ -f "$_src" ]] || continue
  log "Decky plugin_loader drop-in: ${_drop}"
  install -D -m 0644 "$_src" \
    "${ROOTFS}/etc/systemd/system/plugin_loader.service.d/${_drop}"
done
if [[ -f "${SRC}/etc/systemd/system/plugin_loader.service.d/steamos-ubuntu.conf" ]]; then
  install -D -m 0644 \
    "${SRC}/etc/systemd/system/plugin_loader.service.d/steamos-ubuntu.conf" \
    "${ROOTFS}/etc/systemd/system/plugin_loader.service.d/steamos-ubuntu.conf"
fi
if [[ -f "${SRC}/etc/sudoers.d/99-steam-decky-plugin-loader" ]]; then
  install -D -m 0440 \
    "${SRC}/etc/sudoers.d/99-steam-decky-plugin-loader" \
    "${ROOTFS}/etc/sudoers.d/99-steam-decky-plugin-loader"
fi
install -D -m 0755 \
  "${SRC}/usr/libexec/steamos-ubuntu/ensure-decky-plugin-loader" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/ensure-decky-plugin-loader"

# Bundled Decky plugins (vendor/plug-ins-steamos-ubuntu → /usr/share/steamos-ubuntu/decky-plugins)
if [[ -x "${ROOT_DIR}/scripts/stage-decky-plugins-into-rootfs.sh" ]]; then
  "${ROOT_DIR}/scripts/stage-decky-plugins-into-rootfs.sh" "$ROOTFS"
fi

# LSFG-VK Decky snapshot → /home/steam (config + ~/lsfg + pre-seeded plugin tree)
if [[ -x "${ROOT_DIR}/scripts/stage-decky-lsfg-vk-home-into-rootfs.sh" ]]; then
  "${ROOT_DIR}/scripts/stage-decky-lsfg-vk-home-into-rootfs.sh" "$ROOTFS"
fi

# Maliit OSK: Qt6 for Plasma 6 + Qt5 for older apps; KWin InputMethod owns the VK
log "Ensure maliit keyboard + Qt5/Qt6 inputcontext"
if [[ -x "${ROOT_DIR}/scripts/unmount-rootfs-binds.sh" ]]; then
  mountpoint -q "${ROOTFS}/proc" || mount -t proc proc "${ROOTFS}/proc"
  mountpoint -q "${ROOTFS}/sys" || mount -t sysfs sysfs "${ROOTFS}/sys"
  mountpoint -q "${ROOTFS}/dev" || mount --bind /dev "${ROOTFS}/dev"
fi
chroot "$ROOTFS" apt-get update -y 2>/dev/null || true
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
  maliit-keyboard \
  maliit-server-qt5 maliit-inputcontext-qt5 libmaliit-plugins2 \
  maliit-server-qt6 maliit-inputcontext-qt6 libmaliit6-plugins2 \
  2>/dev/null || true
install -D -m 0644 "${SRC}/etc/xdg/kwinrc" "${ROOTFS}/etc/xdg/kwinrc"
install -D -m 0644 "${SRC}/etc/profile.d/maliit-im.sh" "${ROOTFS}/etc/profile.d/maliit-im.sh"
if [[ -x "${ROOTFS}/usr/bin/maliit-keyboard" ]]; then
  cat >"${ROOTFS}/usr/share/applications/maliit-keyboard.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Maliit Keyboard
Name[es]=Teclado Maliit
Comment=On-screen keyboard
Exec=maliit-keyboard
Icon=input-keyboard
Terminal=false
Categories=Utility;Accessibility;
EOF
  log "maliit-keyboard installed OK"
fi
# Prefer Maliit over fcitx5 as the Plasma Wayland virtual keyboard candidate
FCITX_DESKTOP="${ROOTFS}/usr/share/applications/org.fcitx.Fcitx5.desktop"
if [[ -f "$FCITX_DESKTOP" ]]; then
  if grep -q '^X-KDE-Wayland-VirtualKeyboard=' "$FCITX_DESKTOP"; then
    sed -i 's/^X-KDE-Wayland-VirtualKeyboard=.*/X-KDE-Wayland-VirtualKeyboard=false/' \
      "$FCITX_DESKTOP" || true
  else
    printf '\nX-KDE-Wayland-VirtualKeyboard=false\n' >>"$FCITX_DESKTOP" || true
  fi
fi
# Polkit agent guard: start after Wayland (Kate root-save password dialog)
install -D -m 0755 \
  "${SRC}/usr/libexec/steamos-ubuntu/ensure-plasma-polkit-agent" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/ensure-plasma-polkit-agent"
install -D -m 0755 \
  "${SRC}/usr/libexec/steamos-ubuntu/ensure-decky-plugin-loader" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/ensure-decky-plugin-loader"
install -D -m 0644 \
  "${SRC}/etc/xdg/autostart/steamos-polkit-agent-guard.desktop" \
  "${ROOTFS}/etc/xdg/autostart/steamos-polkit-agent-guard.desktop"

# Prefer Speaker sink after PipeWire/WirePlumber (HDMI/DP may otherwise stay default)
install -D -m 0755 \
  "${SRC}/usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink"
install -D -m 0644 \
  "${SRC}/usr/lib/systemd/user/sm8550-prefer-speaker-sink.service" \
  "${ROOTFS}/usr/lib/systemd/user/sm8550-prefer-speaker-sink.service"
# Prefer HiFi over pro-audio when WirePlumber has no sticky profile
if [[ -f "${SRC}/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" ]]; then
  install -D -m 0644 \
    "${SRC}/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" \
    "${ROOTFS}/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf"
fi
mkdir -p "${ROOTFS}/etc/skel/.local/share/plasma-systemmonitor"
if [[ -f "${SRC}/etc/skel/.local/share/plasma-systemmonitor/overview.page" ]]; then
  install -m 0644 \
    "${SRC}/etc/skel/.local/share/plasma-systemmonitor/overview.page" \
    "${ROOTFS}/etc/skel/.local/share/plasma-systemmonitor/overview.page"
  install -m 0644 \
    "${SRC}/etc/skel/.local/share/plasma-systemmonitor/overview.page" \
    "${ROOTFS}/usr/share/plasma-systemmonitor/overview.page"
fi
if [[ -f "${SRC}/etc/skel/.local/share/plasma-systemmonitor/history.page" ]]; then
  install -m 0644 \
    "${SRC}/etc/skel/.local/share/plasma-systemmonitor/history.page" \
    "${ROOTFS}/etc/skel/.local/share/plasma-systemmonitor/history.page"
  install -m 0644 \
    "${SRC}/etc/skel/.local/share/plasma-systemmonitor/history.page" \
    "${ROOTFS}/usr/share/plasma-systemmonitor/history.page"
fi
# Enable prefer-speaker for steam user + skel default.target.wants
for wants in \
  "${ROOTFS}/etc/skel/.config/systemd/user/default.target.wants" \
  "${ROOTFS}/home/steam/.config/systemd/user/default.target.wants" \
  "${ROOTFS}/etc/systemd/user/default.target.wants"; do
  mkdir -p "${wants}"
  ln -sfn /usr/lib/systemd/user/sm8550-prefer-speaker-sink.service \
    "${wants}/sm8550-prefer-speaker-sink.service"
done
if [[ -x "${ROOT_DIR}/scripts/unmount-rootfs-binds.sh" ]]; then
  "${ROOT_DIR}/scripts/unmount-rootfs-binds.sh" "$ROOTFS" 2>/dev/null || true
fi

# --- Purge sudo-rs: incompatible with Steam's sudo -n usage ---
# ubuntu-minimal pulls sudo-rs which registers as the update-alternatives
# default for /usr/bin/sudo. Steam calls sudo -n internally and sudo-rs
# breaks that flow → BMainLoop stall → black screen.
log "Removing sudo-rs and pinning classic sudo"
chroot "$ROOTFS" apt-get purge -y sudo-rs 2>/dev/null || true
# Force update-alternatives back to the classic setuid sudo
if [[ -e "${ROOTFS}/usr/bin/sudo.ws" ]]; then
  chroot "$ROOTFS" update-alternatives --set sudo /usr/bin/sudo.ws 2>/dev/null \
    || ln -sf /usr/bin/sudo.ws "${ROOTFS}/etc/alternatives/sudo"
fi
# Block sudo-rs from ever coming back via apt
cat > "${ROOTFS}/etc/apt/preferences.d/99-block-sudo-rs" <<'APTPIN'
Package: sudo-rs
Pin: release *
Pin-Priority: -1
APTPIN
chown root:root "${ROOTFS}/etc/apt/preferences.d/99-block-sudo-rs"
chmod 0644 "${ROOTFS}/etc/apt/preferences.d/99-block-sudo-rs"
# Ensure classic sudo is installed and setuid
chroot "$ROOTFS" apt-get install -y --no-install-recommends sudo 2>/dev/null || true

# InputPlumber: rsinput pad → Steam Deck Controller (deck-uhid) for Gaming Mode
if [[ -x "${ROOT_DIR}/scripts/install-inputplumber.sh" ]]; then
  log "InputPlumber (Odin2 → deck-uhid)"
  # chroot apt needs real DNS (finalize already set NM symlink for the device)
  if [[ -x "${ROOT_DIR}/scripts/inject-chroot-dns.sh" ]]; then
    "${ROOT_DIR}/scripts/inject-chroot-dns.sh" "$ROOTFS" 2>/dev/null || true
  fi
  if "${ROOT_DIR}/scripts/install-inputplumber.sh" "$ROOTFS"; then
    log "InputPlumber installed OK"
  else
    log "WARN: InputPlumber install failed (network/deb) — re-run scripts/install-inputplumber.sh"
  fi
  # masi-motion (SSC → uinput IMU, odin2-dsu-v9) into the image
  if [[ -x "${ROOT_DIR}/vendor/masi-motion/install.sh" ]]; then
    log "masi-motion (qcom-motion + sensors) → rootfs"
    if "${ROOT_DIR}/vendor/masi-motion/install.sh" --rootfs "$ROOTFS" --force; then
      log "masi-motion installed OK (odin2-dsu-v9)"
    else
      log "WARN: masi-motion bake failed (network/build) — on device: sudo ./scripts/install-masi-motion.sh"
    fi
  fi
  # GYRO-FIX: desktop pad + optional DSU app
  if [[ -x "${ROOT_DIR}/vendor/gyro-desktop/install.sh" ]]; then
    log "gyro-desktop (GYRO-FIX) → rootfs"
    if "${ROOT_DIR}/vendor/gyro-desktop/install.sh" "$ROOTFS"; then
      log "gyro-desktop installed OK"
    else
      log "WARN: gyro-desktop bake failed — on device: sudo ./vendor/gyro-desktop/install.sh"
    fi
  fi
  # Restore handheld DNS (DHCP via NetworkManager)
  rm -f "${ROOTFS}/etc/resolv.conf"
  ln -sfn ../run/NetworkManager/resolv.conf "${ROOTFS}/etc/resolv.conf"
fi

# Desktop Gaming Mode (steambp + adapted steamos-session-select) — after Steam bake
if [[ -x "${ROOT_DIR}/scripts/install-desktop-gamemode.sh" ]]; then
  log "Desktop Gaming Mode (vendor/Desktop_gamemode)"
  "${ROOT_DIR}/scripts/install-desktop-gamemode.sh" "$ROOTFS"
fi

# System trees must be root:root (not host uid 1000 == steam). Client update
# writes only under /home/steam; /usr launchers are baked here as root.
if [[ -x "${ROOT_DIR}/scripts/fix-rootfs-ownership.sh" ]]; then
  log "Fixing system ownership (root:root; preserve /home/steam)"
  "${ROOT_DIR}/scripts/fix-rootfs-ownership.sh" "$ROOTFS"
else
  die "missing scripts/fix-rootfs-ownership.sh"
fi
if [[ -x "${ROOT_DIR}/scripts/cleanup-ubuntu-leftovers.sh" ]]; then
  log "Kubuntu desktop branding cleanup"
  "${ROOT_DIR}/scripts/cleanup-ubuntu-leftovers.sh" "$ROOTFS" || true
fi

# MaSi apt source (apps + kernel updates via GitHub Pages once repo is public)
if [[ "${SKIP_STEAMOS_APT_SOURCE:-0}" != "1" ]] \
  && [[ -x "${ROOT_DIR}/scripts/install-steamos-ubuntu-apt-source.sh" ]]; then
  log "SteamOS-Ubuntu apt source (steamos-ubuntu.list + keyring)"
  "${ROOT_DIR}/scripts/install-steamos-ubuntu-apt-source.sh" "$ROOTFS"
fi

# Register MaSi .deb packages in dpkg (future apt upgrade on devices)
if [[ "${SKIP_STEAMOS_APT_PACKAGES:-0}" != "1" ]] \
  && [[ -x "${ROOT_DIR}/scripts/install-steamos-ubuntu-apt-packages.sh" ]]; then
  log "SteamOS-Ubuntu apt packages (dpkg register for apt upgrade)"
  "${ROOT_DIR}/scripts/install-steamos-ubuntu-apt-packages.sh" "$ROOTFS"
fi

# Post apt-bake: fixpad + session hooks (gyro .deb may overwrite vendor binaries)
if [[ -x "${ROOT_DIR}/vendor/fixpad-sm8550/install.sh" ]]; then
  log "fixpad-sm8550 (AYN stick range + desktop idle wake) → rootfs"
  if "${ROOT_DIR}/vendor/fixpad-sm8550/install.sh" "$ROOTFS"; then
    log "fixpad-sm8550 installed OK"
  else
    log "WARN: fixpad-sm8550 bake failed — on device: sudo ./vendor/fixpad-sm8550/install.sh"
  fi
fi
if [[ -f "${SRC}/usr/bin/gamescope-session" ]]; then
  install -m 0755 "${SRC}/usr/bin/gamescope-session" "${ROOTFS}/usr/bin/gamescope-session"
fi
if [[ -x "${ROOT_DIR}/vendor/gyro-desktop/install.sh" ]]; then
  log "gyro-desktop refresh (post apt-bake hooks)"
  "${ROOT_DIR}/vendor/gyro-desktop/install.sh" "$ROOTFS" || true
fi

# Marker for QA
install -d "${ROOTFS}/usr/share/sm8550-steamos"
{
  date -Iseconds
  echo "finalize=ok"
  echo "steam-mode=deck"
  echo "mangohud-steam-config=ok"
  echo "wayland-display-manager=target"
  echo "boot-trim=ok"
  echo "steamos-manager-variant-fix=ok"
  echo "ownership=root:root-system"
  echo "steam-client-home-only=1"
  echo "snap=disabled"
  echo "browser=brave-only"
  echo "gamepad=inputplumber+sdl2+fixpad-sm8550"
  if [[ -f "${ROOTFS}/usr/share/sm8550-steamos/inputplumber-ok.txt" ]]; then
    echo "inputplumber=ok"
  else
    echo "inputplumber=missing"
  fi
} >"${ROOTFS}/usr/share/sm8550-steamos/finalize-ok.txt"

log "Handheld rootfs finalized"
