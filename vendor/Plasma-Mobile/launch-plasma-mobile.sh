#!/usr/bin/env bash
# Launch Plasma Mobile under greetd (optional — installed by install-plasma-mobile.sh).
# Needs real systemd --user bus, same constraints as Plasma desktop in steamos-greetd-session.
set +e

LOG=/var/log/steamos-session.log
log() {
  printf 'plasma-mobile-launch: %s\n' "$*"
  printf 'plasma-mobile-launch: %s\n' "$*" >>"$LOG" 2>/dev/null || true
}

export HOME="${HOME:-/home/steam}"
export USER="${USER:-steam}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

pick_mobile_start() {
  local c
  for c in startplasmamobile startplasma-mobile-wayland startplasma-mobile; do
    if command -v "$c" >/dev/null 2>&1; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

START="$(pick_mobile_start)" || {
  log "ERROR: startplasma-mobile not found — run: sudo ./scripts/install-plasma-mobile.sh"
  exit 1
}

mkdir -p /tmp/.X11-unix
chmod 1777 /tmp /tmp/.X11-unix 2>/dev/null || true

unset STEAMOS_DBUS_RUN_SESSION || true
if [[ -S "${XDG_RUNTIME_DIR}/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

sleep 1

export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_DESKTOP=plasma-mobile
export DESKTOP_SESSION=plasma-mobile
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
unset STEAMOS_SESSION || true
unset DISPLAY WAYLAND_DISPLAY || true

mkdir -p "${HOME}/.config"
cat >"${HOME}/.config/plasma-welcomerc" <<'EOF'
[General]
LastSeenVersion=99.0.0
EOF

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP 2>/dev/null || true
  systemctl --user enable steamos-gamescope-autologin.service 2>/dev/null || true
  systemctl --user start steamos-gamescope-autologin.service 2>/dev/null || true
fi

log "starting Plasma Mobile ($START)"
if [[ -x /usr/lib/aarch64-linux-gnu/libexec/plasma-dbus-run-session-if-needed ]]; then
  exec /usr/lib/aarch64-linux-gnu/libexec/plasma-dbus-run-session-if-needed "$START"
fi
exec "$START"
