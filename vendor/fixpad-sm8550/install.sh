#!/usr/bin/env bash
# Install fixpad-sm8550 into a rootfs or live system (SM8550 AYN stick range + desktop idle wake).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS="${1:-/}"

if [[ "${1:-}" == "--force" ]]; then
  ROOTFS="/"
fi

log() { printf '==> [fixpad-sm8550] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ "${EUID}" -ne 0 && "${ROOTFS}" == "/" ]]; then
  die "Run as root"
fi

if [[ "$ROOTFS" != "/" ]]; then
  ROOTFS="${ROOTFS%/}"
  [[ -d "${ROOTFS}/usr" ]] || die "Not a rootfs: ${ROOTFS}"
fi

path() {
  if [[ "$ROOTFS" == "/" ]]; then printf '%s\n' "$1"; else printf '%s%s\n' "$ROOTFS" "$1"; fi
}

log "Install binaries → $(path /usr/bin)"
install -d "$(path /usr/libexec/steamos-ubuntu)" \
  "$(path /usr/lib/systemd/user)" \
  "$(path /etc/xdg/autostart)"

install -m 0755 "${ROOT}/fixpad-sm8550" "$(path /usr/bin)/fixpad-sm8550"
install -m 0755 "${ROOT}/fixpad-sm8550-daemon.py" \
  "$(path /usr/libexec/steamos-ubuntu)/fixpad-sm8550-daemon.py"

cat >"$(path /usr/lib/systemd/user)/fixpad-sm8550.service" <<'EOF'
[Unit]
Description=SM8550 fixpad (stick range + Plasma idle wake)
After=graphical-session.target
PartOf=graphical-session.target
ConditionEnvironment=!STEAMOS_SESSION

[Service]
Type=simple
ExecStart=/usr/libexec/steamos-ubuntu/fixpad-sm8550-daemon.py
Restart=on-failure
RestartSec=2
Environment=FIXPAD_TARGET=740

[Install]
WantedBy=default.target
EOF

# Plasma autostart fallback (desktop session)
cat >"$(path /etc/xdg/autostart)/fixpad-sm8550-plasma.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=SM8550 fixpad
Comment=Rescale AYN sticks and keep screen awake while playing on Desktop
Exec=/usr/bin/fixpad-sm8550 apply
Icon=preferences-desktop-gaming
X-GNOME-Autostart-enabled=true
OnlyShowIn=KDE;
NoDisplay=true
EOF

enable_user_unit() {
  local wants base
  for base in \
    "$(path /etc/skel/.config/systemd/user/default.target.wants)" \
    "$(path /home/steam/.config/systemd/user/default.target.wants)"; do
    mkdir -p "$base"
    ln -sfn /usr/lib/systemd/user/fixpad-sm8550.service \
      "${base}/fixpad-sm8550.service"
  done
}

enable_user_unit

# User systemd at boot (desktop idle daemon; gaming uses gamescope-session apply)
mkdir -p "$(path /var/lib/systemd/linger)"
touch "$(path /var/lib/systemd/linger)/steam"

if [[ -d "$(path /usr)" ]] && command -v chroot >/dev/null && [[ "$ROOTFS" != "/" ]]; then
  log "python3-evdev (chroot)"
  chroot "$ROOTFS" apt-get install -y --no-install-recommends python3-evdev 2>/dev/null || \
    log "WARN: could not install python3-evdev in chroot (python3-dbus from plasma)"
elif [[ "$ROOTFS" == "/" ]]; then
  apt-get install -y --no-install-recommends python3-evdev 2>/dev/null || \
    log "WARN: could not apt-install python3-evdev"
fi

if [[ "$ROOTFS" == "/" ]]; then
  if [[ "${XDG_CURRENT_DESKTOP:-}" == *gamescope* ]] || [[ "${STEAMOS_SESSION:-}" == "1" ]]; then
    log "Gaming session — apply sticks"
    /usr/bin/fixpad-sm8550 apply || true
  else
    log "Desktop session — apply sticks + start user daemon"
    /usr/bin/fixpad-sm8550 apply || true
    if id steam >/dev/null 2>&1; then
      runuser -u steam -- systemctl --user daemon-reload 2>/dev/null || true
      runuser -u steam -- systemctl --user enable --now fixpad-sm8550.service 2>/dev/null || true
    fi
  fi
fi

log "Done."
log "  Gaming Mode: gamescope-session applies sticks at session start"
log "  Desktop:     fixpad-sm8550 user service + Plasma autostart"
