#!/usr/bin/env bash
# Build / install / uninstall Dolphin Emulator from source.
#
# Manual equivalent:
#   apt install <deps>
#   git clone --recurse-submodules https://github.com/dolphin-emu/dolphin.git
#   cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local ...
#   cmake --build build -j$(nproc)
#   sudo cmake --install build
#
# Do not pass Tegra/L4T CPU tune flags; they crash on sm8550.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="dolphin"
APP_NAME="Dolphin"
REPO_URL="https://github.com/dolphin-emu/dolphin.git"
PREFIX="${MASI_PREFIX:-/usr/local}"

# Use glvnd (libgl-dev/libegl-dev), never Ubuntu *-mesa-dev.
BUILD_DEPS=(
  build-essential clang cmake ninja-build pkg-config git ca-certificates
  libx11-dev libxrandr-dev libxi-dev libegl-dev libopengl-dev libgl-dev
  libavcodec-dev libavformat-dev libavutil-dev libswresample-dev libswscale-dev
  libudev-dev libevdev-dev
  libsdl3-dev
  glslang-dev glslang-tools libpugixml-dev libenet-dev libxxhash-dev
  libbz2-dev liblzma-dev libzstd-dev zlib1g-dev libminizip-ng-dev liblzo2-dev liblz4-dev
  libspng-dev libcubeb-dev libusb-1.0-0-dev libsfml-dev libminiupnpc-dev
  libcurl4-openssl-dev libhidapi-dev libbluetooth-dev
  qt6-base-dev qt6-base-private-dev qt6-svg-dev
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
  masi_log "CPU tune flags disabled (not for sm8550)."
  masi_log "Ubuntu Mesa will not be installed (vendor Adreno/Turnip Mesa)."

  if [[ ! -f /usr/include/EGL/egl.h ]]; then
    masi_die "Missing EGL headers (/usr/include/EGL/egl.h). Use your vendor Mesa SDK, not Ubuntu Mesa."
  fi

  masi_ensure_sudo
  masi_apt_install "${BUILD_DEPS[@]}"

  masi_prepare_build "$APP_ID"
  local src_dir="${MASI_WORK}/src"
  local build_dir="${MASI_WORK}/build"

  masi_log "Cloning ${REPO_URL} (with submodules)..."
  git clone --depth 1 "$REPO_URL" "$src_dir"
  git -C "$src_dir" submodule update --init --recursive --depth 1 \
    || git -C "$src_dir" submodule update --init --recursive

  masi_log "Configuring CMake (Release, native aarch64 detection)..."
  # USE_SYSTEM_FMT=OFF: Ubuntu libfmt + Clang consteval breaks LogManager.cpp.
  cmake -S "$src_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DENABLE_QT=ON \
    -DUSE_SYSTEM_FMT=OFF \
    -DUSE_SYSTEM_MBEDTLS=OFF \
    -DUSE_SYSTEM_LIBMGBA=OFF \
    -G Ninja

  masi_log "Compiling with $(masi_nproc) jobs..."
  cmake --build "$build_dir" --parallel "$(masi_nproc)"

  MASI_PREFIX="$PREFIX" masi_cmake_install "$build_dir" "$APP_ID"

  local desktop_file="${PREFIX}/share/applications/dolphin-emu.desktop"
  if [[ -f "$desktop_file" ]]; then
    # Prefer absolute path so the menu entry works regardless of PATH.
    if [[ -x "${PREFIX}/bin/dolphin-emu" ]]; then
      masi_sudo sed -i "s|^Exec=.*|Exec=${PREFIX}/bin/dolphin-emu|" "$desktop_file"
    fi
  fi
  masi_refresh_desktop_and_icons "${PREFIX}/share"

  masi_log "Removing source/build tree..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:   ${PREFIX}/bin/dolphin-emu"
  masi_log "Desktop:  ${desktop_file}"
  masi_log "Manifest: ${MASI_MANIFESTS}/${APP_ID}.txt"
  masi_log "Run: dolphin-emu"
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
