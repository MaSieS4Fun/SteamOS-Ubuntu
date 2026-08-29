#!/usr/bin/env bash
# Hot-apply desktop polish onto a mounted STORAGE/rootfs (no full image bake).
# Usage:
#   sudo mount -o remount,rw /media/odin2/STORAGE
#   sudo ./scripts/fix-desktop-polish-on-rootfs.sh /media/odin2/STORAGE
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${1:-}"
[[ -n "$ROOT" && -d "$ROOT/usr" ]] || { echo "Usage: $0 <rootfs>"; exit 1; }
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root"; exit 1; }

SRC="${ROOT_DIR}/system_files"
STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "$ROOT/etc/passwd")"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "$ROOT/etc/passwd")"
g="$(awk -F: '$1=="steam"{print $3; exit}' "$ROOT/etc/group" 2>/dev/null || true)"
[[ -n "$g" ]] && STEAM_GID="$g"
[[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]] || { echo "ERROR: no steam user"; exit 1; }
echo "==> polish on $ROOT (steam ${STEAM_UID}:${STEAM_GID})"

overlay() {
  local rel="$1" mode="${2:-}"
  local src="${SRC}/${rel}" dst="${ROOT}/${rel}"
  [[ -e "$src" ]] || { echo "skip missing $rel"; return 0; }
  install -D ${mode:+-m "$mode"} "$src" "$dst"
}

# --- overlays (icons, desktops, power, gpu) ---
overlay usr/share/icons/hicolor/scalable/apps/steamos-gamemode.svg 0644
overlay usr/share/pixmaps/steamos-gamemode.svg 0644
overlay usr/share/applications/steamos-gamemode.desktop 0644
# steamos-gaming-mode.desktop removed (duplicate of steamos-gamemode)
rm -f "$ROOT/usr/share/applications/steamos-gaming-mode.desktop" \
  "$ROOT/home/steam/Desktop/steamos-gaming-mode.desktop" 2>/dev/null || true
overlay usr/share/applications/steambp.desktop 0644
overlay usr/bin/steamos-desktop-to-gamescope 0755
overlay usr/bin/steamos-desktop-gamescope 0755
overlay etc/systemd/logind.conf.d/steamos-power.conf 0644
overlay etc/xdg/powerdevilrc 0644
overlay etc/polkit-1/rules.d/10-steamos-suspend.rules 0644
overlay usr/bin/gamescope-session 0755

# Drop obsolete userspace GMU "perf governor" mitigation (fixed in kernel 1030/1031)
rm -f "$ROOT/etc/systemd/system/steamos-gpu-perf.service" \
  "$ROOT/usr/libexec/steamos-ubuntu/steamos-gpu-perf.sh" \
  "$ROOT/etc/systemd/system/multi-user.target.wants/steamos-gpu-perf.service" \
  "$ROOT/etc/systemd/system/graphical.target.wants/steamos-gpu-perf.service" \
  2>/dev/null || true

# Desktop junk + emoji / icon browser launchers
rm -f \
  "$ROOT/usr/share/applications/org.kfocus.web.howtos.desktop" \
  "$ROOT/usr/share/applications/org.kubuntu.web.home.desktop" \
  "$ROOT/usr/share/applications/org.kubuntu.restore-desktop-links.desktop" \
  "$ROOT/usr/share/applications/org.kde.plasma.emojier.desktop" \
  "$ROOT/usr/share/applications/yad-icon-browser.desktop" \
  "$ROOT/home/steam/Desktop/org.kfocus.web.howtos.desktop" \
  "$ROOT/home/steam/Desktop/org.kubuntu.web.home.desktop" \
  "$ROOT/home/steam/Desktop/"*howto* \
  "$ROOT/home/steam/Desktop/"*HOW* \
  "$ROOT/home/steam/Desktop/"*kubuntu* \
  "$ROOT/home/steam/Desktop/"*Kubuntu* \
  2>/dev/null || true

rm -f \
  "$ROOT/usr/share/applications/org.kubuntu.manage-software.desktop" \
  "$ROOT/usr/bin/kubuntu-manage-software" \
  2>/dev/null || true

