#!/usr/bin/env bash
# Download Steam ROM Manager arm64 .deb and unpack to vendor/SteamROMManager/linux-arm64-unpacked
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="${ROOT_DIR}/vendor/SteamROMManager"
OUT="${VENDOR}/linux-arm64-unpacked"
CACHE="${ROOT_DIR}/vendor/.cache/steam-rom-manager"

SRM_VERSION="${SRM_VERSION:-2.5.44}"
DEB="steam-rom-manager_${SRM_VERSION}_arm64.deb"
URL="https://github.com/SteamGridDB/steam-rom-manager/releases/download/v${SRM_VERSION}/${DEB}"

log() { printf '==> [fetch-srm] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -x "${OUT}/steam-rom-manager" ]] && {
    log "Already present: ${OUT}/steam-rom-manager"
    exit 0
}

command -v curl >/dev/null || die "curl required"
command -v dpkg-deb >/dev/null || die "dpkg-deb required (install dpkg)"

mkdir -p "${CACHE}"
deb_path="${CACHE}/${DEB}"

if [[ ! -f "${deb_path}" ]]; then
    log "Downloading ${URL}"
    curl -fsSL -o "${deb_path}" "${URL}"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

log "Extracting ${DEB} → ${OUT}"
dpkg-deb -x "${deb_path}" "${tmpdir}"

src="${tmpdir}/opt/Steam ROM Manager"
[[ -d "${src}" ]] || die "Unexpected .deb layout (missing opt/Steam ROM Manager)"

rm -rf "${OUT}"
mkdir -p "${VENDOR}"
mv "${src}" "${OUT}"

log "Done — $(du -sh "${OUT}" | cut -f1) in ${OUT}"
