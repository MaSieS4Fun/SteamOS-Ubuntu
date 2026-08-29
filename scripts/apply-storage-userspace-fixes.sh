#!/usr/bin/env bash
# Apply FEX + maliit + Kate/polkit Desktop fixes onto a mounted STORAGE rootfs.
# Does NOT rebuild the image — for live testing before the next --finalize-img.
#
# Usage:
#   sudo ./scripts/apply-storage-userspace-fixes.sh /run/media/masies/STORAGE
#   sudo APPLY_STEAMUI_ONLY=1 ./scripts/apply-storage-userspace-fixes.sh /run/media/masies/STORAGE
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-/run/media/masies/STORAGE}"
SRC="${ROOT_DIR}/system_files"

log() { printf '==> [userspace] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -d "${ROOTFS}/usr" ]] || die "Usage: $0 <mounted-rootfs>"
ROOTFS="${ROOTFS%/}"

# Remount RW if udisks left it ro / errors=remount-ro
if findmnt -no OPTIONS "$ROOTFS" 2>/dev/null | grep -q '\bro\b'; then
  log "Remounting ${ROOTFS} read-write"
  mount -o remount,rw "$ROOTFS" || die "Could not remount RW"
fi

STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "${ROOTFS}/etc/passwd" 2>/dev/null || echo 1000)"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "${ROOTFS}/etc/passwd" 2>/dev/null || echo 1000)"

install_steamui_update_fix() {
  log "SteamUI: ignore Client Blocked when no updates (error 40 dialog)"
  install -D -m 0755 \
    "${SRC}/usr/libexec/steamos-ubuntu/patch-steamui-update-check" \
    "${ROOTFS}/usr/libexec/steamos-ubuntu/patch-steamui-update-check"
  install -D -m 0755 \
    "${SRC}/usr/libexec/steamos-ubuntu/launch-steam" \
    "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"
  install -D -m 0755 \
    "${SRC}/usr/libexec/steamos-ubuntu/patch-steamui-update-check" \
    "${ROOTFS}/home/steam/.local/share/steamos-ubuntu/patch-steamui-update-check"
  chown "${STEAM_UID}:${STEAM_GID}" \
    "${ROOTFS}/home/steam/.local/share/steamos-ubuntu" \
    "${ROOTFS}/home/steam/.local/share/steamos-ubuntu/patch-steamui-update-check" 2>/dev/null || true
  STEAM_ROOT="${ROOTFS}/home/steam/.local/share/Steam" \
    "${ROOTFS}/usr/libexec/steamos-ubuntu/patch-steamui-update-check" || true
}

# Fast path: only the update-check permanent fix
if [[ "${APPLY_STEAMUI_ONLY:-0}" == "1" ]]; then
  install_steamui_update_fix
  sync
  log "Done (SteamUI only) on ${ROOTFS}"
  exit 0
fi

# --- 1) Kate / Dolphin root save (polkit agent + rules + greetd) -------------
log "1/6 Kate: polkit agent + greetd + desktop-admin rules"
install -D -m 0644 \
  "${SRC}/etc/polkit-1/rules.d/60-steamos-desktop-admin.rules" \
  "${ROOTFS}/etc/polkit-1/rules.d/60-steamos-desktop-admin.rules"
# polkitd must read rules.d (750). Always use the IMAGE numeric GID — host
# `chown root:polkitd` resolves the host's polkitd (often wrong GID; on this
# builder bluetooth is 990 while STORAGE polkitd is 990 → silent break).
_pk_gid="$(awk -F: '$1=="polkitd"{print $3; exit}' "${ROOTFS}/etc/group" 2>/dev/null || true)"
if [[ -n "${_pk_gid}" ]]; then
  chown "0:${_pk_gid}" "${ROOTFS}/etc/polkit-1/rules.d" 2>/dev/null || true
  chmod 750 "${ROOTFS}/etc/polkit-1/rules.d" 2>/dev/null || true
