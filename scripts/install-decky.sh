#!/usr/bin/env bash
# Install / verify / uninstall Decky PluginLoader on SteamOS-Ubuntu (aarch64).
#
# PluginLoader upstream is x86_64-only (no native aarch64 build). On this handheld
# it runs via binfmt — Box64 or FEXEmu must be installed first.
# This image uses user "steam" (not Valve's "deck"); upstream installer is patched.
#
# Usage (Desktop / konsole — asks for sudo once):
#   ./scripts/install-decky.sh
#   /usr/bin/install-decky
#   sudo ./scripts/install-decky.sh install [stable|beta]
#   sudo ./scripts/install-decky.sh verify|uninstall
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_USER="${SUDO_USER:-${USER:-}}"
[[ -n "$REAL_USER" && "$REAL_USER" != "root" ]] || REAL_USER="$(logname 2>/dev/null || true)"
REAL_USER="${REAL_USER:-steam}"
REAL_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6 || true)"
REAL_HOME="${REAL_HOME:-/home/${REAL_USER}}"
REAL_UID="$(id -u "$REAL_USER" 2>/dev/null || echo 1000)"
REAL_GID="$(id -g "$REAL_USER" 2>/dev/null || echo 1000)"

if [[ -d "${_SCRIPT_DIR}/../vendor" && -f "${_SCRIPT_DIR}/../create-image.sh" ]]; then
  ROOT_DIR="$(cd "${_SCRIPT_DIR}/.." && pwd)"
else
  ROOT_DIR=""
fi

DECKY_INSTALL_URL="${DECKY_INSTALL_URL:-https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/user_install_script.sh}"
DECKY_BRANCH="${DECKY_BRANCH:-}"  # release | prerelease (set by menu or CLI)
HOMEBREW_ROOT="${REAL_HOME}/homebrew"
PLUGIN_LOADER="${HOMEBREW_ROOT}/services/PluginLoader"
LOADER_VERSION_FILE="${HOMEBREW_ROOT}/services/.loader.version"
LOADER_SETTINGS="${HOMEBREW_ROOT}/settings/loader.json"
PLUGIN_UNIT="/etc/systemd/system/plugin_loader.service"
LSFG_DROPINS="${ROOT_DIR}/vendor/system-fixes/LSFG-VK/plugin_loader.service.d"
DECKY_LOADER_REPO="SteamDeckHomebrew/decky-loader"

log()  { printf '==> [decky] %s\n' "$*" >&2; }
warn() { printf '==> [decky] WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# systemctl via the user's Konsole session bus triggers polkit (reload-daemon,
# manage-unit-files) even when the script was started with sudo. Always talk to
# pid 1 as root without the session bus.
systemctl_root() {
  env -u DBUS_SESSION_BUS_ADDRESS systemctl --no-ask-password "$@"
}

systemctl_user() {
  sudo -u "$REAL_USER" \
    env -u DBUS_SESSION_BUS_ADDRESS \
    "XDG_RUNTIME_DIR=/run/user/${REAL_UID}" \
    systemctl --user --no-ask-password "$@" 2>/dev/null || true
}

ask_yes_no() {
  local prompt="$1" default="${2:-n}" ans
  local hint="[y/N]"
  [[ "$default" == "y" ]] && hint="[Y/n]"
  while true; do
    read -r -p "${prompt} ${hint} " ans || return 1
    ans="${ans,,}"
    [[ -z "$ans" ]] && ans="$default"
    case "$ans" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
    esac
  done
}

box64_detected() {
  command -v box64 >/dev/null 2>&1 && return 0
  [[ -f /etc/binfmt.d/box64.conf || -f /usr/lib/binfmt.d/box64.conf ]] && return 0
  [[ -x /usr/local/bin/box64 ]] && return 0
  return 1
}

fex_detected() {
  command -v FEX >/dev/null 2>&1 && return 0
  [[ -f /usr/lib/binfmt.d/FEX-x86_64.conf ]] && return 0
  [[ -f /usr/local/share/fex-emu/install_manifest.txt ]] && return 0
  return 1
}

decky_installed() {
  [[ -x "$PLUGIN_LOADER" ]] && return 0
  [[ -f "$PLUGIN_UNIT" ]] && return 0
  return 1
}

normalize_decky_branch() {
  case "${1,,}" in
    beta|prerelease|pre|b|2) printf '%s' "prerelease" ;;
    stable|release|estable|s|1|"") printf '%s' "release" ;;
    *) die "Unknown channel: $1 (use stable or beta)" ;;
  esac
}

