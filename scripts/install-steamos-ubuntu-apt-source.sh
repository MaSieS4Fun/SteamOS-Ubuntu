#!/usr/bin/env bash
# Install SteamOS-Ubuntu apt source + GPG key into a rootfs (image bake or live system).
#
# Usage:
#   sudo ./scripts/install-steamos-ubuntu-apt-source.sh [rootfs]
#
# Env:
#   STEAMOS_UBUNTU_GITHUB_REPO=Owner/SteamOS-Ubuntu
#   SKIP_STEAMOS_APT_SOURCE=1   — skip entirely
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-/}"
# shellcheck source=packaging/apt/channel.conf
source "${ROOT_DIR}/packaging/apt/channel.conf"

log() { printf '==> [apt-source] %s\n' "$*"; }
die() { printf 'ERROR: [apt-source] %s\n' "$*" >&2; exit 1; }

[[ "${SKIP_STEAMOS_APT_SOURCE:-0}" == "1" ]] && { log "SKIP (SKIP_STEAMOS_APT_SOURCE=1)"; exit 0; }

if [[ "${ROOTFS}" != "/" ]]; then
    ROOTFS="${ROOTFS%/}"
    [[ -d "${ROOTFS}/usr" ]] || die "Not a rootfs: ${ROOTFS}"
    [[ "${EUID}" -eq 0 ]] || die "Run as root"
else
    [[ "${EUID}" -eq 0 ]] || die "Run as root"
fi

path() {
    if [[ "${ROOTFS}" == "/" ]]; then printf '%s\n' "$1"; else printf '%s%s\n' "${ROOTFS}" "$1"; fi
}

repo="${STEAMOS_UBUNTU_GITHUB_REPO}"
owner="${repo%%/*}"
name="${repo#*/}"
[[ -n "${owner}" && -n "${name}" && "${owner}" != "${repo}" ]] || die "bad STEAMOS_UBUNTU_GITHUB_REPO: ${repo}"

# GitHub Pages flat repo (workflow publishes output/apt-repo → gh-pages branch /apt/)
apt_url="https://${owner}.github.io/${name}/apt"

install -d "$(path /usr/share/keyrings)" "$(path /etc/apt/sources.list.d)"

pubkey="${ROOT_DIR}/packaging/apt/steamos-ubuntu.gpg"
if [[ -f "${pubkey}" ]]; then
    install -m 0644 "${pubkey}" "$(path /usr/share/keyrings/steamos-ubuntu.gpg)"
    signed_by='[signed-by=/usr/share/keyrings/steamos-ubuntu.gpg '
else
    log "WARN: ${pubkey} missing — run ./scripts/apt-generate-signing-key.sh before bake"
    signed_by='[trusted=yes '
fi

cat > "$(path /etc/apt/sources.list.d/steamos-ubuntu.list)" <<EOF
# SteamOS-Ubuntu vendor apps + kernel updater (MaSi)
# Active once the GitHub repo (and Pages) are PUBLIC — see packaging/apt/README.md
deb ${signed_by}arch=arm64] ${apt_url} ./
EOF

install -d "$(path /usr/share/steamos-ubuntu)"
cat > "$(path /usr/share/steamos-ubuntu/apt-channel.conf)" <<EOF
GITHUB_REPO=${repo}
APT_URL=${apt_url}
APT_CHANNEL=${APT_CHANNEL}
EOF

log "Installed $(path /etc/apt/sources.list.d/steamos-ubuntu.list)"
log "  URL: ${apt_url}"
log "  Note: apt update works on devices after repo + GitHub Pages are public"
