#!/usr/bin/env bash
# Enable Gaming Mode services (greetd autologin → gamescope-session)
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
# Keep our /etc/greetd/config.toml from system_files (never prompt)
export UCF_FORCE_CONFFOLD=1
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

log() { printf '==> %s\n' "$*"; }

# Plasma install can leave greetd half-configured (dpkg "unpacked" forever).
# Finish configures + force-reinstall so display-manager can start.
dpkg --force-confdef --force-confold --configure -a || true
apt-get install "${APT_OPTS[@]}" --reinstall --no-install-recommends greetd seatd 2>/dev/null || true
dpkg --force-confdef --force-confold --configure -a || true

# Re-assert SteamOS greetd session (package may have tried to replace config.toml)
if [[ ! -f /etc/greetd/config.toml ]] || ! grep -q 'steamos-greetd-session' /etc/greetd/config.toml 2>/dev/null; then
  install -d /etc/greetd
  cat >/etc/greetd/config.toml <<'EOF'
[terminal]
vt = "1"

[initial_session]
command = "/usr/local/bin/steamos-greetd-session"
user = "steam"

[default_session]
command = "/usr/local/bin/steamos-greetd-session"
user = "steam"
EOF
fi

systemctl enable NetworkManager.service || true
systemctl enable bluetooth.service || true
systemctl enable seatd.service || true
systemctl enable greetd.service || true
systemctl enable systemd-resolved.service || true
systemctl enable upower.service || true
# First boot after flash: grow STORAGE partition + ext4 (no reboot; before greetd/Steam)
systemctl enable steamos-expand-rootfs.service 2>/dev/null || true

# greetd MUST own graphical.target (sddm from Plasma is masked and must not steal this)
mkdir -p /etc/systemd/system
ln -sfn /lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
if [[ -x /usr/sbin/greetd ]]; then
  echo /usr/sbin/greetd >/etc/X11/default-display-manager
elif [[ -x /usr/bin/greetd ]]; then
  echo /usr/bin/greetd >/etc/X11/default-display-manager
fi

# Do NOT wait for a default route before graphical/greetd (OOBE brings Wi-Fi later).
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
systemctl mask NetworkManager-wait-online.service 2>/dev/null || true

# Dead weight / always-fail on this handheld (also masked again in finalize-handheld-rootfs)
for u in \
  nvmf-autoconnect.service \
  nvmefc-boot-connections.service \
  lvm2-monitor.service \
  ubuntu-advantage.service \
  ua-reboot-cmds.service \
  ua-timer.timer \
  motd-news.timer \
  cloud-init.service \
  cloud-init-local.service \
  cloud-config.service \
  cloud-final.service
do
  systemctl disable "$u" 2>/dev/null || true
  systemctl mask "$u" 2>/dev/null || true
done

# Mask display managers that fight greetd if pulled in (Plasma uses startplasma via greetd)
for s in gdm sddm lightdm; do
  systemctl mask "${s}.service" 2>/dev/null || true
done

# Snap must never run (also purged in 25-disable-snap.sh)
for s in snapd.service snapd.socket snapd.seeded.service; do
  systemctl disable "$s" 2>/dev/null || true
  systemctl mask "$s" 2>/dev/null || true
done

# Default target
systemctl set-default graphical.target || true

# greetd refuses to start without /etc/pam.d/greetd
if [[ ! -f /etc/pam.d/greetd ]]; then
  install -d /etc/pam.d
  cat >/etc/pam.d/greetd <<'EOF'
#%PAM-1.0
@include login
EOF
fi
if [[ ! -f /etc/pam.d/greetd-greeter ]]; then
  cat >/etc/pam.d/greetd-greeter <<'EOF'
#%PAM-1.0
@include login
EOF
fi

# greetd package often expects a greeter user; we autologin as steam instead
if ! id greeter &>/dev/null; then
  useradd --system --create-home --home-dir /var/lib/greeter \
    --shell /usr/sbin/nologin --user-group greeter 2>/dev/null || true
fi

# VT1 is for gamescope — do not run a text getty there
systemctl mask getty@tty1.service 2>/dev/null || true
mkdir -p /etc/systemd/system/greetd.service.d
# Seatd + no getty conflict. Faster-boot (no plymouth-quit-wait) comes from system_files.
cat >/etc/systemd/system/greetd.service.d/10-steamos.conf <<'EOF'
[Unit]
Conflicts=getty@tty1.service
After=getty@tty1.service
Wants=seatd.service
EOF

# Pipewire user services are socket-activated; ensure lingering for steam
if id -u steam &>/dev/null; then
  loginctl enable-linger steam 2>/dev/null || true
  mkdir -p /var/lib/systemd/linger
  touch /var/lib/systemd/linger/steam
fi

# dbus-run-session binary (greetd → gamescope) — required for Steam CEF/Gamepad UI
apt-get install -y --no-install-recommends dbus-user-session dbus-x11 libcap2-bin x11-utils 2>/dev/null || true

log "Services enabled"
