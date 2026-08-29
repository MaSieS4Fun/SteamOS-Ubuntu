#!/usr/bin/env bash
# Black panel until gamescope DRM — userspace only.
#
# Does NOT repack /boot/KERNEL. That file is one multi-device ABL bootimg
# (zImage + initrd + DTB chain); ABL picks the DTB. Per-SD root UUID repack
# is vendor/kernel/update.sh or image build — never here.
#
#   sudo ./scripts/apply-quiet-boot.sh
#   sudo ./scripts/apply-quiet-boot.sh /run/media/steam/STORAGE
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT_DIR}/system_files"
TARGET="${1:-/}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root: sudo $0 [/mounted/root]"
[[ "$TARGET" == "/" || -d "${TARGET}/usr" ]] || die "Not a rootfs: ${TARGET}"

if [[ "$TARGET" == "/" && -f /boot/KERNEL ]] && command -v abootimg >/dev/null 2>&1; then
  log "KERNEL cmdline (read-only — unified multi-device bootimg, ABL selects DTB)"
  "${ROOT_DIR}/scripts/verify-boot-cmdline.sh" /boot/KERNEL || true
  echo
  if abootimg -i /boot/KERNEL 2>/dev/null | sed -n 's/^\* cmdline = //p' | head -1 | grep -q console=tty0; then
    log "NOTE: console=tty0 still in KERNEL — rebuild/reflash image or run"
    log "      sudo ./vendor/kernel/update.sh from a build with CMDLINE_QUIET=1."
    log "      panel-hold below still blackens the panel without repacking KERNEL."
    echo
  fi
fi

log "Install quiet-console policy (all SM8550 devices)"
install -D -m 0644 \
  "${SRC}/etc/sysctl.d/20-quiet-console.conf" \
  "${TARGET}/etc/sysctl.d/20-quiet-console.conf"
install -D -m 0644 \
  "${SRC}/etc/systemd/system.conf.d/10-quiet-boot.conf" \
  "${TARGET}/etc/systemd/system.conf.d/10-quiet-boot.conf"
install -D -m 0644 \
  "${SRC}/etc/systemd/journald.conf.d/50-quiet-console.conf" \
  "${TARGET}/etc/systemd/journald.conf.d/50-quiet-console.conf"

log "Mask Plymouth"
for u in plymouth-start.service plymouth-read-write.service \
           plymouth-quit.service plymouth-quit-wait.service plymouth-quit-on-ready.service; do
  mkdir -p "${TARGET}/etc/systemd/system"
  ln -sfn /dev/null "${TARGET}/etc/systemd/system/${u}"
  rm -f \
    "${TARGET}/etc/systemd/system/multi-user.target.wants/${u}" \
    "${TARGET}/etc/systemd/system/sysinit.target.wants/${u}" \
    2>/dev/null || true
done

install -D -m 0644 \
  "${SRC}/usr/lib/tmpfiles.d/steamos-panel-hold.conf" \
  "${TARGET}/usr/lib/tmpfiles.d/steamos-panel-hold.conf"

log "Install steamos-panel-hold (black panel until gamescope ready)"
install -D -m 0755 \
  "${SRC}/usr/libexec/steamos-ubuntu/steamos-panel-hold" \
  "${TARGET}/usr/libexec/steamos-ubuntu/steamos-panel-hold"
install -D -m 0644 \
  "${SRC}/etc/systemd/system/steamos-panel-hold.service" \
  "${TARGET}/etc/systemd/system/steamos-panel-hold.service"
mkdir -p "${TARGET}/etc/systemd/system/multi-user.target.wants"
ln -sfn /etc/systemd/system/steamos-panel-hold.service \
  "${TARGET}/etc/systemd/system/multi-user.target.wants/steamos-panel-hold.service"
rm -f \
  "${TARGET}/usr/libexec/steamos-ubuntu/trim-panel-console" \
  "${TARGET}/etc/systemd/system/steamos-trim-panel-console.service" \
  "${TARGET}/etc/systemd/system/multi-user.target.wants/steamos-trim-panel-console.service" \
  "${TARGET}/etc/systemd/system/steamos-quiet-console.service" \
  "${TARGET}/etc/systemd/system/multi-user.target.wants/steamos-quiet-console.service" \
  2>/dev/null || true

if [[ "$TARGET" == "/" ]]; then
  systemd-tmpfiles --create "${SRC}/usr/lib/tmpfiles.d/steamos-panel-hold.conf" 2>/dev/null || true
  sysctl --system >/dev/null 2>&1 || true
  systemctl daemon-reload
  systemctl enable steamos-panel-hold.service 2>/dev/null || true
  systemctl restart systemd-journald 2>/dev/null || true
  cat <<EOF

Panel hold applied (userspace only — KERNEL untouched).

  sudo reboot

Black/empty panel until gamescope ready, then Steam UI.
Verify: ${ROOT_DIR}/scripts/diagnose-panel-log.sh

EOF
else
  sync "${TARGET}" 2>/dev/null || sync
  echo "Done on ${TARGET}. Boot the handheld."
fi
