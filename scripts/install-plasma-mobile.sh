#!/usr/bin/env bash
# Optional Plasma Mobile for SteamOS-Ubuntu (handheld).
#
# Does NOT change default boot (always Gaming Mode via steamos-force-gaming-boot).
# Switch to Desktop from Gaming Mode still opens Plasma Desktop (unchanged).
#
# Adds:
#   • plasma-mobile packages (apt)
#   • greetd hook → startplasma-mobile when session file says plasma-mobile
#   • Switch to Plasma Mobile (apps + desktop shortcut)
#   • Switch to Plasma Desktop (apps only, from mobile)
#   • Return to Gaming Mode (apps only, from mobile)
#
# Usage:
#   sudo ./scripts/install-plasma-mobile.sh
#   sudo ./scripts/install-plasma-mobile.sh uninstall
#   sudo ./scripts/install-plasma-mobile.sh /path/to/rootfs   # files only, no apt
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_vendor_dir() {
  local rootfs="${1:-/}"
  local candidates=(
    "${rootfs}/usr/share/plasma-mobile-steamos/packaged"
    "${SCRIPT_DIR}/../vendor/Plasma-Mobile"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "${c}/bin" && -f "${c}/launch-plasma-mobile.sh" ]]; then
      printf '%s\n' "$(cd "$c" && pwd)"
      return 0
    fi
  done
  return 1
}

