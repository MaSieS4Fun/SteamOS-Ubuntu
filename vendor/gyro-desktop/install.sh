#!/usr/bin/env bash
# Install GYRO-FIX desktop app + session hooks (pad always, DSU optional).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${ROOT}/../.." && pwd)"
ROOTFS="${1:-/}"

if [[ "${1:-}" == "--force" ]]; then
  ROOTFS="/"
fi

log() { printf '==> [gyro-desktop] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Live install to / needs root; deb staging into a rootfs path does not.
if [[ "${EUID}" -ne 0 && "${ROOTFS}" == "/" ]]; then
  die "Run as root"
fi

if [[ "$ROOTFS" != "/" ]]; then
  ROOTFS="${ROOTFS%/}"
  [[ -d "${ROOTFS}/usr" ]] || die "Not a rootfs: ${ROOTFS}"
fi

path() {
  if [[ "$ROOTFS" == "/" ]]; then printf '%s\n' "$1"; else printf '%s%s\n' "$ROOTFS" "$1"; fi
}

log "Install binaries → $(path /usr/bin)"
install -d "$(path /usr/bin)" "$(path /usr/share/gyro-desktop/bin)" \
  "$(path /usr/share/gyro-desktop/profiles)" \
  "$(path /usr/share/gyro-desktop/inputplumber)" \
  "$(path /usr/share/applications)" \
  "$(path /usr/share/icons/hicolor/256x256/apps)" \
  "$(path /usr/share/icons/hicolor/512x512/apps)" \
  "$(path /etc/xdg/autostart)" \
  "$(path /etc/sudoers.d)" \
  "$(path /var/lib/masi/gyro-desktop/profiles)"

for b in gyro-fix gyro-fix-dsu gyro-fix-apply gyro-desktop-plasma gyro-desktop-gamescope gyro-desktop-nested-gm; do
  install -m 0755 "${ROOT}/bin/${b}" "$(path /usr/bin)/${b}"
  install -m 0755 "${ROOT}/bin/${b}" "$(path /usr/share/gyro-desktop/bin)/${b}"
done

install -m 0644 "${ROOT}/share/applications/gyro-fix.desktop" \
  "$(path /usr/share/applications)/gyro-fix.desktop"
if [[ -f "${ROOT}/share/icons/hicolor/256x256/apps/gyro-fix.png" ]]; then
  install -m 0644 "${ROOT}/share/icons/hicolor/256x256/apps/gyro-fix.png" \
    "$(path /usr/share/icons/hicolor/256x256/apps)/gyro-fix.png"
fi
if [[ -f "${ROOT}/share/icons/hicolor/512x512/apps/gyro-fix.png" ]]; then
  install -m 0644 "${ROOT}/share/icons/hicolor/512x512/apps/gyro-fix.png" \
    "$(path /usr/share/icons/hicolor/512x512/apps)/gyro-fix.png"
elif [[ -f "${ROOT}/icons/gyro-fix.png" ]]; then
  install -m 0644 "${ROOT}/icons/gyro-fix.png" \
    "$(path /usr/share/icons/hicolor/512x512/apps)/gyro-fix.png"
fi

cp -a "${ROOT}/profiles/." "$(path /usr/share/gyro-desktop/profiles)/"
cp -a "${ROOT}/profiles/." "$(path /var/lib/masi/gyro-desktop/profiles)/" 2>/dev/null || true

if [[ -d "${REPO}/system_files/etc/inputplumber" ]]; then
  cp -a "${REPO}/system_files/etc/inputplumber/." "$(path /usr/share/gyro-desktop/inputplumber)/"
fi

# Deploy session hooks into the live/baked image (critical for single Deck pad in GM)
if [[ -f "${REPO}/system_files/usr/bin/gamescope-session" ]]; then
  log "Install gamescope-session (calls gyro-desktop-gamescope)"
  install -m 0755 "${REPO}/system_files/usr/bin/gamescope-session" \
    "$(path /usr/bin)/gamescope-session"
fi
if [[ -f "${REPO}/system_files/usr/bin/steamos-session-select" ]]; then
  install -m 0755 "${REPO}/system_files/usr/bin/steamos-session-select" \
    "$(path /usr/bin)/steamos-session-select"
fi
if [[ -f "${REPO}/system_files/usr/bin/steamos-desktop-gamescope" ]]; then
  install -m 0755 "${REPO}/system_files/usr/bin/steamos-desktop-gamescope" \
    "$(path /usr/bin)/steamos-desktop-gamescope"
fi
if [[ -f "${REPO}/vendor/Desktop_gamemode/steambp.desktop" ]]; then
  install -d "$(path /usr/local/share/applications)" "$(path /home/steam/Desktop)"
  install -m 0644 "${REPO}/vendor/Desktop_gamemode/steambp.desktop" \
    "$(path /usr/local/share/applications)/steambp.desktop"
  install -m 0755 "${REPO}/vendor/Desktop_gamemode/steambp.desktop" \
    "$(path /home/steam/Desktop)/steambp.desktop" 2>/dev/null || true
fi

install -m 0644 "${ROOT}/packaging/xdg/autostart/gyro-desktop-plasma.desktop" \
  "$(path /etc/xdg/autostart)/gyro-desktop-plasma.desktop"
install -m 0440 "${ROOT}/packaging/sudoers.d/gyro-desktop" \
  "$(path /etc/sudoers.d)/gyro-desktop"

STATE="$(path /var/lib/masi/gyro-desktop/state.ini)"
if [[ ! -f "$STATE" ]]; then
  cat >"$STATE" <<'EOF'
[desktop]
dsu_enabled=false
profile=default
EOF
fi

if [[ "$ROOTFS" == "/" ]]; then
  log "UI deps (Gtk3 for GYRO-FIX)"
  apt-get install -y --no-install-recommends python3-gi gir1.2-gtk-3.0 2>/dev/null || \
    log "WARN: could not apt-install Gtk3 GI — CLI fallback still works"

  systemctl stop qcom-motion.service 2>/dev/null || true
  systemctl disable qcom-motion.service 2>/dev/null || true

  # Detect session: if already in gamescope, apply GM pad; else desktop pad
  if [[ "${XDG_CURRENT_DESKTOP:-}" == *gamescope* ]] || [[ "${STEAMOS_SESSION:-}" == "1" ]]; then
    log "Gaming Mode session detected — apply deck-uhid + IMU"
    /usr/bin/gyro-desktop-gamescope || true
  else
    log "Desktop session — AYN pad only (InputPlumber stopped)"
    /usr/bin/gyro-desktop-plasma || true
  fi

  update-desktop-database /usr/share/applications 2>/dev/null || true
  gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
else
  mkdir -p "$(path /etc/systemd/system)"
  rm -f "$(path /etc/systemd/system/multi-user.target.wants)/qcom-motion.service" \
    "$(path /etc/systemd/system/graphical.target.wants)/qcom-motion.service" 2>/dev/null || true
  # Bake: also try to stage GI packages if chroot apt works (best-effort)
  if [[ -d "${ROOTFS}/usr" ]] && command -v chroot >/dev/null; then
    chroot "$ROOTFS" apt-get install -y --no-install-recommends python3-gi gir1.2-gtk-3.0 \
      2>/dev/null || true
  fi
fi

log "Done."
log "  Fix GM now:  sudo gyro-desktop-gamescope"
log "  Desktop pad:  sudo gyro-desktop-plasma"
log "  App:          gyro-fix"
