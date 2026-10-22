#!/usr/bin/env bash
# Fix-PAD — restore the Xbox 360 layout after an InputPlumber or SDL update.
#
# The image ships this layout. An InputPlumber upgrade puts the package map
# back in /usr/share (X swapped with Y, LB left on RB). SDL's built-in DB
# does the same for desktop apps unless the environment file is present.
#
#   sudo fix-pad              # this system
#   sudo fix-pad /mnt/rootfs  # another root
set -euo pipefail

PAYLOAD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${PAYLOAD}/ayn_mcu.yaml" && -d /usr/share/fix-pad ]]; then
  PAYLOAD=/usr/share/fix-pad
fi

ROOTFS="/"
if [[ $# -ge 1 && -d "$1" ]]; then
  ROOTFS="$(cd "$1" && pwd)"
fi

log() { printf '==> [fix-pad] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root: sudo fix-pad"
[[ -f "${PAYLOAD}/ayn_mcu.yaml" ]] || die "Missing ${PAYLOAD}/ayn_mcu.yaml"

path() {
  if [[ "$ROOTFS" == "/" ]]; then
    printf '%s\n' "$1"
  else
    printf '%s%s\n' "$ROOTFS" "$1"
  fi
}

install_file() {
  local src="$1" dest="$2" mode="$3"
  install -d "$(dirname "$dest")"
  install -m "$mode" "$src" "$dest"
  log "wrote ${dest#${ROOTFS}}"
}

MAP_SHARE="/usr/share/inputplumber/capability_maps/ayn_mcu.yaml"
MAP_DIVERT="/usr/share/inputplumber/capability_maps/ayn_mcu.yaml.upstream"

if [[ -d "$(path /usr/share/inputplumber/capability_maps)" ]]; then
  if [[ "$ROOTFS" == "/" ]]; then
    divert=(dpkg-divert --local)
  else
    divert=(dpkg-divert --root "$ROOTFS" --local)
  fi
  if ! "${divert[@]}" --list "$MAP_SHARE" 2>/dev/null | grep -q "$MAP_SHARE"; then
    "${divert[@]}" --rename --divert "$MAP_DIVERT" --add "$MAP_SHARE" \
      || log "dpkg-divert skipped (map will still be overwritten)"
  fi
fi

install_file "${PAYLOAD}/ayn_mcu.yaml" "$(path "$MAP_SHARE")" 0644
install_file "${PAYLOAD}/ayn_mcu.yaml" \
  "$(path /etc/inputplumber/capability_maps.d/ayn_mcu.yaml)" 0644
install_file "${PAYLOAD}/qcom-gamecontrollerdb.txt" \
  "$(path /etc/sdl2/qcom-gamecontrollerdb.txt)" 0644
install_file "${PAYLOAD}/60-steamos-sdl-gamepad.conf" \
  "$(path /usr/lib/environment.d/60-steamos-sdl-gamepad.conf)" 0644
install_file "${PAYLOAD}/60-steamos-sdl-gamepad.conf" \
  "$(path /etc/environment.d/60-steamos-sdl-gamepad.conf)" 0644
install_file "${PAYLOAD}/steamos-sdl-gamepad.sh" \
  "$(path /etc/profile.d/steamos-sdl-gamepad.sh)" 0755

if [[ "$ROOTFS" == "/" ]] && command -v systemctl >/dev/null 2>&1; then
  systemctl restart inputplumber.service \
    && log "inputplumber restarted" \
    || log "inputplumber was not restarted (start it if the service is installed)"
fi

log "Xbox layout restored: X/Y follow the print, LB/RB are not crossed."
log "Desktop SDL2 picks this up on the next login."