fi
unset _pk_gid
chown root:root "${ROOTFS}/etc/polkit-1/rules.d/"*.rules 2>/dev/null || true
# Allow XDG autostart of the stock agent under greetd (systemd skip leaves it dead)
if [[ -f "${ROOTFS}/etc/xdg/autostart/polkit-kde-authentication-agent-1.desktop" ]]; then
  sed -i 's/^X-systemd-skip=true/X-systemd-skip=false/' \
    "${ROOTFS}/etc/xdg/autostart/polkit-kde-authentication-agent-1.desktop" || true
fi
install -D -m 0644 \
  "${SRC}/usr/lib/systemd/user/plasma-polkit-agent.service.d/after-wayland.conf" \
  "${ROOTFS}/usr/lib/systemd/user/plasma-polkit-agent.service.d/after-wayland.conf"
install -D -m 0755 \
  "${SRC}/usr/local/bin/steamos-greetd-session" \
  "${ROOTFS}/usr/local/bin/steamos-greetd-session"
install -D -m 0755 \
  "${SRC}/usr/libexec/steamos-ubuntu/ensure-plasma-polkit-agent" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/ensure-plasma-polkit-agent"
install -D -m 0755 \
  "${SRC}/usr/libexec/steamos-ubuntu/ensure-decky-plugin-loader" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/ensure-decky-plugin-loader"
install -D -m 0755 \
  "${SRC}/usr/bin/gamescope-session" \
  "${ROOTFS}/usr/bin/gamescope-session"
install -D -m 0644 \
  "${SRC}/etc/xdg/autostart/steamos-polkit-agent-guard.desktop" \
  "${ROOTFS}/etc/xdg/autostart/steamos-polkit-agent-guard.desktop"
if [[ -f "${SRC}/usr/share/kio/servicemenus/kate-edit-as-admin.desktop" ]]; then
  install -D -m 0644 \
    "${SRC}/usr/share/kio/servicemenus/kate-edit-as-admin.desktop" \
    "${ROOTFS}/usr/share/kio/servicemenus/kate-edit-as-admin.desktop"
fi
if [[ -f "${ROOTFS}/usr/lib/systemd/user/plasma-polkit-agent.service" ]]; then
  for wants in \
    "${ROOTFS}/home/steam/.config/systemd/user/plasma-workspace.target.wants" \
    "${ROOTFS}/etc/systemd/user/plasma-workspace.target.wants"
  do
    mkdir -p "$wants"
    ln -sfn /usr/lib/systemd/user/plasma-polkit-agent.service \
      "${wants}/plasma-polkit-agent.service"
  done
  rm -f \
    "${ROOTFS}/home/steam/.config/systemd/user/graphical-session.target.wants/plasma-polkit-agent.service" \
    "${ROOTFS}/etc/systemd/user/graphical-session.target.wants/plasma-polkit-agent.service" \
    2>/dev/null || true
fi
# Narrow sudoers if the broken NOPASSWD:ALL is still present
if [[ -f "${SRC}/etc/sudoers.d/99-steam-oobe-helpers" ]]; then
  rm -f "${ROOTFS}/etc/sudoers.d/99-steam-user"
  install -D -m 0440 \
    "${SRC}/etc/sudoers.d/99-steam-oobe-helpers" \
    "${ROOTFS}/etc/sudoers.d/99-steam-oobe-helpers"
  chown root:root "${ROOTFS}/etc/sudoers.d/99-steam-oobe-helpers"
fi

# --- 2) FEXEmu installer ----------------------------------------------------
log "2/6 FEXEmu: install-fexemu + menu entry (sudo in konsole)"
install -D -m 0755 \
  "${ROOT_DIR}/scripts/install-fexemu.sh" \
  "${ROOTFS}/usr/bin/install-fexemu"
