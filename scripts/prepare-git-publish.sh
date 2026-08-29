#!/usr/bin/env bash
# Prepare SteamOS-Ubuntu for a clean git push (no nested repos, no agent junk).
#
# Usage:
#   ./scripts/prepare-git-publish.sh
#   ./scripts/prepare-git-publish.sh --check-only
#
# Removes nested vendor/.git directories so `git add -A` works.
# Does NOT touch packaging/apt/.gnupg (apt signing key).
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ONLY="${1:-}"

log() { printf '==> [git-prep] %s\n' "$*"; }
warn() { printf 'WARN: [git-prep] %s\n' "$*" >&2; }

cd "${ROOT_DIR}"

removed=0
while IFS= read -r -d '' gitdir; do
    case "${gitdir}" in
    "${ROOT_DIR}/.git"*) continue ;;
    "${ROOT_DIR}/packaging/apt/.gnupg"*) continue ;;
    "${ROOT_DIR}/vendor/.cache"*) continue ;;  # build cache — gitignored, often root-owned
    esac
    rel="${gitdir#${ROOT_DIR}/}"
    if [[ "${CHECK_ONLY}" == "--check-only" ]]; then
        warn "nested repo: ${rel} (run without --check-only to remove)"
        removed=$((removed + 1))
        continue
    fi
    log "Removing nested ${rel} (files stay; only .git metadata removed)"
    if ! rm -rf "${gitdir}" 2>/dev/null; then
        if [[ "${EUID}" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
            warn "permission denied — retrying with sudo for ${rel}"
            sudo rm -rf "${gitdir}" || warn "could not remove ${rel} (ignored; under .cache?)"
        else
            warn "could not remove ${rel} (ignored)"
        fi
    fi
    removed=$((removed + 1))
done < <(find "${ROOT_DIR}" -path "${ROOT_DIR}/vendor/.cache" -prune -o \
    -name .git -type d -print0 2>/dev/null)

# Agent / scratch files at repo root
for f in _agent_explore.txt _apply_live_result.txt _run_explore.sh _search_results.txt; do
    [[ -f "${ROOT_DIR}/${f}" ]] || continue
    if [[ "${CHECK_ONLY}" == "--check-only" ]]; then
        warn "junk file: ${f}"
    else
        log "Removing ${f}"
        rm -f "${ROOT_DIR}/${f}"
    fi
done

# Stray debs at root
shopt -s nullglob
for f in "${ROOT_DIR}"/*.deb; do
    if [[ "${CHECK_ONLY}" == "--check-only" ]]; then
        warn "stray deb: $(basename "${f}")"
    else
        log "Removing $(basename "${f}")"
        rm -f "${f}"
    fi
done
shopt -u nullglob

# Block accidental commit of files over GitHub's 100 MB limit
while IFS= read -r -d '' f; do
    size="$(stat -c%s "${f}" 2>/dev/null || echo 0)"
    if [[ "${size}" -gt 104857600 ]]; then
        rel="${f#${ROOT_DIR}/}"
        if [[ "${CHECK_ONLY}" == "--check-only" ]]; then
            warn "file >100MB (git will reject push): ${rel} ($(numfmt --to=iec-i --suffix=B "${size}" 2>/dev/null || echo "${size} bytes"))"
        else
            warn "tracked file >100MB: ${rel} — add to .gitignore and git rm --cached"
        fi
        removed=$((removed + 1))
    fi
done < <(git ls-files -z 2>/dev/null || true)

# vendor/.cache is gitignored; drop root-owned heroic clone metadata if present
heroic_git="${ROOT_DIR}/vendor/.cache/heroic-build/HeroicGamesLauncher/.git"
if [[ -d "${heroic_git}" ]]; then
    if [[ "${CHECK_ONLY}" == "--check-only" ]]; then
        warn "root-owned cache (gitignored): vendor/.cache/heroic-build/…"
    else
        log "Removing gitignored vendor/.cache/heroic-build/…/.git (may need sudo)"
        rm -rf "${heroic_git}" 2>/dev/null || sudo rm -rf "${heroic_git}" 2>/dev/null || \
            warn "leave vendor/.cache/ alone — already in .gitignore"
    fi
fi

if [[ "${CHECK_ONLY}" == "--check-only" ]]; then
    [[ "${removed}" -eq 0 ]] && log "OK — no nested .git dirs found"
    exit 0
fi

log "Done. Verify identity before commit:"
printf '  '; git config user.name 2>/dev/null || echo "(set git user.name)"
printf '  '; git config user.email 2>/dev/null || echo "(set git user.email)"
log "Next: git add -A && git commit …"
