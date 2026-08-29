#!/usr/bin/env bash
# Stage vendor/plug-ins-steamos-ubuntu/* into rootfs for Decky.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:?rootfs path required}"
ROOTFS="$(cd "$ROOTFS" && pwd)"

SRC="${ROOT_DIR}/vendor/plug-ins-steamos-ubuntu"
DST="${ROOTFS}/usr/share/steamos-ubuntu/decky-plugins"
SYNC="${ROOT_DIR}/system_files/usr/libexec/steamos-ubuntu/sync-decky-bundled-plugins.sh"

log() { printf '==> [decky-plugins] %s\n' "$*"; }

[[ -d "${ROOTFS}/usr" ]] || { echo "Invalid rootfs: ${ROOTFS}" >&2; exit 1; }
[[ "${EUID}" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

if [[ ! -d "$SRC" ]]; then
  log "No ${SRC} — skip"
  exit 0
fi

install -D -m 0755 "$SYNC" "${ROOTFS}/usr/libexec/steamos-ubuntu/sync-decky-bundled-plugins.sh"

for plugin in "${SRC}"/*; do
  [[ -d "$plugin" && -f "${plugin}/plugin.json" ]] || continue
  name="$(basename "$plugin")"
  target="${DST}/${name}"
  log "${name} → ${target}"

  if [[ -x "${plugin}/build.sh" && ! -f "${plugin}/dist/index.js" ]]; then
    if command -v pnpm >/dev/null 2>&1 || command -v npm >/dev/null 2>&1; then
      log "Building frontend for ${name}…"
      (cd "$plugin" && ./build.sh) || log "WARNING: build failed for ${name} (install Node/pnpm on build host)"
    else
      log "WARNING: ${name} missing dist/index.js — run ./build.sh before baking image"
    fi
  fi

  if [[ -f "${plugin}/dist/index.js" ]] && grep -qE '^[[:space:]]*import[[:space:]]' "${plugin}/dist/index.js"; then
    log "ERROR: ${name}/dist/index.js uses ES imports — run rollup build or use legacy bundle"
    exit 1
  fi

  rm -rf "$target"
  mkdir -p "$target"
  rsync -a \
    --exclude node_modules \
    --exclude .pnpm-store \
    --exclude src \
    "${plugin}/" "$target/"
done

log "Bundled plugins staged under /usr/share/steamos-ubuntu/decky-plugins/"
