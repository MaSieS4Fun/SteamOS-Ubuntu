#!/usr/bin/env bash
# Install / uninstall Pi-Apps (https://pi-apps.io / Botspot/pi-apps).
#
# This image reports lsb_release ID "SteamOS-Ubuntu" while still being Ubuntu
# 26.04 Resolute. Pi-Apps only accepts Debian/Raspbian/Ubuntu IDs.
#
# Ubuntu 26.04 also moved apt mirrors to deb822
# (/etc/apt/sources.list.d/ubuntu.sources) and left /etc/apt/sources.list as a
# comment stub. Pi-Apps still expects classic deb lines there (and mentions
# sources.list in its "not compatible / missing repos" errors).
#
# We restore a classic sources.list mirroring ubuntu.sources, disable the
# deb822 file to avoid duplicate targets, and patch Pi-Apps to treat
# SteamOS-Ubuntu as Ubuntu. ~/pi-apps is kept (not a disposable build tree).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="pi-apps"
APP_NAME="Pi-Apps"
REPO_URL="https://github.com/Botspot/pi-apps.git"
PI_APPS_DIR="${MASI_PI_APPS_DIR:-$HOME/pi-apps}"
SOURCES_LIST="/etc/apt/sources.list"
SOURCES_BAK="/etc/apt/sources.list.masi-bak"
UBUNTU_SOURCES="/etc/apt/sources.list.d/ubuntu.sources"
# Must NOT live under sources.list.d — apt warns on unknown extensions there.
APT_BACKUP_DIR="/var/lib/emukitarm/apt"
UBUNTU_SOURCES_DISABLED="${APT_BACKUP_DIR}/ubuntu.sources"
# Legacy path left by older installs (triggers apt "invalid filename extension").
UBUNTU_SOURCES_DISABLED_LEGACY="/etc/apt/sources.list.d/ubuntu.sources.masi-disabled"
APT_QUIET_CONF="/etc/apt/apt.conf.d/90emukitarm-pi-apps-sources"

BUILD_DEPS=(
  git curl wget ca-certificates
  yad aria2 lsb-release apt-utils apt-transport-https gnupg
  imagemagick bc librsvg2-bin locales shellcheck wmctrl xdotool
  x11-utils rsync unzip debsums libgtk3-perl bzip2 zstd binutils
)

ubuntu_codename() {
  local codename=""
  # Prefer Ubuntu fields; fall back to VERSION_CODENAME.
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    codename="$(. /etc/os-release; echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
  fi
  if [[ -z "$codename" && -r /etc/lsb-release ]]; then
    # shellcheck disable=SC1091
    codename="$(. /etc/lsb-release; echo "${DISTRIB_CODENAME:-}")"
  fi
  [[ -n "$codename" ]] || masi_die "Could not determine Ubuntu codename"
  printf '%s\n' "$codename"
}

ensure_hostname_resolves() {
  # Empty /etc/hosts → "sudo: unable to resolve host …"
  local host
  host="$(hostname 2>/dev/null || true)"
  [[ -n "$host" ]] || return 0
  masi_ensure_sudo
  if [[ ! -s /etc/hosts ]] || ! grep -qE "[[:space:]]${host}([[:space:]]|$)" /etc/hosts 2>/dev/null; then
    masi_log "Fixing /etc/hosts for hostname ${host}..."
    masi_sudo tee /etc/hosts >/dev/null <<EOF
127.0.0.1 localhost
127.0.1.1 ${host}

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
  fi
}

ensure_apt_quiet_for_classic_sources() {
  # Classic .list sources (needed by Pi-Apps) make apt notice "modernize-sources".
  masi_ensure_sudo
  masi_sudo tee "$APT_QUIET_CONF" >/dev/null <<'EOF'
# EmuKitARM / Pi-Apps: keep classic sources.list; silence format notices on apt update.
APT::Get::Update::SourceListWarnings "false";
EOF
}

