#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYSTEM_DEST="/usr/share/plasma/plasmoids/org.masi.colorines"
USER_DEST="${HOME}/.local/share/plasma/plasmoids/org.masi.colorines"

rm -rf "$USER_DEST"
mkdir -p "$(dirname "$USER_DEST")"
cp -a "$ROOT/kde/org.masi.colorines" "$USER_DEST"

if [[ "${EUID:-$(id -u)}" -eq 0 ]] || (command -v sudo >/dev/null && sudo -n true 2>/dev/null); then
  SUDO=()
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || SUDO=(sudo)
  "${SUDO[@]}" mkdir -p /usr/libexec/masi
  "${SUDO[@]}" install -m 755 "$ROOT/system/colorines-ctl" /usr/libexec/masi/colorines-ctl
  "${SUDO[@]}" rm -rf "$SYSTEM_DEST"
  "${SUDO[@]}" cp -a "$ROOT/kde/org.masi.colorines" "$SYSTEM_DEST"
  "${SUDO[@]}" chown -R root:root "$SYSTEM_DEST"
  echo "System install: $SYSTEM_DEST"
else
  echo "Skipped system plasmoid (run install.sh / sudo for /usr/share)"
fi

echo "User install: $USER_DEST"
echo "Añade «Led Colors» al panel / bandeja del sistema."
echo "Reinicia Plasma: kquitapp6 plasmashell && plasmashell --replace &"
