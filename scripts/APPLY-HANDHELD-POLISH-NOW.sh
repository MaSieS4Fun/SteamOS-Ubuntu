#!/usr/bin/env bash
# Hot-fix handheld polish onto a live STORAGE / rootfs (no full image rebuild).
# Applies: Plasma screen-lock OFF, stick SDL map, gamescope-session,
# mangoapp-steam dual-binary wiring, system MangoHud presets, Mesa apt hold,
# expand-rootfs, Plasma 150% + power→sleep defaults, gaming volume-keys.
#
# Usage:
#   sudo ./scripts/APPLY-HANDHELD-POLISH-NOW.sh /media/odin2/STORAGE
#   sudo ./scripts/APPLY-HANDHELD-POLISH-NOW.sh /home/odin2/Desktop/SteamOS-Ubuntu/output/rootfs
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
log() { printf '==> [polish] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs|STORAGE>"

SRC="${ROOT_DIR}/system_files"
STEAM_HOME="${ROOTFS}/home/steam"
MANGO_SRC="${ROOT_DIR}/vendor/MangoHud/MangoHud"

install -D -m 0644 "${SRC}/etc/xdg/kscreenlockerrc" "${ROOTFS}/etc/xdg/kscreenlockerrc"
install -D -m 0644 "${SRC}/etc/skel/.config/kscreenlockerrc" \
  "${ROOTFS}/etc/skel/.config/kscreenlockerrc"
install -D -m 0644 "${SRC}/etc/sdl2/qcom-gamecontrollerdb.txt" \
  "${ROOTFS}/etc/sdl2/qcom-gamecontrollerdb.txt"
install -D -m 0644 "${SRC}/usr/lib/environment.d/60-steamos-sdl-gamepad.conf" \
  "${ROOTFS}/usr/lib/environment.d/60-steamos-sdl-gamepad.conf" 2>/dev/null || true
install -D -m 0755 "${SRC}/usr/bin/gamescope-session" "${ROOTFS}/usr/bin/gamescope-session"
install -D -m 0755 "${SRC}/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"
install -D -m 0755 "${SRC}/usr/libexec/steamos-ubuntu/expand-rootfs" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/expand-rootfs"
install -D -m 0755 "${SRC}/usr/libexec/steamos-ubuntu/volume-keys" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/volume-keys"
install -D -m 0644 "${SRC}/etc/systemd/system/steamos-expand-rootfs.service" \
  "${ROOTFS}/etc/systemd/system/steamos-expand-rootfs.service"
for f in kdeglobals kwinrc powerdevilrc kscreenlockerrc; do
  [[ -f "${SRC}/etc/xdg/${f}" ]] || continue
  install -D -m 0644 "${SRC}/etc/xdg/${f}" "${ROOTFS}/etc/xdg/${f}"
done
install -D -m 0644 \
  "${ROOT_DIR}/config/apt-preferences/99-block-ubuntu-mesa" \
  "${ROOTFS}/etc/apt/preferences.d/99-block-ubuntu-mesa"
# shellcheck source=lib/mesa-hold-packages.sh
source "${ROOT_DIR}/scripts/lib/mesa-hold-packages.sh"
chroot "$ROOTFS" apt-mark hold "${MESA_HOLD_PKGS[@]}" 2>/dev/null || true
log "Mesa packages pinned+held (Discover will not upgrade stock Mesa)"

# Seed Plasma defaults into steam home if missing
if [[ -d "$STEAM_HOME" ]]; then
  install -d "${STEAM_HOME}/.config"
  for f in kdeglobals kwinrc powerdevilrc kscreenlockerrc; do
    if [[ -f "${SRC}/etc/xdg/${f}" && ! -f "${STEAM_HOME}/.config/${f}" ]]; then
      cp -a "${SRC}/etc/xdg/${f}" "${STEAM_HOME}/.config/${f}"
    fi
  done
fi

chroot "$ROOTFS" systemctl enable steamos-expand-rootfs.service 2>/dev/null || true
mkdir -p "${ROOTFS}/etc/systemd/system/local-fs.target.wants"
ln -sfn /etc/systemd/system/steamos-expand-rootfs.service \
  "${ROOTFS}/etc/systemd/system/local-fs.target.wants/steamos-expand-rootfs.service" 2>/dev/null || true
# Drop marker so next boot (or manual run) can grow if card still has free space
rm -f "${ROOTFS}/var/lib/steamos-ubuntu/rootfs-expanded" 2>/dev/null || true
log "Enabled steamos-expand-rootfs (growpart+resize2fs, no reboot)"

# System copy of overlay configs (same tree as user ~/.config/MangoHud)
if [[ -d "$MANGO_SRC" ]]; then
  install -d "${ROOTFS}/usr/share/sm8550-steamos/MangoHud"
  cp -a "${MANGO_SRC}/." "${ROOTFS}/usr/share/sm8550-steamos/MangoHud/"
  log "Installed system MangoHud configs → /usr/share/sm8550-steamos/MangoHud"
fi

# Dual binary needs the steam-subdir patch in libMangoHud — rebuild if missing.
need_mango_rebuild=0
[[ -x "${ROOTFS}/usr/bin/mangoapp" ]] || need_mango_rebuild=1
[[ -x "${ROOTFS}/usr/bin/mangoapp-steam" ]] || need_mango_rebuild=1
lib_has_steam=0
while IFS= read -r -d '' so; do
  if strings "$so" 2>/dev/null | grep -q 'MangoHud/steam'; then
    lib_has_steam=1
    break
  fi
done < <(find "${ROOTFS}/usr" -name 'libMangoHud.so*' -print0 2>/dev/null)
[[ "$lib_has_steam" -eq 1 ]] || need_mango_rebuild=1
if [[ "$need_mango_rebuild" -eq 1 ]]; then
  log "Building vendor MangoHud (mangoapp + mangoapp-steam, steam/ default path)"
  FORCE_REBUILD=1 "${ROOT_DIR}/scripts/build-vendor-mangohud.sh" "$ROOTFS"
else
  if [[ -x "${ROOTFS}/usr/bin/mangoapp" && ! -x "${ROOTFS}/usr/bin/mangoapp-steam" ]]; then
    install -D -m 0755 "${ROOTFS}/usr/bin/mangoapp" "${ROOTFS}/usr/bin/mangoapp-steam"
  fi
  log "mangoapp + mangoapp-steam OK (steam profile in lib)"
  # Rebuild already copies configs; when skipping rebuild, copy only.
  if [[ -d "$MANGO_SRC" && -d "$STEAM_HOME" ]]; then
    install -d "${STEAM_HOME}/.config/MangoHud"
    cp -a "${MANGO_SRC}/." "${STEAM_HOME}/.config/MangoHud/"
    log "Copied overlay configs → /home/steam/.config/MangoHud/"
  fi
fi

if [[ -d "$STEAM_HOME" ]]; then
  install -d "${STEAM_HOME}/.config"
  cp -a "${ROOTFS}/etc/xdg/kscreenlockerrc" "${STEAM_HOME}/.config/kscreenlockerrc" 2>/dev/null || true
  rm -rf "${STEAM_HOME}/.local/share/Steam/compatibilitytools.d"/proton-cachyos-* 2>/dev/null || true
  chown -R --reference="$STEAM_HOME" "${STEAM_HOME}/.config" 2>/dev/null || true
fi

log "Done. Re-enter Gaming Mode (or reboot)."
log "Desktop: mangoapp → ~/.config/MangoHud/"
log "Gaming:  mangoapp-steam → ~/.config/MangoHud/steam/"
log "Kernel stick-drift fix still needs KERNEL rebuild (patch 1032) if not flashed yet."