migrate_legacy_disabled_ubuntu_sources() {
  masi_ensure_sudo
  masi_sudo mkdir -p "$APT_BACKUP_DIR"
  if [[ -f "$UBUNTU_SOURCES_DISABLED_LEGACY" ]]; then
    masi_log "Moving legacy ${UBUNTU_SOURCES_DISABLED_LEGACY} out of sources.list.d..."
    if [[ ! -f "$UBUNTU_SOURCES_DISABLED" ]]; then
      masi_sudo mv -f "$UBUNTU_SOURCES_DISABLED_LEGACY" "$UBUNTU_SOURCES_DISABLED"
    else
      masi_sudo rm -f "$UBUNTU_SOURCES_DISABLED_LEGACY"
    fi
  fi
}

ubuntu_ports_mirror() {
  # aarch64 image uses ports.ubuntu.com (see ubuntu.sources).
  if [[ -f "$UBUNTU_SOURCES" ]] && grep -q 'ports.ubuntu.com' "$UBUNTU_SOURCES"; then
    echo "http://ports.ubuntu.com/ubuntu-ports"
  elif [[ -f "$UBUNTU_SOURCES_DISABLED" ]] && grep -q 'ports.ubuntu.com' "$UBUNTU_SOURCES_DISABLED"; then
    echo "http://ports.ubuntu.com/ubuntu-ports"
  elif [[ -f "$UBUNTU_SOURCES_DISABLED_LEGACY" ]] && grep -q 'ports.ubuntu.com' "$UBUNTU_SOURCES_DISABLED_LEGACY"; then
    echo "http://ports.ubuntu.com/ubuntu-ports"
  else
    echo "http://ports.ubuntu.com/ubuntu-ports"
  fi
}

ensure_classic_sources_list() {
  local codename mirror
  codename="$(ubuntu_codename)"
  mirror="$(ubuntu_ports_mirror)"

  masi_log "Ensuring classic ${SOURCES_LIST} for Pi-Apps (codename=${codename})..."
  masi_ensure_sudo
  ensure_hostname_resolves
  migrate_legacy_disabled_ubuntu_sources
  masi_sudo mkdir -p "$APT_BACKUP_DIR"

  if [[ ! -f "$SOURCES_BAK" ]]; then
    masi_sudo cp -a "$SOURCES_LIST" "$SOURCES_BAK"
  fi

  # Disable deb822 ubuntu.sources so apt does not see duplicate targets.
  # Keep the backup outside sources.list.d (apt warns on unknown extensions there).
  if [[ -f "$UBUNTU_SOURCES" ]]; then
    masi_log "Disabling deb822 ${UBUNTU_SOURCES} → ${UBUNTU_SOURCES_DISABLED}"
    masi_sudo mv -f "$UBUNTU_SOURCES" "$UBUNTU_SOURCES_DISABLED"
  fi

  masi_sudo tee "$SOURCES_LIST" >/dev/null <<EOF
# Written by EmuKitARM for Pi-Apps compatibility.
# Mirrors the previous deb822 ubuntu.sources entries for ${codename}.
# Original stub saved as ${SOURCES_BAK}; ubuntu.sources → ${UBUNTU_SOURCES_DISABLED}

deb ${mirror} ${codename} main restricted universe multiverse
deb ${mirror} ${codename}-updates main restricted universe multiverse
deb ${mirror} ${codename}-security main restricted universe multiverse
deb ${mirror} ${codename}-backports main restricted universe multiverse
EOF

  ensure_apt_quiet_for_classic_sources
  masi_sudo apt-get update -y
}

restore_apt_sources() {
  masi_ensure_sudo
  migrate_legacy_disabled_ubuntu_sources
  if [[ -f "$UBUNTU_SOURCES_DISABLED" && ! -f "$UBUNTU_SOURCES" ]]; then
    masi_log "Restoring ${UBUNTU_SOURCES}"
    masi_sudo mv -f "$UBUNTU_SOURCES_DISABLED" "$UBUNTU_SOURCES"
  fi
  if [[ -f "$SOURCES_BAK" ]]; then
    masi_log "Restoring original ${SOURCES_LIST}"
    masi_sudo mv -f "$SOURCES_BAK" "$SOURCES_LIST"
  fi
  masi_sudo rm -f "$APT_QUIET_CONF"
  masi_sudo apt-get update -y || true
}

