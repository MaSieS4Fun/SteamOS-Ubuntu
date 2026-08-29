#!/usr/bin/env bash
# Panel diagnosis — respects unified multi-device KERNEL (no local repack).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say() { printf '%s\n' "$*"; }
hdr() { printf '\n=== %s ===\n' "$*"; }

hdr "Panel diagnosis (SM8550)"
say "Target: black panel until gamescope, then Steam UI."
say "KERNEL = one ABL bootimg for all devices; ABL picks DTB."
say ""

hdr "1) KERNEL cmdline (read-only)"
if [[ -f /boot/KERNEL ]] && command -v abootimg >/dev/null 2>&1; then
  "${ROOT_DIR}/scripts/verify-boot-cmdline.sh" /boot/KERNEL || true
else
  say "WARN: cannot inspect /boot/KERNEL"
fi

hdr "2) steamos-panel-hold (userspace — safe on all devices)"
if systemctl is-enabled steamos-panel-hold.service 2>/dev/null | grep -q enabled; then
  say "steamos-panel-hold: enabled"
else
  say "NOT enabled — sudo ${ROOT_DIR}/scripts/apply-quiet-boot.sh"
fi
say "This script does NOT repack KERNEL."

hdr "3) Apply on device"
say "sudo ${ROOT_DIR}/scripts/apply-quiet-boot.sh"
say "sudo reboot"
say ""
say "New image / per-SD UUID: rebuild or sudo ./vendor/kernel/update.sh"
say "Never copy boot/KERNEL between SD cards."
