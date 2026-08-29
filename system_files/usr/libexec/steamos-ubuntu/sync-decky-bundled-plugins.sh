#!/usr/bin/env bash
# Copy bundled SteamOS-Ubuntu Decky plugins into ~/homebrew/plugins/.
# PluginLoader runs as root upstream — always fix ownership for steam.
set -euo pipefail

STEAM_USER="${STEAM_USER:-steam}"
STEAM_HOME="${STEAM_HOME:-/home/${STEAM_USER}}"
BUNDLE_ROOT="${BUNDLE_ROOT:-/usr/share/steamos-ubuntu/decky-plugins}"
HOMEBREW="${STEAM_HOME}/homebrew"
DEST="${HOMEBREW}/plugins"

log() { printf 'sync-decky-plugins: %s\n' "$*"; }

STEAM_UID="$(id -u "$STEAM_USER" 2>/dev/null || echo 1000)"
STEAM_GID="$(id -g "$STEAM_USER" 2>/dev/null || echo 1000)"

fix_homebrew_ownership() {
  [[ -d "$HOMEBREW" ]] || return 0
  if [[ "${EUID}" -eq 0 ]]; then
    chown -R "${STEAM_UID}:${STEAM_GID}" "$HOMEBREW"
    return 0
  fi
  if ! sudo -n chown -R "${STEAM_UID}:${STEAM_GID}" "$HOMEBREW" 2>/dev/null; then
    log "WARNING: ~/homebrew not owned by ${STEAM_USER} — run: sudo chown -R ${STEAM_USER}:${STEAM_USER} ${HOMEBREW}"
    return 1
  fi
  return 0
}

if [[ ! -d "$BUNDLE_ROOT" ]]; then
  log "No bundled plugins at ${BUNDLE_ROOT} — skip"
  exit 0
fi

if [[ ! -x "${HOMEBREW}/services/PluginLoader" && ! -f "${HOMEBREW}/services/PluginLoader" ]]; then
  log "Decky not installed yet (${HOMEBREW}) — skip"
  exit 0
fi

fix_homebrew_ownership || exit 1

if [[ "${EUID}" -ne 0 ]]; then
  mkdir -p "$DEST" 2>/dev/null || {
    log "Cannot create ${DEST} — fixing ownership…"
    fix_homebrew_ownership || exit 1
    mkdir -p "$DEST"
  }
else
  mkdir -p "$DEST"
  chown "${STEAM_UID}:${STEAM_GID}" "$DEST"
fi

shopt -s nullglob
installed=0
for src in "${BUNDLE_ROOT}"/*; do
  [[ -d "$src" && -f "${src}/plugin.json" ]] || continue
  name="$(basename "$src")"
  log "Installing ${name} → ${DEST}/${name}"
  mkdir -p "${DEST}/${name}"
  rsync -a --delete "${src}/" "${DEST}/${name}/"
  installed=1
done

if (( installed == 0 )); then
  log "No plugins found under ${BUNDLE_ROOT}"
  exit 0
fi

fix_homebrew_ownership
log "Done"
