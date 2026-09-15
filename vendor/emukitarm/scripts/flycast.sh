#!/usr/bin/env bash
# Build / install / uninstall Flycast (Dreamcast / Naomi / Atomiswave) from source.
#
# https://github.com/flyinghead/flycast
# Official Linux path is recursive git clone + cmake + make/ninja.
# cmake --install places binary, .desktop, icons, and man page under prefix.
#
# Never install Ubuntu Mesa; vendor Adreno/Turnip stays in place.
# Do not pass Tegra/L4T -march=native flags.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="flycast"
APP_NAME="Flycast"
REPO_URL="https://github.com/flyinghead/flycast.git"
PREFIX="${MASI_PREFIX:-/usr/local}"

BUILD_DEPS=(
  build-essential clang cmake ninja-build pkg-config git ca-certificates
  libcurl4-openssl-dev libudev-dev libsdl2-dev
  libegl-dev libopengl-dev libgl-dev libvulkan-dev
  zlib1g-dev libao-dev libasound2-dev libpulse-dev
)

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  masi_uninstall_from_manifest "$APP_ID"
  masi_refresh_desktop_and_icons "${PREFIX}/share"
  masi_log "=== ${APP_NAME} removed ==="
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} (source build + cmake --install) ==="
  masi_log "Install prefix: ${PREFIX}"
  masi_log "Ubuntu Mesa will not be installed (vendor Adreno/Turnip Mesa)."

  if [[ ! -f /usr/include/EGL/egl.h ]]; then
    masi_die "Missing EGL headers (/usr/include/EGL/egl.h). Use your vendor Mesa SDK, not Ubuntu Mesa."
  fi

  masi_ensure_sudo
  masi_ensure_mesa_dev_stubs
  masi_apt_install "${BUILD_DEPS[@]}"

  masi_prepare_build "$APP_ID"
  local src_dir="${MASI_WORK}/src"
  local build_dir="${MASI_WORK}/build"

  masi_log "Cloning ${REPO_URL} (recursive submodules)..."
  git clone --depth 1 --recursive "$REPO_URL" "$src_dir" \
    || {
      git clone --depth 1 "$REPO_URL" "$src_dir"
      git -C "$src_dir" submodule update --init --recursive --depth 1 \
        || git -C "$src_dir" submodule update --init --recursive
    }

  masi_log "Configuring CMake (Release)..."
  cmake -S "$src_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DUSE_BREAKPAD=OFF \
    -DUSE_DISCORD=OFF

  masi_log "Compiling with $(masi_nproc) jobs..."
  cmake --build "$build_dir" --parallel "$(masi_nproc)"

  MASI_PREFIX="$PREFIX" masi_cmake_install "$build_dir" "$APP_ID"

  local desktop_file="${PREFIX}/share/applications/flycast.desktop"
  if [[ -f "$desktop_file" ]]; then
    masi_sudo sed -i "s|^Exec=.*|Exec=${PREFIX}/bin/flycast %f|" "$desktop_file" || true
  fi
  masi_refresh_desktop_and_icons "${PREFIX}/share"

  masi_log "Removing source/build tree..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:   ${PREFIX}/bin/flycast"
  masi_log "Desktop:  ${desktop_file}"
  masi_log "Manifest: ${MASI_MANIFESTS}/${APP_ID}.txt"
  masi_log "Run: flycast"
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
