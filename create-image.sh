#!/usr/bin/env bash
# Create SteamOS-Ubuntu (Ubuntu Resolute / ARM64) image — ONE-SHOT end-to-end.
#
# Does everything in order:
#   1) rootfs (Podman OCI or debootstrap)  2) SM8550 kernel  3) vendor audio
#   4) mesa → gamescope → mangohud → Steam/Proton  5) finalize  6) GPT .img
#
# Usage:
#   sudo ./create-image.sh              # full bake (recommended)
#   sudo ./create-image.sh --oci        # force Podman/Containerfile
#   sudo ./create-image.sh --bootstrap  # force debootstrap
#   sudo ./create-image.sh --rootfs-only
#   sudo ./create-image.sh --finalize-img  # reuse output/rootfs: finalize + .img only
#   ./create-image.sh --help
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

FORCE_OCI=0
FORCE_BOOTSTRAP=0
REUSE_ROOTFS=0
FINALIZE_IMG=0
export SUITE="${SUITE:-resolute}"
export ARCH="${ARCH:-arm64}"
export MIRROR="${MIRROR:-http://ports.ubuntu.com/ubuntu-ports}"
export IMAGE="${IMAGE:-localhost/steamos-ubuntu}"
export TAG="${TAG:-resolute}"
export CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-}"
export SKIP_IMG="${SKIP_IMG:-0}"
export SKIP_OCI_BUILD="${SKIP_OCI_BUILD:-0}"
export SKIP_AUDIO="${SKIP_AUDIO:-0}"
# Kernel pin for non-interactive bake (matches vendor/kernel/config/defaults.conf)
export KERNEL_VER="${KERNEL_VER:-7.0.14}"
export UI="${UI:-plain}"
export PREFERRED_KERNEL_SERIES="${PREFERRED_KERNEL_SERIES:-7.0}"

usage() {
  cat <<'EOF'
SteamOS-Ubuntu — one-shot image builder

  sudo ./create-image.sh                 Full bake: rootfs → kernel → stack → .img
  sudo ./create-image.sh --oci           Force Containerfile build (needs podman)
  sudo ./create-image.sh --bootstrap     Force debootstrap (no containers)
  sudo ./create-image.sh --reuse-rootfs  Keep output/rootfs; rebuild kernel/stack/disk
  sudo ./create-image.sh --finalize-img  Keep output/rootfs; ONLY finalize + GPT .img
                                         (no kernel/mesa/gamescope rebuild — minutes)
  sudo ./create-image.sh --rootfs-only   Skip sparse .img
  ./create-image.sh --help

Pipeline (automatic, no separate phases needed):
  packages/rootfs → SM8550 kernel (7.0.14) → audio → mesa/gamescope/mangohud/steam
  → finalize → GPT disk image

Disk layout (GPT):
  p1 VFAT  PARTLABEL=BOOT     → /boot/KERNEL (ABL)
  p2 ext4  PARTLABEL=STORAGE  → rootfs (firmware from vendor/kernel only)

Optional env:
  KERNEL_VER=7.0.14   (default)   SKIP_AUDIO=1   SKIP_IMG=1   JOBS=N
  SKIP_HOST_DEPS=1    skip apt install of compile/podman packages

After switching to a fresh build host:
  sudo ./scripts/install-host-build-deps.sh   # Mesa/gamescope/kernel/Podman deps
  (create-image.sh runs this automatically unless SKIP_HOST_DEPS=1)

Artifacts: ./output/steamos-ubuntu-resolute-arm64.img (+ output/rootfs)
EOF
}

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --oci) FORCE_OCI=1 ;;
    --bootstrap|--debootstrap) FORCE_BOOTSTRAP=1 ;;
    --reuse-rootfs) REUSE_ROOTFS=1; SKIP_OCI_BUILD=1; export SKIP_OCI_BUILD ;;
    --finalize-img|--finalize-only) FINALIZE_IMG=1; SKIP_OCI_BUILD=1; export SKIP_OCI_BUILD ;;
    --rootfs-only) SKIP_IMG=1; export SKIP_IMG ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $arg (try --help)" ;;
  esac
done

(( FORCE_OCI && FORCE_BOOTSTRAP )) && die "Use either --oci or --bootstrap, not both"
(( REUSE_ROOTFS && FINALIZE_IMG )) && die "Use either --reuse-rootfs or --finalize-img, not both"