install -d "${ROOTFS}/usr/share/applications"
cat >"${ROOTFS}/usr/share/applications/install-fexemu.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=FEXEmu
Comment=Install/update or uninstall FEX-Emu (x86_64 on ARM)
Exec=konsole -e bash -c 'sudo /usr/bin/install-fexemu; echo; read -r -p "Press Enter to close..."'
Icon=utilities-terminal
Terminal=false
Categories=System;Utility;X-ARM-Manager;
Keywords=fex;fexemu;x86;emulation;wine;arm;box64;
StartupNotify=true
EOF
# Refresh ARM-Manager desktop copy if present under another name
if [[ -f "${ROOTFS}/usr/share/applications/update-box64.desktop" ]]; then
  # keep Box64; FEX entry is install-fexemu.desktop above
  true
fi

# --- 2b) Decky installer ----------------------------------------------------
log "2b/6 Decky: install-decky + menu (requiere Box64 o FEX en el dispositivo)"
if [[ -f "${ROOT_DIR}/scripts/install-decky.sh" ]]; then
  install -D -m 0755 \
    "${ROOT_DIR}/scripts/install-decky.sh" \
    "${ROOTFS}/usr/bin/install-decky"
  if [[ -f "${ROOT_DIR}/vendor/Deky/decky_installer.desktop" ]]; then
    install -D -m 0644 \
      "${ROOT_DIR}/vendor/Deky/decky_installer.desktop" \
      "${ROOTFS}/usr/share/applications/install-decky.desktop"
  fi
  _LSFG_DIR="${ROOT_DIR}/vendor/system-fixes/LSFG-VK/plugin_loader.service.d"
  for _drop in fast-stop.conf fex-steam-rootfs.conf; do
    [[ -f "${_LSFG_DIR}/${_drop}" ]] || continue
    install -D -m 0644 "${_LSFG_DIR}/${_drop}" \
      "${ROOTFS}/etc/systemd/system/plugin_loader.service.d/${_drop}"
  done
  if [[ -f "${SRC}/etc/systemd/system/plugin_loader.service.d/steamos-ubuntu.conf" ]]; then
    install -D -m 0644 \
      "${SRC}/etc/systemd/system/plugin_loader.service.d/steamos-ubuntu.conf" \
      "${ROOTFS}/etc/systemd/system/plugin_loader.service.d/steamos-ubuntu.conf"
  fi
  if [[ -f "${SRC}/etc/sudoers.d/99-steam-decky-plugin-loader" ]]; then
    install -D -m 0440 \
      "${SRC}/etc/sudoers.d/99-steam-decky-plugin-loader" \
      "${ROOTFS}/etc/sudoers.d/99-steam-decky-plugin-loader"
  fi
  install -D -m 0755 \
    "${SRC}/usr/libexec/steamos-ubuntu/ensure-decky-plugin-loader" \
    "${ROOTFS}/usr/libexec/steamos-ubuntu/ensure-decky-plugin-loader"
  install -D -m 0755 \
    "${SRC}/usr/bin/gamescope-session" \
    "${ROOTFS}/usr/bin/gamescope-session"
fi

# Desktop Gaming Mode from vendor (steambp + adapted steamos-session-select)
if [[ -x "${ROOT_DIR}/scripts/install-desktop-gamemode.sh" ]]; then
  log "2c/6 Desktop Gaming Mode (vendor/Desktop_gamemode)"
  "${ROOT_DIR}/scripts/install-desktop-gamemode.sh" "$ROOTFS"
fi

# --- 3) Maliit keyboard -----------------------------------------------------
log "3/6 Maliit: apt install + KWin InputMethod (no QT_IM_MODULE under Plasma)"
need_umount=0
# resolv.conf is often a symlink to ../run/NetworkManager/resolv.conf — that
# target does not exist on a host-mounted STORAGE and `> resolv.conf` aborts
# under set -e. Replace with a real file for chroot apt, then restore.
resolv="${ROOTFS}/etc/resolv.conf"
resolv_bak="${ROOTFS}/etc/resolv.conf.bak.userspace"
resolv_link=""
if [[ -L "$resolv" ]]; then
  resolv_link="$(readlink "$resolv" || true)"
  cp -a "$resolv" "$resolv_bak" 2>/dev/null || true
  rm -f "$resolv"
