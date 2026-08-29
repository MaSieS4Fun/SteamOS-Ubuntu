#!/usr/bin/env bash
# Seed decky-lsfg-vk home snapshot into /home/steam and bundle the plugin for Decky sync.
#
# vendor/plug-ins-steamos-ubuntu/decky-lsfg-vk/ mirrors a configured steam home:
#   ~/lsfg, ~/.config/lsfg-vk/, ~/.local/..., ~/homebrew/plugins/decky-lsfg-vk/
#
# LSFG config + Vulkan layer are ready on first boot. After Box64/FEX + Decky install,
# sync-decky-bundled-plugins.sh also installs decky-lsfg-vk from the system bundle.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:?rootfs path required}"
ROOTFS="$(cd "$ROOTFS" && pwd)"

SRC="${ROOT_DIR}/vendor/plug-ins-steamos-ubuntu/decky-lsfg-vk"
STEAM_HOME="${ROOTFS}/home/steam"
BUNDLE="${ROOTFS}/usr/share/steamos-ubuntu/decky-plugins/decky-lsfg-vk"
PLUGIN_SRC="${SRC}/homebrew/plugins/decky-lsfg-vk"

log() { printf '==> [decky-lsfg-vk] %s\n' "$*"; }

[[ -d "${ROOTFS}/usr" ]] || { echo "Invalid rootfs: ${ROOTFS}" >&2; exit 1; }
[[ "${EUID}" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

if [[ ! -d "$SRC" ]]; then
  log "No ${SRC} — skip"
  exit 0
fi

STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "${ROOTFS}/etc/passwd" 2>/dev/null || echo 1000)"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "${ROOTFS}/etc/passwd" 2>/dev/null || echo 1000)"

mkdir -p "$STEAM_HOME"

log "Seeding ${STEAM_HOME} from vendor snapshot"
rsync -a \
  --exclude '.git' \
  --exclude 'README.md' \
  "${SRC}/" "${STEAM_HOME}/"

if [[ -f "${STEAM_HOME}/lsfg" ]]; then
  chmod 0755 "${STEAM_HOME}/lsfg"
fi

if [[ -f "${PLUGIN_SRC}/plugin.json" ]]; then
  log "Bundling plugin → ${BUNDLE}"
  mkdir -p "$BUNDLE"
  rsync -a \
    --exclude node_modules \
    --exclude src \
    --exclude .pnpm-store \
    "${PLUGIN_SRC}/" "${BUNDLE}/"
else
  log "WARNING: missing ${PLUGIN_SRC}/plugin.json — home seed only"
fi

for path in \
  "${STEAM_HOME}/lsfg" \
  "${STEAM_HOME}/.config/lsfg-vk" \
  "${STEAM_HOME}/.local" \
  "${STEAM_HOME}/homebrew"
do
  [[ -e "$path" ]] || continue
  chown -R "${STEAM_UID}:${STEAM_GID}" "$path"
done

log "Done"
