#!/usr/bin/env bash
# Build a flat apt repository index from output/debs/*.deb
#
# Usage:
#   ./scripts/build-debs.sh
#   ./scripts/generate-apt-repo.sh
#   APT_SIGN=1 ./scripts/generate-apt-repo.sh   # requires packaging/apt/.gnupg or APT_GPG_KEY_ID
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=packaging/apt/channel.conf
source "${ROOT_DIR}/packaging/apt/channel.conf"

IN_DEBS="${IN_DEBS:-${ROOT_DIR}/output/debs}"
OUT_REPO="${OUT_REPO:-${ROOT_DIR}/output/apt-repo}"
GPG_HOME="${GPG_HOME:-${ROOT_DIR}/packaging/apt/.gnupg}"
PUBKEY="${PUBKEY:-${ROOT_DIR}/packaging/apt/steamos-ubuntu.gpg}"
APT_SIGN="${APT_SIGN:-0}"

log() { printf '==> [apt-repo] %s\n' "$*" >&2; }
die() { printf 'ERROR: [apt-repo] %s\n' "$*" >&2; exit 1; }

command -v apt-ftparchive >/dev/null 2>&1 || die "apt install apt-utils"

[[ -d "${IN_DEBS}" ]] || die "missing ${IN_DEBS} — run ./scripts/build-debs.sh first"
shopt -s nullglob
debs=( "${IN_DEBS}"/*.deb )
shopt -u nullglob
[[ ${#debs[@]} -gt 0 ]] || die "no .deb files in ${IN_DEBS}"

rm -rf "${OUT_REPO}"
mkdir -p "${OUT_REPO}"
cp -a "${debs[@]}" "${OUT_REPO}/"

log "Generating Packages index (${#debs[@]} debs)"
(
    cd "${OUT_REPO}"
    apt-ftparchive packages . > Packages
)
gzip -9cn "${OUT_REPO}/Packages" > "${OUT_REPO}/Packages.gz"

log "Generating Release"
apt-ftparchive release "${OUT_REPO}" > "${OUT_REPO}/Release"

if [[ "${APT_SIGN}" == "1" ]]; then
    [[ -d "${GPG_HOME}" ]] || die "missing ${GPG_HOME} — run ./scripts/apt-generate-signing-key.sh"
    export GNUPGHOME="${GPG_HOME}"
    key_id="${APT_GPG_KEY_ID:-}"
    if [[ -z "${key_id}" ]]; then
        key_id="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '$1=="sec"{print $5; exit}')"
    fi
    [[ -n "${key_id}" ]] || die "no signing key in ${GPG_HOME}"
    log "Signing Release with ${key_id}"
    gpg --batch --yes --local-user "${key_id}" --clearsign \
        --output "${OUT_REPO}/InRelease" "${OUT_REPO}/Release"
    gpg --batch --yes --local-user "${key_id}" -ab \
        --output "${OUT_REPO}/Release.gpg" "${OUT_REPO}/Release"
    gpg --batch --yes --export "${key_id}" > "${PUBKEY}"
    log "Updated public key → ${PUBKEY}"
else
    log "APT_SIGN=0 — unsigned repo (OK for local tests; enable APT_SIGN=1 before publish)"
fi

cat > "${OUT_REPO}/README.txt" <<EOF
SteamOS-Ubuntu apt channel (${APT_CHANNEL})
GitHub: https://github.com/${STEAMOS_UBUNTU_GITHUB_REPO}
Packages: ${#debs[@]}
EOF

log "Repo ready: ${OUT_REPO}"
ls -la "${OUT_REPO}"