branch_label() {
  case "$1" in
    prerelease) printf '%s' "Beta (prerelease)" ;;
    release)    printf '%s' "Stable (release)" ;;
    *)          printf '%s' "$1" ;;
  esac
}

show_installed_variant() {
  local ver branch_num branch_name=""
  if [[ -f "$LOADER_VERSION_FILE" ]]; then
    ver="$(tr -d '\n' <"$LOADER_VERSION_FILE")"
    log "PluginLoader version: ${ver}"
    if [[ "$ver" == *pre* ]]; then
      branch_name="Beta (prerelease)"
    elif [[ -z "$branch_name" ]]; then
      branch_name="Stable (release)"
    fi
  fi
  if [[ -f "$LOADER_SETTINGS" ]] && command -v jq >/dev/null 2>&1; then
    branch_num="$(jq -r '.branch // empty' "$LOADER_SETTINGS" 2>/dev/null || true)"
    case "$branch_num" in
      0) branch_name="Stable (release)" ;;
      1) branch_name="Beta (prerelease)" ;;
      2) branch_name="Testing (experimental)" ;;
    esac
  elif [[ -f "$LOADER_SETTINGS" ]]; then
    grep -q '"branch"[[:space:]]*:[[:space:]]*1' "$LOADER_SETTINGS" 2>/dev/null \
      && branch_name="Beta (prerelease)"
    grep -q '"branch"[[:space:]]*:[[:space:]]*0' "$LOADER_SETTINGS" 2>/dev/null \
      && branch_name="Stable (release)"
  fi
  if [[ -n "$branch_name" ]]; then
    log "Installed channel: ${branch_name}"
  else
    warn "Installed channel: unknown (missing .loader.version or settings/loader.json)"
  fi
  if [[ -x "$PLUGIN_LOADER" ]] && command -v file >/dev/null 2>&1; then
    log "Binary: $(file -b "$PLUGIN_LOADER" 2>/dev/null || true)"
    if file -b "$PLUGIN_LOADER" 2>/dev/null | grep -qi 'x86-64'; then
      if box64_detected; then
        log "Emulation: Box64 (binfmt)"
      elif fex_detected; then
        log "Emulation: FEXEmu (binfmt)"
      else
        warn "PluginLoader is x86_64 — cannot run on aarch64 without Box64 or FEX"
      fi
    fi
  fi
}

ask_decky_channel() {
  [[ -n "$DECKY_BRANCH" ]] && return 0
  local choice
  echo
  echo "Decky PluginLoader channel:"
  echo "  1) Stable   (release — recommended; requires Box64 or FEX)"
  echo "  2) Beta     (prerelease — newer, may break; requires Box64 or FEX)"
  echo
  read -r -p "Choose [1]: " choice
  case "${choice:-1}" in
    2|beta|prerelease|pre|b) DECKY_BRANCH="prerelease" ;;
    *) DECKY_BRANCH="release" ;;
  esac
  export DECKY_BRANCH
  log "Selected channel: $(branch_label "$DECKY_BRANCH")"
}

require_x86_emulator() {
  local has_box has_fex
  has_box=0 has_fex=0
  box64_detected && has_box=1
  fex_detected && has_fex=1

  if (( has_box == 0 && has_fex == 0 )); then
    die "$(cat <<EOF

Decky needs an x86_64 emulator (Box64 or FEXEmu) to run PluginLoader.

Install one from ARM-Manager:
  • Box64   — recommended for Decky
  • FEXEmu  — may be unstable with Decky

Installation cancelled.
EOF
)"
  fi

  if (( has_box == 1 && has_fex == 1 )); then
    warn "Both Box64 and FEXEmu are installed — binfmt conflict."
    warn "For Decky, uninstall FEX and use Box64 only."
    if ! ask_yes_no "Continue with Decky anyway?"; then
      log "Cancelled."
      exit 0
    fi
  elif (( has_fex == 1 && has_box == 0 )); then
    warn "Only FEXEmu detected. Decky (x86_64 PluginLoader) may be unstable with FEX."
    warn "Box64 is recommended for Decky."
    if ! ask_yes_no "Install Decky with FEX anyway?"; then
      log "Cancelled. Install Box64 from ARM-Manager and try again."
      exit 0
    fi
  else
    log "Box64 detected — recommended emulator for Decky."
  fi
}