elif [[ -e "$resolv" ]]; then
  cp -a "$resolv" "$resolv_bak" 2>/dev/null || true
fi
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' >"$resolv" || true
if [[ -r /etc/resolv.conf ]]; then
  awk '/^nameserver/ && $2 !~ /^127\./ {print}' /etc/resolv.conf >>"$resolv" 2>/dev/null || true
fi

mountpoint -q "${ROOTFS}/proc" || { mount -t proc proc "${ROOTFS}/proc"; need_umount=1; }
mountpoint -q "${ROOTFS}/sys" || { mount -t sysfs sysfs "${ROOTFS}/sys"; need_umount=1; }
mountpoint -q "${ROOTFS}/dev" || { mount --bind /dev "${ROOTFS}/dev"; need_umount=1; }
mountpoint -q "${ROOTFS}/run" || { mkdir -p "${ROOTFS}/run"; mount --bind /run "${ROOTFS}/run"; need_umount=1; }
chroot "$ROOTFS" apt-get update -y || true
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
  maliit-keyboard \
  maliit-server-qt5 maliit-inputcontext-qt5 libmaliit-plugins2 \
  maliit-server-qt6 maliit-inputcontext-qt6 libmaliit6-plugins2 \
  polkit-kde-agent-1 kio-admin kate \
  || true
# Restore original resolv (symlink preferred)
rm -f "$resolv"
if [[ -n "$resolv_link" ]]; then
  ln -sfn "$resolv_link" "$resolv" || true
elif [[ -e "$resolv_bak" && ! -L "$resolv_bak" ]]; then
  mv -f "$resolv_bak" "$resolv" || true
elif [[ -L "$resolv_bak" ]]; then
  resolv_link="$(readlink "$resolv_bak" || true)"
  [[ -n "$resolv_link" ]] && ln -sfn "$resolv_link" "$resolv" || true
  rm -f "$resolv_bak"
fi
rm -f "$resolv_bak" 2>/dev/null || true
# If restore failed, leave a working symlink for the handheld
if [[ ! -e "$resolv" && ! -L "$resolv" ]]; then
  ln -sfn ../run/NetworkManager/resolv.conf "$resolv" || true
fi
if [[ -x "${ROOTFS}/usr/bin/maliit-keyboard" ]]; then
  cat >"${ROOTFS}/usr/share/applications/maliit-keyboard.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Maliit Keyboard
Name[es]=Teclado Maliit
Comment=On-screen keyboard
Exec=maliit-keyboard
Icon=input-keyboard
Terminal=false
Categories=Utility;Accessibility;
EOF
  install -D -m 0644 "${SRC}/etc/profile.d/maliit-im.sh" "${ROOTFS}/etc/profile.d/maliit-im.sh"
  install -D -m 0644 "${SRC}/etc/xdg/kwinrc" "${ROOTFS}/etc/xdg/kwinrc"
  # Merge Maliit VK into steam user's kwinrc (System Settings may already have toggled it)
  STEAM_HOME="${ROOTFS}/home/steam"
  mkdir -p "${STEAM_HOME}/.config"
  python3 - "${STEAM_HOME}/.config/kwinrc" <<'PY' || true
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8", errors="replace") if p.is_file() else ""
want_im = "/usr/share/applications/com.github.maliit.keyboard.desktop"
if "VirtualKeyboardEnabled=true" in text and want_im in text:
    raise SystemExit(0)
lines = [ln for ln in text.splitlines() if not ln.startswith("InputMethod") and not ln.startswith("VirtualKeyboardEnabled")]
out, skip = [], False
for ln in lines:
    if ln.strip() == "[Wayland]":
        skip = True
        continue
    if skip and ln.startswith("["):
        skip = False
    if skip:
        continue
    out.append(ln)
