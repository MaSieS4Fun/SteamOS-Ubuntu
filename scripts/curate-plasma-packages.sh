#!/usr/bin/env bash
# Optional: regenerate packages/plasma from the Kubuntu Resolute dump.
# Usage:
#   ./scripts/curate-plasma-packages.sh [/path/to/ubuntu-resolute-kubuntu-desktop-aarch64.packages]
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-/home/odin2/Desktop/packages/ubuntu-resolute-kubuntu-desktop-aarch64.packages}"
OUT="${ROOT_DIR}/packages/plasma"
[[ -f "$SRC" ]] || { echo "Missing dump: $SRC" >&2; exit 1; }

{
  cat <<'HDR'
# Plasma / KDE Desktop Mode extras (curated from ubuntu-resolute-kubuntu-desktop-aarch64.packages).
# Excludes: snap*, ubiquity/oem, browsers (Brave via official repo only),
# antimicro / input-remapper (pad→mouse). Gaming Mode stays greetd; sddm masked.
HDR
  grep -vE '^\s*(#|$)' "$SRC" | awk 'NF' \
    | grep -viE '^(ubiquity|oem-config|brave-browser|firefox|chromium|chrome|epiphany|midori|opera|vivaldi|snapd|snap-confine|ubuntu-core-launcher|kubuntu-desktop|antimicro|antimicrox|input-remapper|xserver-xorg-input-joystick)($|-)' \
    | grep -viE 'snap' \
    | sort -u
  printf '%s\n' \
    plasma-desktop plasma-workspace plasma-workspace-wayland plasma-session-wayland \
    kwin-wayland qt6-wayland plasma-nm plasma-pa bluedevil powerdevil \
    dolphin konsole systemsettings breeze breeze-icon-theme \
    xdg-desktop-portal-kde kde-cli-tools plasma-systemmonitor \
    kdeconnect print-manager spectacle ark gwenview okular \
    libsdl2-2.0-0 steam-devices
} | awk 'NF && !seen[$0]++' >"$OUT"

echo "Wrote $(grep -cvE '^\s*(#|$)' "$OUT") packages → $OUT"
