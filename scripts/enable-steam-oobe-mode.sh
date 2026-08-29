#!/usr/bin/env bash
# Enable Deck-style OOBE attempt on live STORAGE:
#  - session mode oobe (-steamos3 -steamdeck)
#  - polkit so user steam can drive NetworkManager Wi-Fi
#  - clear leftover Steam registry that can skip first-run wizard
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/system_files"

[[ "${EUID}" -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -d "$ROOT/usr" ]] || { echo "Bad root $ROOT"; exit 1; }

install -m 0755 "$SRC/usr/bin/gamescope-session" "$ROOT/usr/bin/gamescope-session"
install -m 0755 "$SRC/usr/libexec/steamos-ubuntu/launch-steam" \
  "$ROOT/usr/libexec/steamos-ubuntu/launch-steam" 2>/dev/null || true
install -D -m 0644 \
  "$SRC/etc/polkit-1/rules.d/50-steamos-networkmanager.rules" \
  "$ROOT/etc/polkit-1/rules.d/50-steamos-networkmanager.rules"

mkdir -p "$ROOT/var/lib/steamos-ubuntu"
echo deck >"$ROOT/var/lib/steamos-ubuntu/steam-mode"
rm -f "$ROOT/usr/libexec/steamos-ubuntu/arm-steam-oobe-update-guard" \
  "$ROOT/var/lib/steamos-ubuntu/arm-oobe-did-reboot" 2>/dev/null || true

# Ensure steam can use NM (group + linger already elsewhere)
if grep -q '^steam:' "$ROOT/etc/passwd"; then
  chroot "$ROOT" usermod -aG netdev steam 2>/dev/null || true
fi

# Full primer-inicio reset (CompletedOOBE in registry skips wizard → login)
"$REPO/scripts/reset-steam-oobe-firstboot.sh" "$ROOT"

# Wi-Fi stack presence (informational)
echo "NM:"; ls "$ROOT/usr/sbin/NetworkManager" 2>&1 || true
echo "wifi plugin:"; ls "$ROOT/usr/lib/aarch64-linux-gnu/NetworkManager/"*wifi* 2>/dev/null | head || \
  ls "$ROOT/usr/lib/NetworkManager/"*wifi* 2>/dev/null | head || echo "(check NetworkManager-wifi package)"
echo "wpasupplicant:"; ls "$ROOT/sbin/wpa_supplicant" "$ROOT/usr/sbin/wpa_supplicant" 2>&1 | head

echo
echo "Done. Reboot and look for:"
echo "  steam-mode=deck → ... -gamepadui -steamos3 -steamdeck (wayland: modeset)"
echo "Expected UX: language / timezone / Choose your network (not only Steam login)."
echo "If it stalls again (black, no CreateBrowser), set mode back to bare and report."