ensure_decky_deps() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y -o Acquire::Retries=3 2>/dev/null || true
  apt-get install -y --no-install-recommends curl ca-certificates jq git python3 unzip \
    2>/dev/null || warn "Some optional Decky deps failed to install (continuing)"
}

apply_decky_dropins() {
  local drop src
  install -d -m 0755 /etc/systemd/system/plugin_loader.service.d
  for drop in fast-stop.conf fex-steam-rootfs.conf steamos-ubuntu.conf; do
    src=""
    if [[ -n "$ROOT_DIR" && -f "${LSFG_DROPINS}/${drop}" ]]; then
      src="${LSFG_DROPINS}/${drop}"
    elif [[ -f "${_SCRIPT_DIR}/../vendor/system-fixes/LSFG-VK/plugin_loader.service.d/${drop}" ]]; then
      src="${_SCRIPT_DIR}/../vendor/system-fixes/LSFG-VK/plugin_loader.service.d/${drop}"
    elif [[ -f "${_SCRIPT_DIR}/../system_files/etc/systemd/system/plugin_loader.service.d/${drop}" ]]; then
      src="${_SCRIPT_DIR}/../system_files/etc/systemd/system/plugin_loader.service.d/${drop}"
    fi
    [[ -n "$src" ]] || continue
    install -D -m 0644 "$src" "/etc/systemd/system/plugin_loader.service.d/${drop}"
    log "Installed plugin_loader drop-in: ${drop}"
  done
  if [[ -f "${_SCRIPT_DIR}/../system_files/etc/sudoers.d/99-steam-decky-plugin-loader" ]]; then
    install -D -m 0440 \
      "${_SCRIPT_DIR}/../system_files/etc/sudoers.d/99-steam-decky-plugin-loader" \
      /etc/sudoers.d/99-steam-decky-plugin-loader
  fi
}

fetch_decky_release_meta() {
  local branch="$1"
  local json version url
  json="$(curl -fsSL "https://api.github.com/repos/${DECKY_LOADER_REPO}/releases")" \
    || die "Failed to fetch decky-loader releases (network?)"
  if [[ "$branch" == "prerelease" ]]; then
    version="$(jq -r '[.[] | select(.prerelease == true)][0].tag_name // empty' <<<"$json")"
    url="$(jq -r '[.[] | select(.prerelease == true)][0].assets[]? | select(.name == "PluginLoader") | .browser_download_url // empty' <<<"$json" | head -1)"
  else
    version="$(jq -r '[.[] | select(.prerelease == false)][0].tag_name // empty' <<<"$json")"
    url="$(jq -r '[.[] | select(.prerelease == false)][0].assets[]? | select(.name == "PluginLoader") | .browser_download_url // empty' <<<"$json" | head -1)"
  fi
  [[ -n "$version" ]] || die "No decky-loader release for channel: ${branch}"
  [[ -n "$url" ]] || die "PluginLoader asset missing in release ${version}"
  printf '%s\n' "$version"
  printf '%s\n' "$url"
}


ensure_cef_remote_debugging() {
  local steam_root="${REAL_HOME}/.local/share/Steam"
  mkdir -p "$steam_root"
  touch "${steam_root}/.cef-enable-remote-debugging"
  chown "${REAL_UID}:${REAL_GID}" "${steam_root}/.cef-enable-remote-debugging" 2>/dev/null || true
  log "Steam CEF remote-debugging marker enabled (Decky → localhost:8080)"
}