chmod +x "$ROOT"/scripts/*.sh "$ROOT"/build_files/*.sh 2>/dev/null || true
chmod +x \
  "$ROOT"/system_files/usr/bin/gamescope-session \
  "$ROOT"/system_files/usr/bin/steamos-session-select \
  "$ROOT"/system_files/usr/bin/steamos-desktop-to-gamescope \
  "$ROOT"/system_files/usr/local/bin/steamos-greetd-session \
  2>/dev/null || true

mkdir -p "$ROOT/output"

detect_runtime() {
  if [[ -n "$CONTAINER_RUNTIME" ]]; then
    command -v "$CONTAINER_RUNTIME" >/dev/null || return 1
    return 0
  fi
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_RUNTIME=podman
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    CONTAINER_RUNTIME=docker
    return 0
  fi
  return 1
}

if [[ "${EUID}" -ne 0 ]]; then
  log "Root required — re-running with sudo…"
  exec sudo --preserve-env=SUITE,ARCH,MIRROR,IMAGE,TAG,CONTAINER_RUNTIME,SKIP_IMG,SKIP_OCI_BUILD,SKIP_AUDIO,KERNEL_VER,UI,PREFERRED_KERNEL_SERIES,JOBS,PATCH_SKIP,BUILD_COMPILE,SKIP_KERNEL_BUILD,SKIP_MESA,SKIP_GAMESCOPE,SKIP_MANGOHUD,SKIP_STEAM,SKIP_VENDOR_APPS,SKIP_HOST_DEPS \
    "$0" "$@"
fi

# Fast path: apply latest finalize (sudoers, maliit, LSFG, OOBE, Mesa hold…) + pack .img
if (( FINALIZE_IMG )); then
  ROOTFS="$ROOT/output/rootfs"
  [[ -d "$ROOTFS/usr" ]] || die "--finalize-img needs output/rootfs from a previous bake"
  log "Finalize-only: reusing ${ROOTFS} (no kernel/mesa/gamescope rebuild)"
  export SKIP_HOST_DEPS=1
  "$ROOT/scripts/finalize-handheld-rootfs.sh" "$ROOTFS"
  if [[ "${SKIP_IMG:-0}" != "1" ]]; then
    log "Creating GPT disk image from finalized rootfs"
    "$ROOT/scripts/make-disk-image.sh" "$ROOTFS"
  else
    log "SKIP_IMG=1 — rootfs finalized, no .img"
  fi
  log "Done — image at output/steamos-ubuntu-resolute-arm64.img (if packed)"
  exit 0
fi

log "One-shot bake: rootfs → kernel ${KERNEL_VER} → audio → mesa/gamescope/steam → finalize → disk"
export CMDLINE_QUIET="${CMDLINE_QUIET:-1}"

# Fresh-clone friendly: install compile + Podman deps unless skipped
if [[ "${SKIP_HOST_DEPS:-0}" != "1" ]]; then
  log "Ensuring host build deps (kernel + mesa/gamescope + podman)…"
  "$ROOT/scripts/install-host-build-deps.sh"
fi

if (( REUSE_ROOTFS )); then
  [[ -d "$ROOT/output/rootfs/usr" ]] || die "--reuse-rootfs needs output/rootfs from a previous build"
  log "Reusing output/rootfs — kernel + vendor stack + GPT disk"
  export SKIP_OCI_BUILD=1
  exec "$ROOT/scripts/build-image.sh"
fi

USE_OCI=0
if (( FORCE_BOOTSTRAP )); then
  USE_OCI=0
elif (( FORCE_OCI )); then
  detect_runtime || die "Podman/Docker still missing after host deps. Try: sudo apt install -y podman"
  USE_OCI=1
elif detect_runtime; then
  USE_OCI=1
  log "Found ${CONTAINER_RUNTIME} — using OCI Containerfile build"
else
  USE_OCI=0
  log "No Podman/Docker — falling back to debootstrap (same full stack)"
fi

export CONTAINER_RUNTIME

if (( USE_OCI )); then
  exec "$ROOT/scripts/build-image.sh"
fi

command -v debootstrap >/dev/null || die "Install debootstrap: apt install debootstrap"
command -v rsync >/dev/null || die "Install rsync: apt install rsync"
exec "$ROOT/scripts/bootstrap-rootfs.sh"
