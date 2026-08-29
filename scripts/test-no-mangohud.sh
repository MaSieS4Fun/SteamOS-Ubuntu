#!/usr/bin/env bash
# Diagnostic: strip ALL MangoHud integration from Gaming Mode on a mounted rootfs.
# Lets us confirm whether MangoHud is the cause of CEF gpu-process hang.
#
# Usage: sudo ./scripts/test-no-mangohud.sh [/media/odin2/STORAGE]
set -euo pipefail

ROOTFS="${1:-/media/odin2/STORAGE}"
GS="${ROOTFS}/usr/bin/gamescope-session"
LS="${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"

log() { printf '==> [no-mango] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -f "$GS" ]] || die "gamescope-session not found"
[[ -f "$LS" ]] || die "launch-steam not found"

# Backup originals
cp -a "$GS" "${GS}.bak-mangohud"
cp -a "$LS" "${LS}.bak-mangohud"

### gamescope-session: strip MangoHud config seeding + mangoapp launch

# 1) Replace entire MangoHud config block with a no-op
sed -i '/^# Gaming overlay.*MangoHud/,/^# Do NOT export MANGOHUD/c\
# MangoHud: DISABLED for diagnostic test (no config seeding, no env exports)\
# Chimera still uses temp files for VRS + fps limiter' "$GS"

# 2) Replace mangoapp echo line
sed -i 's|^echo "mangoapp: CONFIGFILE=.*|echo "mangoapp: DISABLED for diagnostic test"|' "$GS"

# 3) Replace mangoapp supervisor block
sed -i '/# ChimeraOS: mangoapp sibling/,/echo "mangoapp supervisor pid/c\
  # MangoHud/mangoapp: DISABLED for diagnostic test\
  pkill -x mangoapp 2>/dev/null || true\
  mango_pid=' "$GS"

# 4) Unset STEAM_USE_MANGOAPP
sed -i 's|^export STEAM_USE_MANGOAPP=1|# export STEAM_USE_MANGOAPP=1  # DISABLED for test|' "$GS"
sed -i 's|^export STEAM_MANGOAPP_PRESETS_SUPPORTED=1|# export STEAM_MANGOAPP_PRESETS_SUPPORTED=1|' "$GS"
sed -i 's|^export STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1|# export STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1|' "$GS"
sed -i 's|^export STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1|# export STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1|' "$GS"

### launch-steam: strip MangoHud config/sanitize/env

# Replace the MangoHud block in launch-steam
sed -i '/^# Fixed mango paths/,/echo "launch-steam: MangoHud.*"/c\
# MangoHud: DISABLED for diagnostic test\
unset MANGOHUD_CONFIGFILE MANGOHUD_PRESETSFILE MANGOHUD_CONFIG MANGOHUD MANGOHUD_TOGGLE\
echo "launch-steam: MangoHud fully disabled (diagnostic mode)"' "$LS"

# Also strip any MANGOHUD from dbus-update-activation-environment
sed -i '/MANGOHUD_CONFIGFILE MANGOHUD_PRESETSFILE MANGOHUD_CONFIG/d' "$LS"

### Clean user MangoHud files that Steam sees
rm -f "${ROOTFS}/home/steam/.local/share/Steam/config/mangohud.conf"
rm -f "${ROOTFS}/home/steam/.config/MangoHud/steam/MangoHud.conf"
rm -f "${ROOTFS}/home/steam/.config/MangoHud/steam/MangoHud.conf.bak"

### Clear htmlcache
rm -rf "${ROOTFS}/home/steam/.local/share/Steam/config/htmlcache"
mkdir -p "${ROOTFS}/home/steam/.local/share/Steam/config/htmlcache"
STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "${ROOTFS}/etc/passwd")"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "${ROOTFS}/etc/passwd")"
[[ -n "$STEAM_UID" ]] && chown "${STEAM_UID}:${STEAM_GID}" \
  "${ROOTFS}/home/steam/.local/share/Steam/config/htmlcache"

log "Done. MangoHud completely stripped from Gaming Mode."
log "Backups: ${GS}.bak-mangohud, ${LS}.bak-mangohud"
log "Reboot SD → Gaming Mode → if CreateBrowser appears, MangoHud was the cause."
log "To restore: sudo cp ${GS}.bak-mangohud ${GS} && sudo cp ${LS}.bak-mangohud ${LS}"
