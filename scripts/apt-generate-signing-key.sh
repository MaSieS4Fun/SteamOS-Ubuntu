#!/usr/bin/env bash
# Generate GPG key for signing the SteamOS-Ubuntu apt repository.
# Commits ONLY the public key (packaging/apt/steamos-ubuntu.gpg).
# Private key stays in packaging/apt/.gnupg/ (gitignored).
#
# Usage:
#   ./scripts/apt-generate-signing-key.sh
#   APT_GPG_NAME="MaSi" APT_GPG_EMAIL="you@example.com" ./scripts/apt-generate-signing-key.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GPG_HOME="${GPG_HOME:-${ROOT_DIR}/packaging/apt/.gnupg}"
PUBKEY="${PUBKEY:-${ROOT_DIR}/packaging/apt/steamos-ubuntu.gpg}"
NAME="${APT_GPG_NAME:-SteamOS-Ubuntu Release}"
EMAIL="${APT_GPG_EMAIL:-steamos-ubuntu@users.noreply.github.com}"

log() { printf '==> [apt-gpg] %s\n' "$*" >&2; }

command -v gpg >/dev/null 2>&1 || { echo "install gnupg" >&2; exit 1; }

mkdir -p "${GPG_HOME}"
chmod 700 "${GPG_HOME}"
export GNUPGHOME="${GPG_HOME}"

if gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:'; then
    log "Key already exists in ${GPG_HOME}"
else
    log "Creating ed25519 signing key (${NAME} <${EMAIL}>)"
    gpg --batch --passphrase '' --quick-generate-key \
        "${NAME} <${EMAIL}>" ed25519 sign 5y
fi

key_id="$(gpg --list-secret-keys --with-colons | awk -F: '$1=="sec"{print $5; exit}')"
gpg --batch --yes --export "${key_id}" > "${PUBKEY}"
chmod 644 "${PUBKEY}"

log "Public key: ${PUBKEY}"
log "Private key: ${GPG_HOME} (keep secret; add to GitHub Actions secret APT_GPG_PRIVATE_KEY for CI)"
gpg --show-keys "${PUBKEY}" 2>&1 | head -5