while out and not out[-1].strip():
    out.pop()
out += ["", "[Wayland]", f"InputMethod[$e]={want_im}", "VirtualKeyboardEnabled=true", ""]
p.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
PY
  chown "${STEAM_UID}:${STEAM_GID}" "${STEAM_HOME}/.config/kwinrc" 2>/dev/null || true
  log "maliit-keyboard + KWin InputMethod OK"
else
  log "WARN: maliit-keyboard binary still missing after apt (check network in chroot)"
fi
if [[ -x "${ROOT_DIR}/scripts/unmount-rootfs-binds.sh" ]]; then
  "${ROOT_DIR}/scripts/unmount-rootfs-binds.sh" "$ROOTFS" 2>/dev/null || true
elif [[ "$need_umount" -eq 1 ]]; then
  umount -l "${ROOTFS}/run" "${ROOTFS}/dev" "${ROOTFS}/sys" "${ROOTFS}/proc" 2>/dev/null || true
fi

chown -R "${STEAM_UID}:${STEAM_GID}" \
  "${ROOTFS}/home/steam/.config/systemd" 2>/dev/null || true

# --- 4) SM8550 HiFi + HDMI/DP audio policy watcher ---------------------------
log "5/6 Audio: sm8550-prefer-speaker-sink watcher + HiFi WP priority"
install -D -m 0755 \
  "${SRC}/usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/sm8550-prefer-speaker-sink"
install -D -m 0644 \
  "${SRC}/usr/lib/systemd/user/sm8550-prefer-speaker-sink.service" \
  "${ROOTFS}/usr/lib/systemd/user/sm8550-prefer-speaker-sink.service"
if [[ -f "${SRC}/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" ]]; then
  install -D -m 0644 \
    "${SRC}/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" \
    "${ROOTFS}/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf"
fi
for wants in \
  "${ROOTFS}/etc/skel/.config/systemd/user/default.target.wants" \
  "${ROOTFS}/home/steam/.config/systemd/user/default.target.wants" \
  "${ROOTFS}/etc/systemd/user/default.target.wants"; do
  mkdir -p "${wants}"
  ln -sfn /usr/lib/systemd/user/sm8550-prefer-speaker-sink.service \
    "${wants}/sm8550-prefer-speaker-sink.service"
done
chown -R "${STEAM_UID}:${STEAM_GID}" \
  "${ROOTFS}/home/steam/.config/systemd" 2>/dev/null || true

# --- 5) SteamUI update-check Blocked(40) fix (BootStrapperInhibitAll) --------
log "6/7 SteamUI: ignore Client Blocked when no updates (error 40 dialog)"
install_steamui_update_fix

# --- 6) InputPlumber (Odin2 rsinput → deck-uhid for Steam) --------------------
if [[ -x "${ROOT_DIR}/scripts/install-inputplumber.sh" ]]; then
  log "7/7 InputPlumber (deck-uhid)"
  "${ROOT_DIR}/scripts/install-inputplumber.sh" "$ROOTFS" || \
    log "WARN: InputPlumber install failed — run sudo ./scripts/install-inputplumber.sh later"
fi

sync
log "Done on ${ROOTFS}"
echo
echo "Eject/unmount the SD, boot the handheld, then test:"
echo "  1) Desktop → Kate open /etc/hostname → Save → password dialog"
echo "  2) ARM Manager → FEXEmu → should ask sudo password in Konsole"
echo "  3) Desktop → tap a text field → Maliit OSK (Virtual Keyboard on)"
echo "  4) Desktop audio: HiFi (not Pro Audio); HDMI plug switches DisplayPort"
echo "  5) Gaming Mode → System → Check for updates → no error dialog"
echo "  6) Gaming Mode → Settings → Controller: Steam Deck / Handheld via InputPlumber"
echo
echo "Tip: only the update-check fix:"
echo "  sudo APPLY_STEAMUI_ONLY=1 $0 ${ROOTFS}"