# Seed Gaming Mode desktop shortcut + powerdevil user config
install -d "$ROOT/home/steam/Desktop" "$ROOT/home/steam/.config"
cp -a "$ROOT/usr/share/applications/steamos-gamemode.desktop" \
  "$ROOT/home/steam/Desktop/steamos-gamemode.desktop"
chmod 0755 "$ROOT/home/steam/Desktop/steamos-gamemode.desktop"
if [[ -f "$ROOT/usr/share/applications/steambp.desktop" ]]; then
  cp -a "$ROOT/usr/share/applications/steambp.desktop" \
    "$ROOT/home/steam/Desktop/steambp.desktop"
  chmod 0755 "$ROOT/home/steam/Desktop/steambp.desktop"
fi
cp -a "$ROOT/etc/xdg/powerdevilrc" "$ROOT/home/steam/.config/powerdevilrc"
chown -R "${STEAM_UID}:${STEAM_GID}" \
  "$ROOT/home/steam/Desktop" "$ROOT/home/steam/.config/powerdevilrc"

# gtk icon cache (best effort)
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f "$ROOT/usr/share/icons/hicolor" 2>/dev/null || true
fi

# Apt polish inside chroot when resolv + network work
if [[ -x /usr/sbin/chroot || -x /usr/bin/chroot ]]; then
  CHROOT=$(command -v chroot)
  # DNS for chroot apt
  if [[ -f /etc/resolv.conf ]]; then
    cp -a /etc/resolv.conf "$ROOT/etc/resolv.conf.bak.polish" 2>/dev/null || true
    cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf" 2>/dev/null || true
  fi
  echo "==> chroot apt polish (may take a few minutes)"
  "$CHROOT" "$ROOT" bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y || true
    apt-get purge -y elisa haruna vim vim-runtime vim-common yad synaptic 2>/dev/null || true
    apt-get install -y --no-install-recommends \
      vlc vlc-plugin-base antimicrox \
      gamemode libgamemode0 libgamemodeauto0 \
      flatpak bubblewrap \
      plasma-discover plasma-discover-backend-flatpak \
      plasma-systemmonitor ksystemstats libksysguard-bin \
      libksysguard-data libksysguardsensors2 libksysguardsensorfaces2 \
      libksysguardsystemstats2 libksysguardformatter2 \
      qml6-module-org-kde-ksysguard \
      || true
    # Align ksysguard stack to whatever plasma-systemmonitor needs
    apt-get install -y --no-install-recommends \
      plasma-systemmonitor ksystemstats \
      "libksysguard*" "qml6-module-org-kde-ksysguard" 2>/dev/null || true
    if ! command -v brave-browser >/dev/null 2>&1 && [[ -f /tmp/build_files/30-brave-and-mozilla-repos.sh ]]; then
      true
    fi
    if ! command -v brave-browser >/dev/null 2>&1; then
      echo "WARN: brave still missing — run build_files/30 in chroot if needed"
    fi
    if command -v flatpak >/dev/null 2>&1; then
      flatpak remote-add --if-not-exists --system flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    fi
  ' || echo "WARN: chroot apt polish had errors (overlays still applied)"

  # Brave: copy stage 30 into chroot if available
  if [[ ! -x "$ROOT/usr/bin/brave-browser" && ! -x "$ROOT/opt/brave.com/brave/brave" ]]; then
    if [[ -f "$ROOT_DIR/build_files/30-brave-and-mozilla-repos.sh" ]]; then
      echo "==> installing Brave via stage 30 in chroot"
      cp "$ROOT_DIR/build_files/30-brave-and-mozilla-repos.sh" "$ROOT/tmp/30-brave.sh"
      "$CHROOT" "$ROOT" bash /tmp/30-brave.sh || echo "WARN: Brave install failed"
      rm -f "$ROOT/tmp/30-brave.sh"
    fi
  fi
fi

echo "OK: desktop polish applied on $ROOT"
echo "Reboot (or remount RO + reboot) and retest Gaming Mode power → sleep."