log() { printf '==> [plasma-mobile] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root (sudo)"

ROOTFS="/"
ACTION=install
if [[ "${1:-}" == "uninstall" ]]; then
  ACTION=uninstall
elif [[ -n "${1:-}" && "${1:-}" != "install" && -d "${1}/usr" ]]; then
  ROOTFS="${1%/}"
fi

VENDOR="$(resolve_vendor_dir "$ROOTFS")" || die "Missing Plasma-Mobile payload (re-run install-vendor-arm-manager.sh)"

SHARE="${ROOTFS}/usr/share/plasma-mobile-steamos"
BIN="${ROOTFS}/usr/bin"
APPS="${ROOTFS}/usr/share/applications"

install_session_files() {
  log "Installing session hooks → ${SHARE}"
  install -d "${SHARE}/bin"
  install -m 0755 "${VENDOR}/launch-plasma-mobile.sh" "${SHARE}/launch-plasma-mobile.sh"
  install -m 0755 "${VENDOR}/bin/"* "${SHARE}/bin/"
  for script in steamos-plasma-end-session.sh steamos-plasma-to-mobile steamos-mobile-to-plasma steamos-mobile-to-gamescope; do
    install -m 0755 "${SHARE}/bin/${script}" "${BIN}/${script}"
  done
  install -m 0644 "${VENDOR}/applications/plasma-to-mobile.desktop" "${APPS}/plasma-to-mobile.desktop"
  install -m 0644 "${VENDOR}/applications/plasma-mobile-to-desktop.desktop" "${APPS}/plasma-mobile-to-desktop.desktop"
  install -m 0644 "${VENDOR}/applications/plasma-mobile-gamemode.desktop" "${APPS}/plasma-mobile-gamemode.desktop"

  if [[ "$ROOTFS" == "/" ]]; then
    steam_home="$(getent passwd steam 2>/dev/null | cut -d: -f6 || echo /home/steam)"
    desktop_dir="${steam_home}/Desktop"
    if id steam >/dev/null 2>&1; then
      desktop_dir="$(sudo -u steam xdg-user-dir DESKTOP 2>/dev/null || echo "${desktop_dir}")"
    fi
    install -d "$desktop_dir"
    install -m 0755 "${APPS}/plasma-to-mobile.desktop" "${desktop_dir}/plasma-to-mobile.desktop"
    chown steam:steam "${desktop_dir}/plasma-to-mobile.desktop" 2>/dev/null || true
    log "Desktop shortcut → ${desktop_dir}/plasma-to-mobile.desktop"
  fi
}

install_system_session_hooks() {
  resolve_system_file() {
    local relpath="$1"
    local base candidates=(
      "${SHARE}/packaged/system/${relpath}"
      "${SCRIPT_DIR}/../system_files/${relpath}"
    )
    local c
    for c in "${candidates[@]}"; do
      [[ -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
    done
    return 1
  }

  local greetd gamescope set_session autologin_wrapper autologin_unit
  greetd="$(resolve_system_file "usr/local/bin/steamos-greetd-session")" \
    || die "Missing steamos-greetd-session payload (re-run install-vendor-arm-manager.sh)"
  gamescope="$(resolve_system_file "usr/bin/gamescope-session" || true)"
  set_session="$(resolve_system_file "usr/lib/steamos/steam-set-session" || true)"
  session_select="$(resolve_system_file "usr/bin/steamos-session-select" || true)"
  autologin_wrapper="$(resolve_system_file "usr/libexec/steamos-ubuntu/steamos-schedule-gaming-next-login.sh" || true)"
  autologin_unit="$(resolve_system_file "usr/lib/systemd/user/steamos-gamescope-autologin.service" || true)"

  log "Updating greetd session launcher (Plasma Mobile hook)"
  install -D -m 0755 "$greetd" "${ROOTFS}/usr/local/bin/steamos-greetd-session"
  [[ -n "$gamescope" ]] && install -D -m 0755 "$gamescope" "${ROOTFS}/usr/bin/gamescope-session"
  [[ -n "$set_session" ]] && install -D -m 0755 "$set_session" "${ROOTFS}/usr/lib/steamos/steam-set-session"
  [[ -n "$session_select" ]] && install -D -m 0755 "$session_select" "${ROOTFS}/usr/bin/steamos-session-select"
  [[ -n "$autologin_wrapper" ]] && install -D -m 0755 "$autologin_wrapper" \
    "${ROOTFS}/usr/libexec/steamos-ubuntu/steamos-schedule-gaming-next-login.sh"
  [[ -n "$autologin_unit" ]] && install -D -m 0644 "$autologin_unit" \
    "${ROOTFS}/usr/lib/systemd/user/steamos-gamescope-autologin.service"
}

uninstall_session_files() {
  log "Removing Plasma Mobile session integration (apt packages stay installed)"
  rm -f "${SHARE}/launch-plasma-mobile.sh"
  rm -rf "${SHARE}/bin"
  rm -f "${BIN}/steamos-plasma-to-mobile" "${BIN}/steamos-mobile-to-plasma" "${BIN}/steamos-mobile-to-gamescope"
  rm -f "${APPS}/plasma-to-mobile.desktop" "${APPS}/plasma-mobile-to-desktop.desktop" \
        "${APPS}/plasma-mobile-gamemode.desktop"
  if [[ "$ROOTFS" == "/" ]]; then
    steam_home="$(getent passwd steam 2>/dev/null | cut -d: -f6 || echo /home/steam)"
    rm -f "${steam_home}/Desktop/plasma-to-mobile.desktop" 2>/dev/null || true
  fi
}

install_plasma_mobile_packages() {
  export DEBIAN_FRONTEND=noninteractive
  log "Updating apt…"
  apt-get update -y || die "apt update failed"

  local candidates=(
    plasma-mobile
    plasma-phone-components
    plasma-mobile-settings
    maliit-framework
    maliit-keyboard
    qml6-module-org-kde-kirigamiaddons-components
    qml-module-org-kde-kirigamiaddons-components
  )
  local pkgs=() p
  for p in "${candidates[@]}"; do
    if apt-cache show "$p" >/dev/null 2>&1; then
      pkgs+=("$p")
    else
      log "skip (not in repos): $p"
    fi
  done

  if ((${#pkgs[@]} == 0)); then
    die "No plasma-mobile packages in apt. Ports mirror may not ship PM yet."
  fi

  log "Installing: ${pkgs[*]}"
  apt-get install -y --no-install-recommends "${pkgs[@]}" || {
    log "WARN: some packages failed — checking for startplasma-mobile anyway"
  }

  if ! command -v startplasmamobile >/dev/null 2>&1 \
      && ! command -v startplasma-mobile-wayland >/dev/null 2>&1 \
      && ! command -v startplasma-mobile >/dev/null 2>&1; then
    die "Plasma Mobile start command missing after install."
  fi
  log "Start command: $(command -v startplasmamobile 2>/dev/null || command -v startplasma-mobile-wayland 2>/dev/null || command -v startplasma-mobile)"
}

if [[ "$ACTION" == "uninstall" ]]; then
  uninstall_session_files
  log "Done."
  exit 0
fi

if [[ "$ROOTFS" == "/" ]]; then
  install_plasma_mobile_packages
  install_system_session_hooks
else
  log "Rootfs-only: skipping apt (${ROOTFS})"
  install_system_session_hooks
fi

install_session_files

if [[ "$ROOTFS" == "/" ]]; then
  cat <<'EOF'

Plasma Mobile installed (optional).

  Boot / Gaming Mode     — unchanged (gamescope after every reboot)
  Switch to Desktop      — still Plasma Desktop (Steam UI)
  Plasma Desktop         — «Switch to Plasma Mobile» (menu + desktop)
  Plasma Mobile          — «Switch to Plasma Desktop» / «Return to Gaming Mode»

Switch from Plasma Desktop when ready (no reboot needed).
EOF
fi
