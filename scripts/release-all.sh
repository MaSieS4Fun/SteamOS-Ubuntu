#!/usr/bin/env bash
# One-shot: commit apt fixes, push, build signed repo, publish gh-pages, tag.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

log() { printf '\n==> [release-all] %s\n' "$*"; }

log "1/5 — git commit + push"
git add \
  scripts/generate-apt-repo.sh \
  scripts/build-debs.sh \
  scripts/publish-apt-repo-local.sh \
  scripts/release-all.sh \
  packaging/apt/channel.conf \
  packaging/apt/steamos-ubuntu.gpg \
  .github/workflows/release-apt.yml \
  vendor/gyro-desktop/install.sh 2>/dev/null || true

if ! git diff --staged --quiet; then
  git commit -m "$(cat <<'EOF'
Fix apt channel for image bake and Resolute updates.

- Flat apt repo layout (debs beside Packages)
- mesa-easy-manager: polkitd on Resolute
- CI signed InRelease + local publish script
- Bump mesa-easy-manager and steamos-ubuntu-apps to 1.0.1
EOF
)"
else
  log "Nothing new to commit (already committed)"
fi

git push origin main

log "2/5 — build .deb packages"
./scripts/build-debs.sh

log "3/5 — signed apt repo"
APT_SIGN=1 ./scripts/generate-apt-repo.sh

log "4/5 — publish gh-pages"
chmod +x scripts/publish-apt-repo-local.sh
./scripts/publish-apt-repo-local.sh --skip-build

log "5/5 — tag v1.0.5"
git tag -f v1.0.5
git push origin v1.0.5 --force

log "Done."
log "  Apt:  https://masies4fun.github.io/SteamOS-Ubuntu/apt/InRelease"
log "  Next: sudo ./create-image.sh"
