#!/usr/bin/env bash
# Inspect unified multi-device boot/KERNEL cmdline (ABL picks DTB — no devicetree= here).
set -euo pipefail

KERNEL="${1:-/boot/KERNEL}"

if [[ ! -f "$KERNEL" ]]; then
  echo "ERROR: missing ${KERNEL}" >&2
  exit 1
fi

if ! command -v abootimg >/dev/null 2>&1; then
  echo "Install abootimg to inspect cmdline: sudo apt install abootimg" >&2
  exit 1
fi

cmdline="$(abootimg -i "$KERNEL" 2>/dev/null | sed -n 's/^\* cmdline = //p' | head -1)"
echo "KERNEL: ${KERNEL}"
echo "cmdline: ${cmdline:-<empty>}"
echo
echo "NOTE: one bootimg for all SM8550 devices — ABL selector picks DTB."
echo "      Do NOT repack KERNEL for panel-hold; use apply-quiet-boot.sh (userspace)."
echo "      Per-SD UUID repack: sudo ./vendor/kernel/update.sh on each card."
echo

if [[ "$cmdline" == *console=tty0* ]]; then
  echo "FAIL: console=tty0 — kernel spam on panel"
  echo "      fix: reflash/rebuild image (CMDLINE_QUIET=1 in build_unified_abl_cmdline)"
  echo "      or:  sudo ./vendor/kernel/update.sh from updated kernel build"
  echo "      also: sudo ./scripts/apply-quiet-boot.sh (panel-hold, no KERNEL touch)"
  echo
fi

if [[ "$cmdline" == *quiet* ]]; then
  echo "quiet: yes"
else
  echo "quiet: NO"
fi

if [[ "$cmdline" == *console=tty0* ]]; then
  echo "console=tty0: yes"
elif [[ "$cmdline" == *console=* ]]; then
  echo "console: $(sed -n 's/.*console=\([^ ]*\).*/\1/p' <<<"$cmdline")"
else
  echo "console=tty0: no  (good for all devices)"
fi

if [[ "$cmdline" == *loglevel=* ]]; then
  echo "loglevel: $(sed -n 's/.*loglevel=\([^ ]*\).*/\1/p' <<<"$cmdline")"
else
  echo "loglevel: not set (kernel default = verbose)"
fi

if [[ "$cmdline" == *ignore_loglevel* || "$cmdline" == *masi.bootlog* ]]; then
  echo "WARN: debug cmdline tokens — verbose panel on every device"
fi

if [[ "$cmdline" == *devicetree=* || "$cmdline" == *" dtb="* ]]; then
  echo "WARN: devicetree=/dtb= in cmdline — must not (ABL selects DTB)"
fi

if [[ -f /boot/LinuxLoader.cfg ]]; then
  echo
  echo "LinuxLoader.cfg: UUID tools only; ABL boots from KERNEL cmdline above."
fi
