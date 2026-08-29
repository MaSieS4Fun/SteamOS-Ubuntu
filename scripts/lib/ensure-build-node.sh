#!/usr/bin/env bash
# Node 22 + pnpm 10 for image-bake steps (Heroic, Decky plugin builds).
# Safe under sudo: searches steam/SUDO_USER ~/.local and vendor/.cache bootstrap.
#
# Usage (source, do not exec):
#   source scripts/lib/ensure-build-node.sh
#   ensure_build_node /path/to/SteamOS-Ubuntu || exit 1
set -euo pipefail

_ensure_build_node_log() { printf '==> [build-node] %s\n' "$*"; }

# Corepack pide [Y/n] al entrar en un repo con "packageManager" distinto al pnpm global.
# En builds con sudo eso bloquea el script indefinidamente.
_ensure_corepack_noninteractive() {
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  export CI=1
  corepack enable 2>/dev/null || true
}

# Activa la versión exacta de pnpm/yarn que pide package.json (p. ej. Heroic → pnpm@10.28.0).
ensure_project_package_manager() {
  local pkg_json="${1:-package.json}"
  [[ -f "$pkg_json" ]] || return 0
  local pm
  pm="$(node -e "const p=require(process.argv[1]); process.stdout.write(p.packageManager||'')" "$pkg_json" 2>/dev/null || true)"
  [[ -n "$pm" ]] || return 0
  _ensure_corepack_noninteractive
  _ensure_build_node_log "Corepack prepare ${pm} (automático, sin prompt)..."
  corepack prepare "$pm" --activate
}

ensure_build_node() {
  _ensure_corepack_noninteractive
  local root_dir="${1:-}"
  local node_ver="${BUILD_NODE_VERSION:-22.14.0}"
  local cache home d

  if command -v node >/dev/null 2>&1 && command -v pnpm >/dev/null 2>&1; then
    _ensure_build_node_log "OK: node $(node -v), pnpm $(pnpm -v)"
    return 0
  fi

  local -a homes=()
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    home="$(getent passwd "${SUDO_USER}" 2>/dev/null | cut -d: -f6 || true)"
    [[ -n "$home" ]] && homes+=("$home")
  fi
  [[ -n "${HOME:-}" ]] && homes+=("${HOME}")
  homes+=("/home/steam")

  for home in "${homes[@]}"; do
    [[ -n "$home" && -d "$home" ]] || continue
    for d in "${home}/.local"/node-v*-linux-arm64/bin; do
      [[ -x "${d}/node" ]] || continue
      export PATH="${d}:${PATH}"
      _ensure_build_node_log "Using Node from ${d}"
      break 2
    done
  done

  if ! command -v node >/dev/null 2>&1 && [[ -n "$root_dir" ]]; then
    cache="${root_dir}/vendor/.cache/node-v${node_ver}-linux-arm64"
    if [[ ! -x "${cache}/bin/node" ]]; then
      local tarball="node-v${node_ver}-linux-arm64.tar.xz"
      local url="https://nodejs.org/dist/v${node_ver}/${tarball}"
      mkdir -p "${root_dir}/vendor/.cache"
      _ensure_build_node_log "Downloading ${url}"
      curl -fsSL "$url" -o "/tmp/${tarball}"
      tar -xJf "/tmp/${tarball}" -C "${root_dir}/vendor/.cache"
      rm -f "/tmp/${tarball}"
    fi
    if [[ -x "${cache}/bin/node" ]]; then
      export PATH="${cache}/bin:${PATH}"
      _ensure_build_node_log "Using bootstrapped Node from ${cache}/bin"
    fi
  fi

  command -v node >/dev/null 2>&1 || return 1

  if ! command -v pnpm >/dev/null 2>&1; then
    if ! corepack prepare pnpm@10 --activate 2>/dev/null; then
      npm install -g pnpm@10
    fi
  fi

  command -v pnpm >/dev/null 2>&1 || return 1
  _ensure_build_node_log "OK: node $(node -v), pnpm $(pnpm -v)"
  return 0
}
