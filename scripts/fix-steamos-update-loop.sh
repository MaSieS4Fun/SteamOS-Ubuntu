#!/usr/bin/env bash
# Install SteamOS-like Steam OOBE update helpers + session restart so the
# post-Wi-Fi update step can finish (client update + Steam restart → login).
#
# Important (from Deck OOBE logs + Bazzite):
#   - steamos-update APPLY must exit 0 in OOBE; post-login APPLY exits 7
#   - check exits 7 (no OS image). Never use check→0 (fake update → reboot hang)
#   - client CDN update is inhibited via steam.cfg; Steam is nudged to exit → relaunch
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/system_files"

[[ "${EUID}" -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -d "$ROOT/usr" ]] || { echo "ROOT not mounted: $ROOT"; exit 1; }

install_bin() {
  local rel="$1"
  install -D -m 0755 "$SRC/$rel" "$ROOT/$rel"
  echo "installed /$rel"
}

install_bin usr/bin/steamos-update
install_bin usr/bin/steamos-select-branch
install_bin usr/bin/jupiter-biosupdate
install_bin usr/bin/jupiter-initial-firmware-update
install_bin usr/bin/steamos-polkit-helpers/steamos-update
install_bin usr/bin/steamos-polkit-helpers/jupiter-biosupdate
install_bin usr/bin/steamos-polkit-helpers/steamos-set-timezone
install_bin usr/bin/steamos-polkit-helpers/steamos-select-branch
install_bin usr/bin/gamescope-session
install_bin usr/local/bin/steamos-greetd-session

install -D -m 0644 "$SRC/etc/greetd/config.toml" "$ROOT/etc/greetd/config.toml"
install -D -m 0644 "$SRC/etc/polkit-1/rules.d/50-steamos-oobe-helpers.rules" \
  "$ROOT/etc/polkit-1/rules.d/50-steamos-oobe-helpers.rules"
install -D -m 0644 "$SRC/usr/share/polkit-1/actions/org.steamos-ubuntu.update.policy" \
  "$ROOT/usr/share/polkit-1/actions/org.steamos-ubuntu.update.policy"
if [[ -f "$SRC/etc/polkit-1/rules.d/50-steamos-networkmanager.rules" ]]; then
  install -D -m 0644 "$SRC/etc/polkit-1/rules.d/50-steamos-networkmanager.rules" \
    "$ROOT/etc/polkit-1/rules.d/50-steamos-networkmanager.rules"
fi

# Session: deck CLIENTCMD (-gamepadui -steamos3). Do NOT use steam-mode=oobe:
# -steamos flags init Steam DisplayManager as X11 on ARM (want wayland: modeset).
mkdir -p "$ROOT/var/lib/steamos-ubuntu"
echo deck >"$ROOT/var/lib/steamos-ubuntu/steam-mode"
rm -f "$ROOT/usr/libexec/steamos-ubuntu/arm-steam-oobe-update-guard" \
  "$ROOT/var/lib/steamos-ubuntu/arm-oobe-did-reboot" 2>/dev/null || true

# ARM CDN self-update fails (http error 0) → Retry forever. Inhibit in $HOME.
STEAM_DIR="$ROOT/home/steam/.local/share/Steam"
if [[ -d "$STEAM_DIR" ]]; then
  mkdir -p "${STEAM_DIR}/steamrtarm64"
  printf '%s\n' \
    '# Steam ARM: skip broken client CDN self-update (Retry loop).' \
    'BootStrapperInhibitAll=enable' \
    'BootStrapperForceSelfUpdate=disable' \
    | tee "${STEAM_DIR}/steam.cfg" "${STEAM_DIR}/steamrtarm64/steam.cfg" >/dev/null
  echo "wrote BootStrapperInhibitAll steam.cfg"
fi

# DNS/IP: DHCP via NetworkManager only (no static public DNS)
"$REPO/scripts/fix-wifi-dns.sh" "$ROOT"

chroot "$ROOT" usermod -aG sudo,netdev,video,render,input,audio steam 2>/dev/null || true

echo
echo "Smoke tests:"
chroot "$ROOT" /usr/bin/steamos-update --supports-duplicate-detection; echo "  supports-dup → $?"
chroot "$ROOT" /usr/bin/steamos-update check; echo "  check (no login) → $? (expect 7)"
chroot "$ROOT" /usr/bin/jupiter-initial-firmware-update check; echo "  firmware check → $? (expect 0)"
chroot "$ROOT" /usr/bin/steamos-select-branch -c; echo "  branch -c → $(chroot "$ROOT" /usr/bin/steamos-select-branch -c 2>/dev/null) exit=$?"
grep -E 'default_session|initial_session|command' "$ROOT/etc/greetd/config.toml" || true

echo
echo "Reboot. Flow should match Deck OOBE:"
echo "  language → Wi-Fi → update (client CDN if needed; OS exit 7) → Steam restarts into session → login"
echo "If you still hit TTY, copy /var/tmp/steamos-session.log"
