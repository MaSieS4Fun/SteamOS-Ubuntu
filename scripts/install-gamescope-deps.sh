#!/usr/bin/env bash
# Install packages/gamescope deps on a live Ubuntu/Debian host
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEBIAN_FRONTEND=noninteractive
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "${ROOT_DIR}/packages/gamescope" | awk 'NF' | sort -u)
apt-get update -y
FAILED=()
for p in "${PKGS[@]}"; do
  apt-get install -y --no-install-recommends "$p" || FAILED+=("$p")
done
"${ROOT_DIR}/scripts/check-gamescope-deps.sh" / || true
if ((${#FAILED[@]})); then
  echo "Could not install: ${FAILED[*]}"
  exit 1
fi
echo "Gamescope deps installed."
