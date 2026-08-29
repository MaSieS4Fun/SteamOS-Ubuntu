#!/bin/bash
# Install Colorines everywhere: system + Decky + KDE + Plasma Mobile.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

# shellcheck source=scripts/lib/masi-steam-paths.sh
source "$ROOT/scripts/lib/masi-steam-paths.sh"
masi_resolve_target_user

export HOME="$TARGET_HOME"
export USER="$TARGET_USER"
export LOGNAME="$TARGET_USER"

step() {
  echo
  echo "==> $1"
}

step "Colorines — instalación completa"
echo "Usuario: $TARGET_USER"
echo "Home:    $TARGET_HOME"
echo "Proyecto: $ROOT"

step "1/4 Sistema (CLI, librería, udev)"
"$ROOT/scripts/install-system.sh"

step "2/4 Plugin Decky (Steam / GameScope, root)"
"$ROOT/scripts/install-decky.sh"

step "3/4 Applet KDE (bandeja escritorio)"
# System plasmoid as root, then user copy as the real user
SYSTEM_DEST="/usr/share/plasma/plasmoids/org.masi.colorines"
rm -rf "$SYSTEM_DEST"
cp -a "$ROOT/kde/org.masi.colorines" "$SYSTEM_DEST"
chown -R root:root "$SYSTEM_DEST"
sudo -u "$TARGET_USER" HOME="$TARGET_HOME" "$ROOT/scripts/install-kde-applet.sh"

step "4/4 Plasma Mobile (2.º tile: sustituye MaSi Power / Mobile Data)"
"$ROOT/scripts/install-plasma-mobile.sh"

step "Reiniciando Decky Loader"
if systemctl is-active --quiet plugin_loader.service 2>/dev/null; then
  systemctl restart plugin_loader.service
  echo "plugin_loader.service reiniciado"
else
  echo "plugin_loader.service no activo — omite reinicio"
fi

echo
echo "Install complete."
echo
echo "  • CLI:     colorines on | colorines preset red | colorines off"
echo "  • Decky:   ⋯ menu → Led Colors (needs Decky root mode)"
echo "  • KDE:     add «Led Colors» to the system tray / panel"
echo "  • PM:      2nd tile Led Colors (was MaSi Power / Mobile Data)"
echo
echo "Restart Plasma if needed:"
echo "  kquitapp6 plasmashell && plasmashell --replace &"
echo "Restart Steam/gamescope for Decky if needed."
