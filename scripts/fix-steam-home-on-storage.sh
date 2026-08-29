#!/usr/bin/env bash
# Normalize steam/ubuntu homes on a live STORAGE rootfs.
# Does NOT install Plasma (optional Desktop Mode — separate). Deck OOBE is Steam UI.
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
[[ "${EUID}" -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -d "$ROOT/usr" ]] || { echo "Bad root $ROOT"; exit 1; }

STEAM_UID="$(awk -F: '$1=="steam"{print $3}' "$ROOT/etc/passwd")"
STEAM_GID="$(awk -F: '$1=="steam"{print $4}' "$ROOT/etc/passwd")"
[[ -n "$STEAM_UID" && -n "$STEAM_GID" ]] || { echo "steam user missing"; exit 1; }

echo "steam uid:gid = ${STEAM_UID}:${STEAM_GID}"

# Fix ownership (host mounts often look like nobody when UIDs don't match)
chown -R "${STEAM_UID}:${STEAM_GID}" "$ROOT/home/steam"

# Browseable from another Linux with sudo still needed for 750; use 755 for handheld SD debugging
chmod 755 "$ROOT/home/steam"

# Standard XDG dirs (Desktop/Downloads/…) — missing because no plasma/login ever ran xdg-user-dirs-update
chroot "$ROOT" runuser -u steam -- env HOME=/home/steam xdg-user-dirs-update 2>/dev/null \
  || chroot "$ROOT" runuser -u steam -- bash -lc '
       mkdir -p "$HOME"/{Desktop,Downloads,Documents,Music,Pictures,Videos,Templates,Public}
     '
chown -R "${STEAM_UID}:${STEAM_GID}" "$ROOT/home/steam"

# Ensure steam in useful groups
chroot "$ROOT" usermod -aG sudo,audio,video,render,input,plugdev,netdev,bluetooth steam 2>/dev/null || true

# ubuntu user: leftover from Ubuntu cloud image — lock & hide (keep uid 1000 slot or remove)
if grep -q '^ubuntu:' "$ROOT/etc/passwd"; then
  chroot "$ROOT" passwd -l ubuntu 2>/dev/null || true
  # Make home root-owned empty skeleton; optional delete later
  chmod 755 "$ROOT/home/ubuntu" 2>/dev/null || true
  echo "NOTE: user 'ubuntu' locked (cloud image leftover). Safe to ignore for Gaming Mode."
fi

echo "steam home now:"
ls -la "$ROOT/home/steam" | head -30
echo
echo "Done. Plasma is NOT installed — Deck OOBE does not need it."
echo "Desktop Mode (optional) would be: apt install plasma-workspace …"
echo "For OOBE Wi-Fi in Steam, use: sudo bash scripts/enable-steam-oobe-mode.sh"