install_decky_native() {
  local branch="${DECKY_BRANCH:-release}"
  local version download_url unit_tmp branch_num
  local services_dir="${HOMEBREW_ROOT}/services"
  local settings_dir="${HOMEBREW_ROOT}/settings"
  local meta

  log "Installing Decky PluginLoader ($(branch_label "$branch")) — native path (no polkit prompts)"

  mapfile -t meta < <(fetch_decky_release_meta "$branch")
  version="${meta[0]}"
  download_url="${meta[1]}"

  mkdir -p "$services_dir" "$settings_dir" "${services_dir}/.systemd"
  chown "${REAL_UID}:${REAL_GID}" "${HOMEBREW_ROOT}" "$services_dir" "$settings_dir" 2>/dev/null || true

  log "Downloading PluginLoader ${version}..."
  curl -fsSL -o "${PLUGIN_LOADER}.new" "$download_url" \
    || die "Failed to download PluginLoader"
  chmod 755 "${PLUGIN_LOADER}.new"
  mv -f "${PLUGIN_LOADER}.new" "${PLUGIN_LOADER}"
  printf '%s\n' "$version" >"$LOADER_VERSION_FILE"

  branch_num=0
  [[ "$branch" == "prerelease" ]] && branch_num=1
  printf '{"branch": %s}\n' "$branch_num" >"$LOADER_SETTINGS"

  unit_tmp="$(mktemp)"
  curl -fsSL \
    "https://raw.githubusercontent.com/${DECKY_LOADER_REPO}/main/dist/plugin_loader-${branch}.service" \
    -o "$unit_tmp" || {
    rm -f "$unit_tmp"
    die "Failed to download plugin_loader-${branch}.service"
  }
  sed \
    -e "s|\${HOMEBREW_FOLDER}|${HOMEBREW_ROOT}|g" \
    -e "s|/home/deck|${REAL_HOME}|g" \
    "$unit_tmp" >"$PLUGIN_UNIT"
  rm -f "$unit_tmp"
  install -m 0644 "$PLUGIN_UNIT" "${services_dir}/.systemd/plugin_loader-${branch}.service"

  fix_homebrew_ownership
  apply_decky_dropins
  enable_plugin_loader_service
  log "Decky ${version} installed for user ${REAL_USER}"
}

enable_plugin_loader_service() {
  systemctl_user disable --now plugin_loader.service
  systemctl_root disable plugin_loader.service 2>/dev/null || true
  systemctl_root stop plugin_loader.service 2>/dev/null || true
  systemctl_root daemon-reload
  systemctl_root enable plugin_loader.service
  systemctl_root start plugin_loader.service
}

fix_plugin_loader_unit() {
  [[ -f "$PLUGIN_UNIT" ]] || return 0
  if grep -q '/home/deck' "$PLUGIN_UNIT" 2>/dev/null; then
    log "Patching plugin_loader.service paths deck → ${REAL_USER}"
    sed -i "s|/home/deck|${REAL_HOME}|g" "$PLUGIN_UNIT"
  fi
  systemctl_root daemon-reload
}

fix_homebrew_ownership() {
  [[ -d "$HOMEBREW_ROOT" ]] || return 0
  chown -R "${REAL_UID}:${REAL_GID}" "$HOMEBREW_ROOT"
}

verify_decky() {
  local ok=0
  echo
  log "Verifying Decky..."
  show_installed_variant

  if [[ -x "$PLUGIN_LOADER" ]]; then
    log "OK: PluginLoader present at ${PLUGIN_LOADER}"
    if command -v file >/dev/null 2>&1; then
      file "$PLUGIN_LOADER" || true
    fi
  else
    warn "PluginLoader missing or not executable: ${PLUGIN_LOADER}"
    ok=1
  fi

  fix_plugin_loader_unit
  apply_decky_dropins
  fix_homebrew_ownership
  enable_plugin_loader_service

  if systemctl_root is-active --quiet plugin_loader.service; then
    log "OK: plugin_loader.service is active"
  else
    warn "plugin_loader.service is not active"
    journalctl -u plugin_loader.service -n 25 --no-pager 2>/dev/null || true
    ok=1
  fi

  if (( ok == 0 )); then
    log "Decky ready. Open Steam (Gaming mode) and open the Decky menu (⋯)."
    return 0
  fi
  warn "Decky installed but verification failed — check journalctl -u plugin_loader.service"
  return 1
}

