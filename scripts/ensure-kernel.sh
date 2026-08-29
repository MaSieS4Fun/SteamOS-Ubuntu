#!/usr/bin/env bash
# Resolve vendor/kernel build dir. Logs → stderr; only prints the path on stdout.
# If no kbase output exists, runs vendor/kernel/make.sh (needed for a clean first bake).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERN_ROOT="${ROOT_DIR}/vendor/kernel"
OUTPUT_DIR="${KERN_ROOT}/output"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

find_build() {
  local d
  shopt -s nullglob
  # Prefer explicit newest kbase tree
  for d in $(ls -1d "${OUTPUT_DIR}"/*-edge-sm8550-kbase 2>/dev/null | sort -V); do
    [[ -f "${d}/boot/KERNEL" && -d "${d}/firmware" && -d "${d}/modules" ]] || continue
    printf '%s\n' "$d"
    return 0
  done
  for d in "${OUTPUT_DIR}"/*-kbase; do
    [[ -d "$d" ]] || continue
    [[ -f "${d}/boot/KERNEL" && -d "${d}/firmware" && -d "${d}/modules" ]] || continue
    printf '%s\n' "$d"
    return 0
  done
  shopt -u nullglob
  return 1
}

emit_build() {
  local b="$1"
  log "Kernel build: ${b}"
  # Sole stdout line for callers (KERN_BUILD="$(ensure-kernel.sh)")
  printf '%s\n' "$b"
}

if BUILD="$(find_build)"; then
  emit_build "$BUILD"
  exit 0
fi

[[ "${SKIP_KERNEL_BUILD:-0}" == "1" ]] && die "No kernel output (expected …/output/*-edge-sm8550-kbase)"

if [[ ! -x "${KERN_ROOT}/make.sh" ]]; then
  die "Missing ${KERN_ROOT}/make.sh and no kbase output"
fi

# Non-interactive one-shot (create-image / build-image). Pin matches defaults.conf.
export KERNEL_VER="${KERNEL_VER:-7.0.14}"
export UI="${UI:-plain}"
export PREFERRED_KERNEL_SERIES="${PREFERRED_KERNEL_SERIES:-7.0}"

log "No kernel output — running vendor/kernel/make.sh (KERNEL_VER=${KERNEL_VER}, UI=${UI})"
# make(1) prints "Entering directory …" on stdout under --print-directory —
# must not leak into callers that capture ensure-kernel stdout as the path.
(
  cd "${KERN_ROOT}"
  ./make.sh >&2
)

if BUILD="$(find_build)"; then
  emit_build "$BUILD"
  exit 0
fi

die "Missing ${OUTPUT_DIR}/*-edge-sm8550-kbase after make.sh (boot/KERNEL + firmware/ + modules/)"
