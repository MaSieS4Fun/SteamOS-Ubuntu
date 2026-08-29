#!/usr/bin/env bash
# Polish Plasma desktop: apps in/out, Flatpak Flathub, Discover-only, sensors aligned.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export UCF_FORCE_CONFFOLD=1
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
log() { printf '==> [desktop] %s\n' "$*"; }

log "Remove unwanted desktop apps"
apt-get purge "${APT_OPTS[@]}" \
  elisa haruna \
  vim vim-runtime vim-common \
  yad \
  2>/dev/null || true
# Emoji selector (Plasma) — remove launcher; keep fonts
rm -f /usr/share/applications/org.kde.plasma.emojier.desktop 2>/dev/null || true
# Icon Browser (yad)
rm -f /usr/share/applications/yad-icon-browser.desktop 2>/dev/null || true
# Kubuntu Focus / Kubuntu website desktop junk (do not recreate kubuntu wrappers)
rm -f \
  /usr/share/applications/org.kfocus.web.howtos.desktop \
  /usr/share/applications/org.kubuntu.web.home.desktop \
  /usr/share/applications/org.kubuntu.restore-desktop-links.desktop \
  /usr/share/applications/org.kubuntu.driver-manager.desktop \
  /usr/share/applications/org.kubuntu.manage-software.desktop \
  /usr/share/applications/software-properties-drivers-lxqt.desktop \
  /usr/share/applications/software-properties-lxqt.desktop \
  /usr/bin/kubuntu-restore-desktop-links \
  /usr/bin/kubuntu-manage-software \
  2>/dev/null || true
apt-get purge "${APT_OPTS[@]}" synaptic 2>/dev/null || true

log "Install desktop apps (vlc, antimicrox, discover flatpak, sensors, maliit)"
apt-get install "${APT_OPTS[@]}" --no-install-recommends \
  vlc vlc-plugin-base \
  antimicrox \
  gamemode libgamemode0 libgamemodeauto0 \
  flatpak bubblewrap \
  plasma-discover plasma-discover-backend-flatpak plasma-discover-backend-fwupd \
  plasma-systemmonitor ksystemstats \
  libksysguard-bin libksysguard-data \
  libksysguardsensors2 libksysguardsensorfaces2 \
  libksysguardsystemstats2 libksysguardformatter2 \
  qml6-module-org-kde-ksysguard \
  maliit-keyboard \
  maliit-server-qt5 maliit-inputcontext-qt5 libmaliit-plugins2 \
  maliit-server-qt6 maliit-inputcontext-qt6 libmaliit6-plugins2 \
  || true

# Version skew (e.g. systemmonitor 6.6.6 vs libksysguard 6.6.5) → empty gauges / Fix does nothing
log "Align plasma-systemmonitor + libksysguard stack"
apt-get install "${APT_OPTS[@]}" --no-install-recommends --allow-downgrades \
  plasma-systemmonitor ksystemstats \
  libksysguard-bin libksysguard-data \
  libksysguardsensors2 libksysguardsensorfaces2 \
  libksysguardsystemstats2 libksysguardformatter2 \
  qml6-module-org-kde-ksysguard \
  2>/dev/null || true
# Pull any newer matching set from the same suite
apt-get install "${APT_OPTS[@]}" --no-install-recommends \
  plasma-systemmonitor/$(. /etc/os-release; echo "${VERSION_CODENAME:-resolute}") \
  2>/dev/null || true

log "Flatpak Flathub remote (system)"
if command -v flatpak >/dev/null 2>&1; then
  flatpak remote-add --if-not-exists --system flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
fi

# Brave must exist (stage 30); re-run install if missing
if ! command -v brave-browser >/dev/null 2>&1 && ! [[ -x /opt/brave.com/brave/brave ]]; then
  log "brave-browser missing — retrying apt install"
  apt-get install "${APT_OPTS[@]}" --no-install-recommends brave-browser \
    || log "WARN: brave-browser still missing (repo/network)"
fi

# Deck icon cache
if [[ -f /usr/share/icons/hicolor/scalable/apps/steamos-gamemode.svg ]]; then
  gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
fi

# Clean steam Desktop of Kubuntu links; seed Gaming Mode + PowerDevil sleep defaults
STEAM_HOME=/home/steam
if [[ -d "$STEAM_HOME" ]]; then
  install -d "$STEAM_HOME/Desktop" "$STEAM_HOME/.config"
  rm -f "$STEAM_HOME/Desktop/"*howto* "$STEAM_HOME/Desktop/"*HOW* \
    "$STEAM_HOME/Desktop/"*kubuntu* "$STEAM_HOME/Desktop/"*Kubuntu* \
    "$STEAM_HOME/Desktop/org.kfocus."* "$STEAM_HOME/Desktop/org.kubuntu."* \
    2>/dev/null || true
  rm -f "$STEAM_HOME/Desktop/steambp.desktop" 2>/dev/null || true
  for desk in steamos-gamemode.desktop steamos-gaming-mode.desktop steambp.desktop; do
    if [[ -f "/usr/share/applications/${desk}" ]]; then
      cp -a "/usr/share/applications/${desk}" "$STEAM_HOME/Desktop/${desk}"
      chmod 0755 "$STEAM_HOME/Desktop/${desk}" || true
    fi
  done
  if [[ -f /etc/xdg/powerdevilrc ]]; then
    cp -a /etc/xdg/powerdevilrc "$STEAM_HOME/.config/powerdevilrc"
  fi
  # Screen lock OFF — handheld has no keyboard at kscreenlocker_greet
  if [[ -f /etc/xdg/kscreenlockerrc ]]; then
    cp -a /etc/xdg/kscreenlockerrc "$STEAM_HOME/.config/kscreenlockerrc"
  else
    cat >"$STEAM_HOME/.config/kscreenlockerrc" <<'EOF'
[Daemon]
Autolock=false
LockOnStartup=false
LockOnResume=false
Timeout=0
RequirePassword=false
EOF
  fi
  STEAM_UID="$(id -u steam 2>/dev/null || true)"
  STEAM_GID="$(id -g steam 2>/dev/null || true)"
  if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
    chown -R "${STEAM_UID}:${STEAM_GID}" "$STEAM_HOME/Desktop" "$STEAM_HOME/.config" 2>/dev/null || true
  else
    chown -R steam:steam "$STEAM_HOME/Desktop" "$STEAM_HOME/.config" 2>/dev/null || true
  fi
fi

# GPU perf oneshot removed — GMU stalls fixed in vendor/kernel (patches 1030/1031)

log "Desktop polish done"