patch_pi_apps_for_sm8550() {
  local api="${1}/api"
  [[ -f "$api" ]] || masi_die "Missing ${api}"

  masi_log "Patching Pi-Apps OS detection (SteamOS-Ubuntu → Ubuntu)..."
  python3 - "$api" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = "MasiScript: SteamOS-Ubuntu is Ubuntu"
if marker in text:
    print("Pi-Apps OS patch already present", file=sys.stderr)
    raise SystemExit(0)

# Remap after all lsb_release / upstream-release branches finish.
anchor = (
    "  fi\n"
    "fi\n"
    "\n"
    "# add CPU op-modes for all scripts to use\n"
)
remap = (
    "  fi\n"
    "fi\n"
    "\n"
    "# MasiScript: SteamOS-Ubuntu is Ubuntu 26.04 Resolute branding\n"
    "if [ \"$__os_id\" = \"SteamOS-Ubuntu\" ] || [ \"$__os_id\" = \"steamos-ubuntu\" ]; then\n"
    "  export __os_id=\"Ubuntu\"\n"
    "  export __os_desc=\"Ubuntu $__os_release\"\n"
    "fi\n"
    "\n"
    "# add CPU op-modes for all scripts to use\n"
)
if anchor not in text:
    sys.stderr.write("Could not find OS-detection / CPU-op-modes anchor in api\n")
    sys.exit(1)
text = text.replace(anchor, remap, 1)

# Accept SteamOS-Ubuntu in the supported-ID check (belt and suspenders).
old = (
    "  elif ([ -z \"$__os_original_id\" ] && ! ([ \"$__os_id\" == \"Debian\" ] || "
    "[ \"$__os_id\" == \"Raspbian\" ] || [ \"$__os_id\" == \"Ubuntu\" ]));then\n"
    "    echo \"Pi-Apps is not supported on $__os_desc, Pi-Apps is only officially supported "
    "on the latest two LTS releases of Raspberry Pi OS, Raspbian, Debian, and Ubuntu.\"\n"
    "    return 1\n"
)
new = (
    "  # MasiScript: SteamOS-Ubuntu is Ubuntu\n"
    "  elif ([ -z \"$__os_original_id\" ] && ! ([ \"$__os_id\" == \"Debian\" ] || "
    "[ \"$__os_id\" == \"Raspbian\" ] || [ \"$__os_id\" == \"Ubuntu\" ] || "
    "[ \"$__os_id\" == \"SteamOS-Ubuntu\" ] || [ \"$__os_id\" == \"steamos-ubuntu\" ]));then\n"
    "    echo \"Pi-Apps is not supported on $__os_desc, Pi-Apps is only officially supported "
    "on the latest two LTS releases of Raspberry Pi OS, Raspbian, Debian, and Ubuntu.\"\n"
    "    return 1\n"
)
if old not in text:
    sys.stderr.write("Could not find is_supported_system ID check to patch\n")
    sys.exit(1)
text = text.replace(old, new, 1)

# Treat SteamOS-Ubuntu like Ubuntu for the default-repos sources.list check.
old2 = (
    "  elif [ \"$__os_id\" == \"Ubuntu\" ] && ! ( echo \"$DEFAULT_REPOS\" | "
    "grep \"$__os_codename \" | awk '{if ($3==\"main\" || $3==\"universe\") print $3 }' "
)
new2 = (
    "  elif { [ \"$__os_id\" == \"Ubuntu\" ] || [ \"$__os_id\" == \"SteamOS-Ubuntu\" ] || "
    "[ \"$__os_id\" == \"steamos-ubuntu\" ]; } && ! ( echo \"$DEFAULT_REPOS\" | "
    "grep \"$__os_codename \" | awk '{if ($3==\"main\" || $3==\"universe\") print $3 }' "
)
if old2 not in text:
    sys.stderr.write("Could not find Ubuntu DEFAULT_REPOS check to patch\n")
    sys.exit(1)
text = text.replace(old2, new2, 1)

path.write_text(text)
print("Pi-Apps api patched for SteamOS-Ubuntu", file=sys.stderr)
PY
}

