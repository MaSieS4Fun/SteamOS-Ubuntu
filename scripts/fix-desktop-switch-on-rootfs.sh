#!/usr/bin/env bash
# Hot-fix Switch-to-Desktop + Plasma greetd launcher onto mounted STORAGE/rootfs.
# Usage: sudo ./scripts/fix-desktop-switch-on-rootfs.sh /media/odin2/STORAGE
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${1:-}"
[[ -n "$ROOT" && -d "$ROOT/usr" ]] || { echo "Usage: $0 <rootfs>"; exit 1; }
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root"; exit 1; }

SRC="${ROOT_DIR}/system_files"

STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "$ROOT/etc/passwd")"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "$ROOT/etc/passwd")"
[[ -n "${STEAM_UID:-}" ]] || { echo "ERROR: no steam user in $ROOT/etc/passwd"; exit 1; }
g="$(awk -F: '$1=="steam"{print $3; exit}' "$ROOT/etc/group" 2>/dev/null || true)"
[[ -n "$g" ]] && STEAM_GID="$g"
echo "steam in rootfs → uid=${STEAM_UID} gid=${STEAM_GID}"

install -D -m 0755 "$SRC/usr/lib/steamos/steam-set-session" "$ROOT/usr/lib/steamos/steam-set-session"
install -D -m 0755 "$SRC/usr/bin/steamos-session-select" "$ROOT/usr/bin/steamos-session-select"
install -D -m 0755 "$SRC/usr/libexec/steamos-ubuntu/steamos-manager" \
  "$ROOT/usr/libexec/steamos-ubuntu/steamos-manager"
install -D -m 0755 "$SRC/usr/local/bin/steamos-greetd-session" \
  "$ROOT/usr/local/bin/steamos-greetd-session"
install -D -m 0644 "$SRC/usr/share/polkit-1/actions/org.steamos.set.session.policy" \
  "$ROOT/usr/share/polkit-1/actions/org.steamos.set.session.policy"
install -D -m 0644 "$SRC/etc/systemd/system/steamos-force-gaming-boot.service" \
  "$ROOT/etc/systemd/system/steamos-force-gaming-boot.service"
install -D -m 0644 "$SRC/usr/share/applications/steamos-gamemode.desktop" \
  "$ROOT/usr/share/applications/steamos-gamemode.desktop" 2>/dev/null || true

install -d -m 0775 "$ROOT/var/lib/steamos-ubuntu"
echo gamescope-session >"$ROOT/var/lib/steamos-ubuntu/session"
chown -R "${STEAM_UID}:${STEAM_GID}" "$ROOT/var/lib/steamos-ubuntu"
chmod 0664 "$ROOT/var/lib/steamos-ubuntu/"* 2>/dev/null || true

# Pre-seed skip Plasma welcome (wizard often leaves a black shell)
install -d -m 0755 "$ROOT/home/steam/.config"
cat >"$ROOT/home/steam/.config/plasma-welcomerc" <<'EOF'
[General]
LastSeenVersion=99.0.0
EOF
chown -R "${STEAM_UID}:${STEAM_GID}" "$ROOT/home/steam/.config"

chmod 1777 "$ROOT/tmp" 2>/dev/null || true
mkdir -p "$ROOT/tmp/.X11-unix"
chmod 1777 "$ROOT/tmp/.X11-unix"

echo "OK: desktop switch + Plasma launcher fixed on $ROOT"
ls -la "$ROOT/var/lib/steamos-ubuntu" "$ROOT/usr/local/bin/steamos-greetd-session"