do_install() {
  require_x86_emulator
  ask_decky_channel
  ensure_decky_deps
  apply_decky_dropins

  if decky_installed; then
    warn "Decky appears already installed in ${HOMEBREW_ROOT}"
    show_installed_variant
    if ! ask_yes_no "Reinstall / switch channel?"; then
      verify_decky || true
      exit 0
    fi
  fi

  ensure_cef_remote_debugging
  install_decky_native
  if [[ -x /usr/libexec/steamos-ubuntu/sync-decky-bundled-plugins.sh ]]; then
    log "Installing bundled Decky plugins (SteamOS-Ubuntu)"
    STEAM_USER="$REAL_USER" STEAM_HOME="$REAL_HOME" \
      /usr/libexec/steamos-ubuntu/sync-decky-bundled-plugins.sh || \
      warn "Bundled plugin sync failed (non-fatal)"
  fi
  fix_homebrew_ownership
  verify_decky
  echo
  show_installed_variant
}

do_uninstall() {
  if ! decky_installed; then
    die "Decky does not appear to be installed."
  fi
  if ! ask_yes_no "Uninstall Decky (service + ~/homebrew)?" "n"; then
    log "Cancelled."
    exit 0
  fi
  systemctl_user disable --now plugin_loader.service
  systemctl_root disable --now plugin_loader.service 2>/dev/null || true
  rm -f "$PLUGIN_UNIT" \
    /etc/systemd/system/multi-user.target.wants/plugin_loader.service \
    2>/dev/null || true
  rm -rf /etc/systemd/system/plugin_loader.service.d 2>/dev/null || true
  systemctl_root daemon-reload
  rm -rf "$HOMEBREW_ROOT"
  log "Decky uninstalled."
}

main_menu() {
  local choice
  echo
  echo "Decky PluginLoader"
  echo "  1) Install stable   (release — requires Box64 or FEX)"
  echo "  2) Install beta     (prerelease — requires Box64 or FEX)"
  echo "  3) Verify           (channel + service)"
  echo "  4) Uninstall"
  echo "  0) Exit"
  echo
  read -r -p "Choice: " choice
  case "$choice" in
    1) DECKY_BRANCH=release; do_install ;;
    2) DECKY_BRANCH=prerelease; do_install ;;
    3) verify_decky ;;
    4) do_uninstall ;;
    0|"") log "Bye."; exit 0 ;;
    *) die "Unknown choice: $choice" ;;
  esac
}

[[ "$(uname -m)" == "aarch64" ]] || die "Decky on this image targets aarch64 hosts + an x86_64 emulator"
log "Decky user: ${REAL_USER} (${REAL_HOME})"

ACTION="${1:-}"
CHANNEL_ARG="${2:-}"
case "$CHANNEL_ARG" in
  stable|beta|release|prerelease)
    DECKY_BRANCH="$(normalize_decky_branch "$CHANNEL_ARG")"
    export DECKY_BRANCH
    ;;
esac

case "$ACTION" in
  install)        do_install ;;
  install-stable) DECKY_BRANCH=release; export DECKY_BRANCH; do_install ;;
  install-beta)   DECKY_BRANCH=prerelease; export DECKY_BRANCH; do_install ;;
  verify|status)  verify_decky ;;
  uninstall|remove) do_uninstall ;;
  ""|-i|--interactive) main_menu ;;
  -h|--help)
    cat <<EOF
Usage: $0 [install [stable|beta]|install-stable|install-beta|verify|uninstall]

  Prompts for sudo if not already root.

  install [stable|beta]   Pick channel; without arg asks in the menu
  install-stable          Stable channel (release)
  install-beta            Beta channel (prerelease)
  verify                  Show installed channel + service status
  uninstall               Remove service and ${REAL_HOME}/homebrew

On aarch64, PluginLoader is an x86_64 binary — Box64 or FEXEmu (binfmt) is required.
Box64 is usually more reliable; FEX may work but is less dependable.

Check installed channel: $0 verify
  • ${HOMEBREW_ROOT}/services/.loader.version
  • ${LOADER_SETTINGS} (branch: 0=stable, 1=beta)
EOF
    exit 0
    ;;
  *) die "Unknown argument: $ACTION (try --help)" ;;
esac
