#!/bin/bash
# Install Colorines system pieces: CLI, Python lib, udev, sudoers, LED perms.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

LIB_DEST="/usr/lib/python3/dist-packages/colorines"
SITE_DEST="/usr/local/lib/colorines"
CTL_DEST="/usr/libexec/masi/colorines-ctl"
BIN_LINK="/usr/bin/colorines"
UDEV_DEST="/etc/udev/rules.d/99-colorines-leds.rules"
SUDOERS_DEST="/etc/sudoers.d/colorines"
STATE_DIR="/var/lib/colorines"

mkdir -p /usr/libexec/masi "$SITE_DEST" "$STATE_DIR"
rm -rf "$SITE_DEST/colorines" 2>/dev/null || true
mkdir -p "$SITE_DEST"
cp -a "$ROOT/shared/colorines" "$SITE_DEST/"
if [[ -d /usr/lib/python3/dist-packages ]]; then
  rm -rf "$LIB_DEST" 2>/dev/null || true
  cp -a "$ROOT/shared/colorines" "$LIB_DEST"
fi

mkdir -p /usr/local/lib/python3/dist-packages
echo "$SITE_DEST" >/usr/local/lib/python3/dist-packages/colorines.pth

install -m 755 "$ROOT/system/colorines-ctl" "$CTL_DEST"
ln -sfn "$CTL_DEST" "$BIN_LINK"

install -m 644 "$ROOT/system/99-colorines-leds.rules" "$UDEV_DEST"
install -m 440 "$ROOT/system/sudoers-colorines" "$SUDOERS_DEST"
if command -v visudo >/dev/null 2>&1; then
  if ! visudo -cf "$SUDOERS_DEST" >/dev/null 2>&1; then
    echo "WARNING: sudoers file invalid, removing $SUDOERS_DEST" >&2
    rm -f "$SUDOERS_DEST"
  fi
fi

udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=leds 2>/dev/null || true

# Real sessions need writable sysfs + video group on LED nodes
mount -o remount,rw /sys 2>/dev/null || true
for led in left-joystick left-side right-joystick right-side left_joystick left_side right_joystick right_side; do
  for f in brightness multi_intensity trigger; do
    p="/sys/class/leds/${led}/${f}"
    [[ -e "$p" ]] || continue
    chgrp video "$p" 2>/dev/null || true
    chmod 0664 "$p" 2>/dev/null || true
  done
done

chmod 755 "$STATE_DIR"
if getent group video >/dev/null; then
  chgrp video "$STATE_DIR" 2>/dev/null || true
  chmod 775 "$STATE_DIR" 2>/dev/null || true
fi

echo "System install OK:"
echo "  $CTL_DEST"
echo "  $BIN_LINK"
echo "  $SITE_DEST/colorines"
echo "  $UDEV_DEST"
echo "  $SUDOERS_DEST"
echo "  $STATE_DIR"
# Smoke test
if "$CTL_DEST" get >/dev/null 2>&1; then
  echo "  smoke: get OK"
else
  echo "  smoke: get failed (zones missing?)" >&2
fi
