#!/usr/bin/env bash
# Publish signed apt repo to gh-pages (manual fallback when CI secrets misbehave).
#
# Prerequisites: git push access, packaging/apt/.gnupg with signing key.
#
# Usage:
#   ./scripts/publish-apt-repo-local.sh
#   ./scripts/publish-apt-repo-local.sh --skip-build   # reuse output/apt-repo
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_BUILD=0
[[ "${1:-}" == "--skip-build" ]] && SKIP_BUILD=1

log() { printf '==> [publish-apt] %s\n' "$*"; }
die() { printf 'ERROR: [publish-apt] %s\n' "$*" >&2; exit 1; }

cd "${ROOT_DIR}"
command -v git >/dev/null || die "git required"

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
    ./scripts/build-debs.sh
    APT_SIGN=1 ./scripts/generate-apt-repo.sh
fi

[[ -f output/apt-repo/InRelease ]] || die "missing output/apt-repo/InRelease — run with signing key"
shopt -s nullglob
debs=( output/apt-repo/*.deb )
shopt -u nullglob
[[ ${#debs[@]} -gt 0 ]] || die "missing output/apt-repo/*.deb"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

log "Cloning gh-pages → ${work}"
git clone --depth=1 --branch=gh-pages "git@github.com:MaSieS4Fun/SteamOS-Ubuntu.git" "${work}/repo" 2>/dev/null || \
git clone --depth=1 --branch=gh-pages "https://github.com/MaSieS4Fun/SteamOS-Ubuntu.git" "${work}/repo"

rm -rf "${work}/repo/apt"
mkdir -p "${work}/repo/apt"
cp -a output/apt-repo/. "${work}/repo/apt/"
touch "${work}/repo/.nojekyll"

cd "${work}/repo"
git add -A
if git diff --staged --quiet; then
    log "No changes on gh-pages"
    exit 0
fi

git -c user.name="MaSieS4Fun" -c user.email="MaSieS4Fun@users.noreply.github.com" \
    commit -m "deploy: signed apt repo (local publish)"
git push origin gh-pages

log "Done — wait ~1 min then check:"
log "  https://masies4fun.github.io/SteamOS-Ubuntu/apt/InRelease"