finish_pi_apps_install() {
  # Replicate upstream install steps after the tree exists (avoid install's re-clone wipe).
  local dir="$1"

  mkdir -p "${HOME}/.local/share/applications" "${HOME}/Desktop" \
    "${HOME}/.local/share/icons" "${HOME}/.config/autostart"

  cat >"${HOME}/.local/share/applications/pi-apps.desktop" <<EOF
[Desktop Entry]
Name=Pi-Apps
Comment=Raspberry Pi App Store for open source projects
Exec=${dir}/gui
Icon=${dir}/icons/logo.png
Terminal=false
StartupWMClass=Pi-Apps
Type=Application
Categories=Utility;System;PackageManager;
StartupNotify=true
EOF
  chmod 755 "${HOME}/.local/share/applications/pi-apps.desktop"
  cp -f "${HOME}/.local/share/applications/pi-apps.desktop" "${HOME}/Desktop/"
  chmod 755 "${HOME}/Desktop/pi-apps.desktop"

  cp -f "${dir}/icons/logo.png" "${HOME}/.local/share/icons/pi-apps.png"
  cp -f "${dir}/icons/settings.png" "${HOME}/.local/share/icons/pi-apps-settings.png"

  cat >"${HOME}/.local/share/applications/pi-apps-settings.desktop" <<EOF
[Desktop Entry]
Name=Pi-Apps Settings
Comment=Configure Pi-Apps or create an App
Exec=${dir}/settings
Icon=${dir}/icons/settings.png
Terminal=false
StartupWMClass=Pi-Apps-Settings
Type=Application
Categories=Settings;
StartupNotify=true
EOF

  cat >"${HOME}/.config/autostart/pi-apps-updater.desktop" <<EOF
[Desktop Entry]
Name=Pi-Apps Updater
Exec=${dir}/updater onboot
Icon=${dir}/icons/logo.png
Terminal=false
StartupWMClass=Pi-Apps
Type=Application
X-GNOME-Autostart-enabled=true
Hidden=false
NoDisplay=false
EOF

  mkdir -p "${dir}/data/status" "${dir}/data/update-status" \
    "${dir}/data/preload" "${dir}/data/settings" "${dir}/data/categories"

  masi_log "Installing /usr/local/bin/pi-apps launcher..."
  masi_sudo tee /usr/local/bin/pi-apps >/dev/null <<EOF
#!/bin/bash
${dir}/gui "\$@"
EOF
  masi_sudo chmod +x /usr/local/bin/pi-apps

  masi_log "Checking Pi-Apps system support..."
  local errors=""
  if ! errors="$("${dir}/api" is_supported_system)"; then
    masi_die "Pi-Apps still reports unsupported system: ${errors}"
  fi

  if "${dir}/api" package_installed coreutils-from-uutils 2>/dev/null; then
    if ! "${dir}/api" package_is_new_enough rust-coreutils 0.8.0 2>/dev/null; then
      masi_log "Switching to GNU coreutils (uutils too old for Pi-Apps)..."
      masi_sudo apt-get -o DPkg::Lock::Timeout=-1 install \
        coreutils-from-gnu coreutils-from-uutils- --allow-remove-essential -y || true
      rm -rf "${dir}/data/preload/"*
    fi
  fi

  masi_log "Preloading Pi-Apps app list..."
  "${dir}/preload" yad &>/dev/null || true
  "${dir}/etc/runonce-entries" &>/dev/null || true

  if [[ ! -f "${dir}/data/announcements" ]] \
    || find "${dir}/data/announcements" -mtime +1 -print 2>/dev/null | grep -q .; then
    wget -qO "${dir}/data/announcements" \
      https://raw.githubusercontent.com/Botspot/pi-apps-announcements/main/message \
      || true
  fi
}

