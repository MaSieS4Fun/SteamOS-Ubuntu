#!/usr/bin/env bash
# Diagnose why QAM "Nivel de la interfaz de rendimiento" is stuck (read-only).
# Usage: ./scripts/DIAGNOSE-QAM-OVERLAY.sh [/media/odin2/STORAGE]
set -euo pipefail
ROOTFS="${1:-/media/odin2/STORAGE}"
STEAM_HOME="${ROOTFS}/home/steam"
LOG="${ROOTFS}/var/log/steamos-session.log"
PERF="${STEAM_HOME}/.local/share/Steam/logs/systemperfmanager.txt"
DISP="${STEAM_HOME}/.local/share/Steam/logs/systemdisplaymanager.txt"
REPO_GS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/system_files/usr/bin/gamescope-session"

echo "========== QAM overlay diagnosis =========="
echo "rootfs: $ROOTFS"
findmnt -n -o SOURCE,FSTYPE,OPTIONS --target "$ROOTFS" 2>/dev/null || true
echo

echo "--- 1) Session script on SD vs repo ---"
if [[ -f "${ROOTFS}/usr/bin/gamescope-session" ]]; then
  echo "SD:   $(wc -c <"${ROOTFS}/usr/bin/gamescope-session") bytes, $(stat -c %y "${ROOTFS}/usr/bin/gamescope-session" | cut -d. -f1)"
  grep -E 'XDG_SESSION_TYPE=|--mangoapp|STEAM_GAMESCOPE_FANCY|sibling mangoapp|MANGOHUD_CONFIGFILE=' \
    "${ROOTFS}/usr/bin/gamescope-session" | head -20 || true
else
  echo "SD: MISSING gamescope-session"
fi
if [[ -f "$REPO_GS" ]]; then
  echo "REPO: $(wc -c <"$REPO_GS") bytes"
  grep -E 'XDG_SESSION_TYPE=|sibling mangoapp|STEAM_GAMESCOPE_FANCY|MANGOHUD_CONFIGFILE=' \
    "$REPO_GS" | head -15 || true
  if ! cmp -s "$REPO_GS" "${ROOTFS}/usr/bin/gamescope-session" 2>/dev/null; then
    echo ">>> SD session script is OUT OF DATE vs repo (hot-fix never landed)."
  else
    echo ">>> SD session script matches repo."
  fi
fi
echo

echo "--- 2) Steam display manager (this blocks the overlay slider) ---"
if [[ -f "$DISP" ]]; then
  grep -E 'Initialized system display manager|primary' "$DISP" | tail -8
  if grep -q 'Initialized system display manager: X11' "$DISP"; then
    echo ">>> Steam is using X11 display manager (want: wayland: modeset)."
  fi
else
  echo "missing $DISP"
fi
echo

echo "--- 3) Steam perf manager ---"
if [[ -f "$PERF" ]]; then
  tail -12 "$PERF"
  if grep -q 'no primary display' "$PERF"; then
    echo ">>> SystemPerfManager: no primary display → overlay level stays inactive."
  fi
else
  echo "missing $PERF"
fi
echo

echo "--- 4) Session exports GAMESCOPE_WAYLAND? ---"
if [[ -f "$LOG" ]]; then
  grep -E 'GAMESCOPE_WAYLAND_DISPLAY=|launch-steam:|xrandr:|mangoapp' "$LOG" | tail -15
else
  echo "missing session log"
fi
echo

echo "--- 5) Mango conf (NOT the main bug if display is X11) ---"
ls -la "${STEAM_HOME}/.config/MangoHud/steam/" 2>/dev/null || echo "no steam mango dir"
cat "${STEAM_HOME}/.config/MangoHud/steam/MangoHud.conf" 2>/dev/null || true
echo

echo "========== Verdict =========="
echo "Power/Balanced/Performance = steamos-manager (works separately)."
echo "Overlay level + Advanced view need Steam Wayland display manager +"
echo "  primary display. Your logs show X11 + no primary → slider locked."
echo "Fix path: remount SD rw, run APPLY-QAM-MANGO-NOW.sh, re-enter Gaming Mode,"
echo "  then re-check systemdisplaymanager.txt for 'wayland: modeset'."
echo "=========================================="
