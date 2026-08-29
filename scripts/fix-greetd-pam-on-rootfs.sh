#!/usr/bin/env bash
# Fix greetd so Gaming Mode can start on a flashed/mounted rootfs.
# Usage: sudo ./scripts/fix-greetd-pam-on-rootfs.sh /media/odin2/STORAGE
set -euo pipefail

ROOT="${1:-}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[[ -n "$ROOT" && -d "$ROOT/etc" ]] || { echo "Usage: $0 <rootfs-mount>"; exit 1; }
[[ "${EUID}" -eq 0 ]] || { echo "Run as root"; exit 1; }

install -D -m 0644 "$HERE/system_files/etc/pam.d/greetd" "$ROOT/etc/pam.d/greetd"
install -D -m 0644 "$HERE/system_files/etc/pam.d/greetd-greeter" "$ROOT/etc/pam.d/greetd-greeter"
install -D -m 0644 "$HERE/system_files/etc/greetd/config.toml" "$ROOT/etc/greetd/config.toml"
install -D -m 0644 "$HERE/system_files/etc/sysctl.d/20-quiet-console.conf" \
  "$ROOT/etc/sysctl.d/20-quiet-console.conf" 2>/dev/null || true
install -D -m 0755 "$HERE/system_files/usr/local/bin/steamos-greetd-session" \
  "$ROOT/usr/local/bin/steamos-greetd-session"
install -D -m 0755 "$HERE/system_files/usr/bin/gamescope-session" \
  "$ROOT/usr/bin/gamescope-session"

# session debug log (world-writable so steam can write)
install -d -m 1777 "$ROOT/var/tmp"
install -d -m 0755 "$ROOT/var/log"
touch "$ROOT/var/log/steamos-session.log"
chmod 666 "$ROOT/var/log/steamos-session.log"
ln -sfn /var/log/steamos-session.log "$ROOT/var/tmp/steamos-session.log"

# gamescope runtime libs often missed by meson --skip-subprojects
install -d "$ROOT/usr/lib/aarch64-linux-gnu"
for so in libliftoff.so.0 libliftoff.so.0.5.0 libliftoff.so; do
  if [[ -e "/usr/lib/aarch64-linux-gnu/${so}" ]]; then
    cp -a "/usr/lib/aarch64-linux-gnu/${so}" "$ROOT/usr/lib/aarch64-linux-gnu/" || true
  fi
done
# Prefer apt if available inside rootfs tooling on host
if command -v dpkg >/dev/null && [[ -d "$ROOT/var/lib/dpkg" ]]; then
  mount -t proc proc "$ROOT/proc" 2>/dev/null || true
  mount --bind /dev "$ROOT/dev" 2>/dev/null || true
  "$HERE/scripts/inject-chroot-dns.sh" "$ROOT" 2>/dev/null || true
  chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y -o Dpkg::Options::="--force-confold" --no-install-recommends \
    libliftoff0 libdisplay-info2 2>/dev/null || true
  umount -l "$ROOT/dev" 2>/dev/null || true
  umount -l "$ROOT/proc" 2>/dev/null || true
fi
ldconfig -r "$ROOT" 2>/dev/null || true

# Optional greeter user (some greetd packages expect it)
if ! grep -q '^greeter:' "$ROOT/etc/passwd"; then
  echo 'greeter:x:968:968:greetd greeter:/var/lib/greeter:/usr/sbin/nologin' >> "$ROOT/etc/passwd"
  echo 'greeter:!:19600:0:99999:7:::' >> "$ROOT/etc/shadow"
  if ! grep -q '^greeter:' "$ROOT/etc/group"; then
    echo 'greeter:x:968:' >> "$ROOT/etc/group"
  fi
  mkdir -p "$ROOT/var/lib/greeter"
  chown -h 968:968 "$ROOT/var/lib/greeter" 2>/dev/null || true
fi

# greetd owns VT1 — stop getty from fighting it
mkdir -p "$ROOT/etc/systemd/system"
ln -sfn /dev/null "$ROOT/etc/systemd/system/getty@tty1.service"
ln -sfn /usr/lib/systemd/system/greetd.service \
  "$ROOT/etc/systemd/system/display-manager.service"
mkdir -p "$ROOT/etc/systemd/system/graphical.target.wants"
ln -sfn /usr/lib/systemd/system/greetd.service \
  "$ROOT/etc/systemd/system/graphical.target.wants/greetd.service"

# Drop-in: greetd after seatd, conflict getty@tty1
install -d "$ROOT/etc/systemd/system/greetd.service.d"
cat >"$ROOT/etc/systemd/system/greetd.service.d/override.conf" <<'EOF'
[Unit]
After=seatd.service
Wants=seatd.service
Conflicts=getty@tty1.service
After=getty@tty1.service
EOF

install -d "$ROOT/var/lib/steamos-ubuntu"
echo gamescope-session > "$ROOT/var/lib/steamos-ubuntu/session"

# Apt pin: never reinstall Ubuntu Mesa over vendor Turnip (applied after packages)
install -D -m 0644 \
  "$HERE/config/apt-preferences/99-block-ubuntu-mesa" \
  "$ROOT/etc/apt/preferences.d/99-block-ubuntu-mesa"

# Xwayland is required by gamescope; Mesa pin/purge often drops it
"${HERE}/scripts/ensure-xwayland-into-rootfs.sh" "$ROOT"

# Full recursive gamescope lib gate — must pass before reboot
"${HERE}/scripts/ensure-gamescope-libs.sh" "$ROOT"

echo "Fixed greetd on ${ROOT}"
echo "  - PAM / config / getty@tty1 mask"
echo "  - Ubuntu Mesa apt-blocked"
echo "  - recursive gamescope libs"
echo "If Vulkan still picks llvmpipe, rebuild Mesa stack:"
echo "  sudo ./scripts/build-vendor-mesa.sh ${ROOT}"
echo "Reboot the handheld image."
