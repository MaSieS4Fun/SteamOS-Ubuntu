#!/usr/bin/env bash
# Reset Steam home to Deck "primer inicio" (language → Wi-Fi → update → login).
# Keeps the baked client (steamui / .installed) so it does not re-download.
#
#   sudo ./scripts/reset-steam-oobe-firstboot.sh [/media/odin2/STORAGE]
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
STEAM_HOME="${STEAM_HOME_OVERRIDE:-$ROOT/home/steam}"

[[ "${EUID}" -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -d "$STEAM_HOME" ]] || { echo "No steam home at $STEAM_HOME"; exit 1; }

echo "Resetting OOBE on $STEAM_HOME"

# 1) Registry flags that skip the wizard (this is why you saw login)
ts="$(date +%s)"
for f in \
  "$STEAM_HOME/.steam/registry.vdf" \
  "$STEAM_HOME/.local/share/Steam/registry.vdf"
do
  if [[ -f "$f" ]]; then
    cp -a "$f" "${f}.bak.${ts}" || true
    rm -f "$f"
    echo "removed $f (had CompletedOOBE)"
  fi
done

# 2) Login / account residue (if any)
rm -f \
  "$STEAM_HOME/.local/share/Steam/config/loginusers.vdf" \
  "$STEAM_HOME/.steam/steam.token" \
  "$STEAM_HOME/.steam/steam.pid" \
  "$STEAM_HOME/.steampid" \
  2>/dev/null || true
find "$STEAM_HOME" \( -name '*.pid' -o -name '*.token' -o -name '*.crash' \) -delete 2>/dev/null || true

# Optional: wipe remembered UI prefs that are not needed for bake
rm -f "$STEAM_HOME/.local/share/Steam/config/DialogConfig.vdf" 2>/dev/null || true

# 3) Forget Wi-Fi so OOBE shows "Choose your network" again
NM_DIR="$ROOT/etc/NetworkManager/system-connections"
if [[ -d "$NM_DIR" ]]; then
  shopt -s nullglob
  for c in "$NM_DIR"/*; do
    [[ -f "$c" ]] || continue
    echo "removing Wi-Fi profile $(basename "$c")"
    rm -f "$c"
  done
  shopt -u nullglob
fi
# Runtime leases / state (harmless if absent)
rm -f "$ROOT/var/lib/NetworkManager/"*.lease \
      "$ROOT/var/lib/NetworkManager/NetworkManager-intern.conf" 2>/dev/null || true

# 4) Keep Gaming Mode on Deck OOBE flags
mkdir -p "$ROOT/var/lib/steamos-ubuntu"
echo deck >"$ROOT/var/lib/steamos-ubuntu/steam-mode"
echo gamescope-session >"$ROOT/var/lib/steamos-ubuntu/session"
echo "steam-mode=deck"

# 5) ARM CDN self-update fails (http error 0) — keep BootStrapperInhibit in $HOME
mkdir -p "$STEAM_HOME/.local/share/Steam/steamrtarm64"
printf '%s\n' \
  '# Steam ARM: skip broken client CDN self-update (Retry loop).' \
  'BootStrapperInhibitAll=enable' \
  'BootStrapperForceSelfUpdate=disable' \
  | tee "$STEAM_HOME/.local/share/Steam/steam.cfg" \
        "$STEAM_HOME/.local/share/Steam/steamrtarm64/steam.cfg" >/dev/null

# Ownership if rootfs uid mapping is normal
if grep -q '^steam:' "$ROOT/etc/passwd" 2>/dev/null; then
  steam_uid="$(awk -F: '$1=="steam"{print $3}' "$ROOT/etc/passwd")"
  steam_gid="$(awk -F: '$1=="steam"{print $4}' "$ROOT/etc/passwd")"
  if [[ -n "$steam_uid" && -n "$steam_gid" ]]; then
    chown -R "${steam_uid}:${steam_gid}" "$STEAM_HOME/.steam" \
      "$STEAM_HOME/.local/share/Steam/config" \
      "$STEAM_HOME/.local/share/Steam/steam.cfg" \
      "$STEAM_HOME/.local/share/Steam/steamrtarm64/steam.cfg" 2>/dev/null || true
  fi
fi

echo
echo "Listo. Primer inicio = sin CompletedOOBE, sin loginusers, sin Wi-Fi guardada."
echo "Reinicia el handheld. Deberías ver idioma / red (no login)."
echo "Nota: si pruebas en un root ya booteado, borra también conexiones NM en vivo:"
echo "  sudo rm -f /etc/NetworkManager/system-connections/* && sudo nmcli conn reload"
