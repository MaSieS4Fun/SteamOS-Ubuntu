#!/usr/bin/env bash
# Fix broken Gaming Mode on a mounted SD (default: /media/odin2/STORAGE).
# Applies hypotheses in order; run one step at a time to isolate cause.
#
# Steps:
#   verify     — read-only: show Mesa stack vs golden (no changes)
#   mesa       — H1: sync libgallium + libvulkan_freedreno from golden SD/build
#   htmlcache  — H2: wipe Steam CEF cache (after mesa fix)
#   mango      — H3: reset MangoHud to control=mangoapp (hygiene, not A/B root cause)
#   cef-soft   — H4: force CEF/software webhelper (-cef-disable-gpu) to isolate GPU init hang
#   mesa-full  — H4: full vendor Mesa rebuild (meson compile + install + dummies)
#   all        — mesa + htmlcache + mango + verify (recommended first try)
#
# Usage:
#   sudo ./scripts/as-root.sh ./scripts/fix-storage-gaming-mode.sh verify
#   sudo ./scripts/as-root.sh ./scripts/fix-storage-gaming-mode.sh all
#   sudo ./scripts/as-root.sh ./scripts/fix-storage-gaming-mode.sh mesa --from /media/odin2/STORAGE1
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${ROOTFS:-/media/odin2/STORAGE}"
GOLDEN_ROOTFS="${GOLDEN_ROOTFS:-/media/odin2/STORAGE1}"
STEP="${1:-all}"
shift || true

log() { printf '==> [fix-gaming] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rootfs) ROOTFS="$2"; shift 2 ;;
    --from) GOLDEN_ROOTFS="$2"; shift 2 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || die "Run as root: sudo ./scripts/as-root.sh $0 ${STEP}"
[[ -d "${ROOTFS}/usr" ]] || die "Rootfs not found: ${ROOTFS}"

run_verify() {
  "${ROOT_DIR}/scripts/verify-vendor-mesa-stack.sh" "$ROOTFS" || return 1
}

run_mesa() {
  export GOLDEN_ROOTFS
  "${ROOT_DIR}/scripts/sync-vendor-mesa-golden.sh" "$ROOTFS" --from "$GOLDEN_ROOTFS"
}

run_htmlcache() {
  "${ROOT_DIR}/scripts/fix-storage-steam-htmlcache.sh" "$ROOTFS"
}

run_mango() {
  "${ROOT_DIR}/scripts/fix-steam-mango-on-storage.sh" "$ROOTFS"
  install -D -m 0755 \
    "${ROOT_DIR}/system_files/usr/libexec/steamos-ubuntu/launch-steam" \
    "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"
}

run_cef_soft() {
  "${ROOT_DIR}/scripts/set-storage-cef-gpu-mode.sh" software "$ROOTFS"
}

run_mesa_full() {
  log "Full Mesa rebuild (may take 10–30 min)"
  FORCE_REBUILD="${FORCE_REBUILD:-0}" \
    "${ROOT_DIR}/scripts/reinstall-mesa-into-rootfs.sh" "$ROOTFS"
  run_verify
}

case "$STEP" in
  verify)
    run_verify || die "Mesa stack FAIL — run: $0 mesa"
    log "Stack OK on paper; if Gaming Mode still broken try: $0 htmlcache"
    ;;
  mesa)
    run_mesa
    log "Reboot SD → Gaming Mode. If still broken: $0 htmlcache"
    ;;
  htmlcache)
    run_htmlcache
    log "Reboot SD → Gaming Mode"
    ;;
  mango)
    run_mango
    log "Reboot SD → Gaming Mode"
    ;;
  cef-soft)
    run_cef_soft
    log "Reboot SD → Gaming Mode"
    ;;
  mesa-full)
    run_mesa_full
    log "Reboot SD → Gaming Mode"
    ;;
  all)
    log "Step 1/4 — sync golden gallium + Turnip"
    run_mesa || true
    log "Step 2/4 — session scripts + MangoHud (CEF-safe)"
    "${ROOT_DIR}/scripts/apply-storage-session-fix.sh" "$ROOTFS"
    log "Step 3/4 — clear CEF htmlcache (redundant OK)"
    run_htmlcache
    log "Step 4/4 — verify Mesa"
    run_verify || true
    log "Done. Reboot the SD card and enter Gaming Mode."
    log "If it still fails: FORCE_REBUILD=1 $0 mesa-full"
    ;;
  *)
    die "Unknown step: ${STEP}. Use: verify|mesa|htmlcache|mango|cef-soft|mesa-full|all"
    ;;
esac
