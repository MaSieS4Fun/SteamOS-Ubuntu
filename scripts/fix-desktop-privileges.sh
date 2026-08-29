#!/usr/bin/env bash
# Fix Desktop privileges + dock stub + Mesa hold on a mounted rootfs or live /.
#
# Undoes NOPASSWD:ALL (sudo never asks / kate save fails), removes Valve dock
# updater, installs vendor libgbm debs + apt-mark hold.
#
# Usage:
#   sudo ./scripts/fix-desktop-privileges.sh /run/media/masies/STORAGE
#   ALLOW_LIVE_ROOT=1 sudo ./scripts/fix-desktop-privileges.sh /
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
SRC="${ROOT_DIR}/system_files"

log() { printf '==> [desktop-priv] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs|/ >"
[[ "$ROOTFS" == "/" ]] || ROOTFS="${ROOTFS%/}"
if [[ "$ROOTFS" == "/" && "${ALLOW_LIVE_ROOT:-0}" != "1" ]]; then
  die "Refusing live / without ALLOW_LIVE_ROOT=1"
fi

log "Replace NOPASSWD:ALL with OOBE-only sudoers"
install -d -m 0750 -o root -g root "${ROOTFS}/etc/sudoers.d"
rm -f "${ROOTFS}/etc/sudoers.d/99-steam-user"
install -D -m 0440 \
  "${SRC}/etc/sudoers.d/99-steam-oobe-helpers" \
  "${ROOTFS}/etc/sudoers.d/99-steam-oobe-helpers"
chown root:root "${ROOTFS}/etc/sudoers.d/99-steam-oobe-helpers"

log "Kate/Dolphin: polkit agent + desktop-admin rules (start after Wayland)"
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
install -D -m 0755 \
  "${SRC}/usr/local/bin/steamos-greetd-session" \
  "${ROOTFS}/usr/local/bin/steamos-greetd-session"
install -D -m 0755 \
  "${SRC}/usr/libexec/steamos-ubuntu/ensure-plasma-polkit-agent" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/ensure-plasma-polkit-agent"
install -D -m 0644 \
  "${SRC}/etc/xdg/autostart/steamos-polkit-agent-guard.desktop" \
  "${ROOTFS}/etc/xdg/autostart/steamos-polkit-agent-guard.desktop"
if [[ -f "${ROOTFS}/usr/lib/systemd/user/plasma-polkit-agent.service" ]]; then
  mkdir -p "${ROOTFS}/home/steam/.config/systemd/user/plasma-workspace.target.wants"
  ln -sfn /usr/lib/systemd/user/plasma-polkit-agent.service \
    "${ROOTFS}/home/steam/.config/systemd/user/plasma-workspace.target.wants/plasma-polkit-agent.service"
  rm -f "${ROOTFS}/home/steam/.config/systemd/user/graphical-session.target.wants/plasma-polkit-agent.service" \
    2>/dev/null || true
fi

log "Stub Valve dock updater (missing binary → Steam update error dialog)"
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/bin/jupiter-dock-updater" \
  "${ROOTFS}/usr/bin/jupiter-dock-updater"
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/bin/steamos-polkit-helpers/jupiter-dock-updater" \
  "${ROOTFS}/usr/bin/steamos-polkit-helpers/jupiter-dock-updater"

if [[ -x "${ROOT_DIR}/scripts/install-fexemu.sh" ]]; then
  log "Refresh /usr/bin/install-fexemu (sudo prompt + ~/src/fex-emu)"
  install -D -m 0755 \
    "${ROOT_DIR}/scripts/install-fexemu.sh" \
    "${ROOTFS}/usr/bin/install-fexemu"
fi
if [[ -x "${ROOT_DIR}/scripts/install-decky.sh" ]]; then
  log "Refresh /usr/bin/install-decky (Box64/FEX preflight + steam user)"
  install -D -m 0755 \
    "${ROOT_DIR}/scripts/install-decky.sh" \
    "${ROOTFS}/usr/bin/install-decky"
  if [[ -f "${ROOT_DIR}/vendor/Deky/decky_installer.desktop" ]]; then
    install -D -m 0644 \
      "${ROOT_DIR}/vendor/Deky/decky_installer.desktop" \
      "${ROOTFS}/usr/share/applications/install-decky.desktop"
  fi
fi

if [[ -x "${ROOT_DIR}/scripts/install-vendor-mesa-blockers.sh" ]]; then
  log "Vendor Mesa blockers + apt-mark hold"
  "${ROOT_DIR}/scripts/install-vendor-mesa-blockers.sh" "$ROOTFS" || true
fi

log "Done — reboot (or log out of Desktop) so sudoers reload"
if [[ "$ROOTFS" != "/" ]]; then
  log "Then on the handheld, sudo should ask for a password again."
fi