save_manifest() {
  mkdir -p "$MASI_MANIFESTS"
  cat >"${MASI_MANIFESTS}/${APP_ID}.txt" <<EOF
${PI_APPS_DIR}
/usr/local/bin/pi-apps
${HOME}/.local/share/applications/pi-apps.desktop
${HOME}/.local/share/applications/pi-apps-settings.desktop
${HOME}/Desktop/pi-apps.desktop
${HOME}/.config/autostart/pi-apps-updater.desktop
${SOURCES_BAK}
${UBUNTU_SOURCES_DISABLED}
EOF
  chmod 644 "${MASI_MANIFESTS}/${APP_ID}.txt"
}

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  if [[ -x "${PI_APPS_DIR}/uninstall" ]]; then
    # Upstream uninstall is interactive-ish; run non-fatal.
    bash "${PI_APPS_DIR}/uninstall" || true
  fi
  masi_ensure_sudo
  masi_sudo rm -f /usr/local/bin/pi-apps
  rm -f "${HOME}/.local/share/applications/pi-apps.desktop" \
    "${HOME}/.local/share/applications/pi-apps-settings.desktop" \
    "${HOME}/Desktop/pi-apps.desktop" \
    "${HOME}/.config/autostart/pi-apps-updater.desktop" \
    "${HOME}/.local/share/icons/pi-apps.png" \
    "${HOME}/.local/share/icons/pi-apps-settings.png"
  restore_apt_sources
  rm -f "${MASI_MANIFESTS}/${APP_ID}.txt"
  masi_log "Left Pi-Apps tree in place: ${PI_APPS_DIR} (delete manually if desired)."
  masi_log "=== ${APP_NAME} removed ==="
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} ==="
  masi_log "Tree: ${PI_APPS_DIR} (kept after install)"
  masi_log "OS ID from lsb_release: $(lsb_release -si 2>/dev/null || echo unknown) — mapped as Ubuntu."

  masi_ensure_sudo
  ensure_classic_sources_list
  masi_apt_install "${BUILD_DEPS[@]}"

  if [[ ! -d "${PI_APPS_DIR}/.git" ]]; then
    masi_log "Cloning ${REPO_URL} → ${PI_APPS_DIR}"
    rm -rf "$PI_APPS_DIR"
    git clone --depth 1 "$REPO_URL" "$PI_APPS_DIR"
  else
    masi_log "Updating existing ${PI_APPS_DIR}"
    git -C "$PI_APPS_DIR" fetch --depth 1 origin master \
      || git -C "$PI_APPS_DIR" fetch --depth 1 origin main \
      || true
    # Preserve user data/apps across update.
    local data_backup apps_backup
    data_backup="$(mktemp -d "${TMPDIR:-/tmp}/pi-apps-data.XXXXXX")"
    apps_backup="$(mktemp -d "${TMPDIR:-/tmp}/pi-apps-apps.XXXXXX")"
    [[ -d "${PI_APPS_DIR}/data" ]] && cp -a "${PI_APPS_DIR}/data/." "$data_backup/" || true
    [[ -d "${PI_APPS_DIR}/apps" ]] && cp -a "${PI_APPS_DIR}/apps/." "$apps_backup/" || true
    git -C "$PI_APPS_DIR" reset --hard FETCH_HEAD \
      || git -C "$PI_APPS_DIR" pull --ff-only \
      || true
    cp -af "${data_backup}/." "${PI_APPS_DIR}/data/" 2>/dev/null || true
    cp -af "${apps_backup}/." "${PI_APPS_DIR}/apps/" 2>/dev/null || true
    rm -rf "$data_backup" "$apps_backup"
  fi

  patch_pi_apps_for_sm8550 "$PI_APPS_DIR"
  finish_pi_apps_install "$PI_APPS_DIR"
  save_manifest

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Launch:  pi-apps"
  masi_log "Or:      ${PI_APPS_DIR}/gui"
  masi_log "Tree:    ${PI_APPS_DIR}"
  cat <<EOF

[EmuKitARM] WARNING — Pi-Apps
- OS ID SteamOS-Ubuntu is treated as Ubuntu 26.04 Resolute.
- /etc/apt/sources.list was rewritten to classic deb lines for Pi-Apps.
- deb822 ubuntu.sources was moved to /var/lib/emukitarm/apt/ (restored on uninstall).
- ~/pi-apps is kept so you can manage apps later.

EOF
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
