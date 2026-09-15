#!/usr/bin/env bash
# Build / install / uninstall Azahar (Nintendo 3DS emulator) from source.
#
# Manual equivalent:
#   apt install <deps>
#   git clone --recurse-submodules https://github.com/azahar-emu/azahar.git
#   cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local ...
#   cmake --build build -j$(nproc)
#   sudo cmake --install build
#
# Do not enable ENABLE_NATIVE_OPTIMIZATION or pass Tegra/L4T CPU tune flags.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="azahar"
APP_NAME="Azahar"
REPO_URL="https://github.com/azahar-emu/azahar.git"
PREFIX="${MASI_PREFIX:-/usr/local}"

# glvnd only (libgl-dev/libegl-dev). Skip xorg-dev (pulls Ubuntu mesa-common-dev).
BUILD_DEPS=(
  build-essential cmake ninja-build pkg-config git ca-certificates
  libasound2-dev libgl-dev libegl-dev libopengl-dev
  libpipewire-0.3-dev libsndio-dev libssl-dev libsdl2-dev
  libx11-dev libxext-dev libxi-dev libxrandr-dev
  qt6-base-dev qt6-base-private-dev qt6-l10n-tools qt6-multimedia-dev
  qt6-tools-dev qt6-tools-dev-tools
  libvulkan-dev glslang-tools
  gamemode gamemode-dev
)

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  masi_uninstall_from_manifest "$APP_ID"
  masi_refresh_desktop_and_icons "${PREFIX}/share"
  if command -v update-mime-database >/dev/null 2>&1; then
    masi_sudo update-mime-database "${PREFIX}/share/mime" >/dev/null 2>&1 || true
  fi
  masi_log "=== ${APP_NAME} removed ==="
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} (source build + cmake --install) ==="
  masi_log "Install prefix: ${PREFIX}"
  masi_log "CPU tune flags disabled (ENABLE_NATIVE_OPTIMIZATION=OFF)."
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

  masi_log "Configuring CMake (Release)..."
  # OpenGL stays off by upstream default on Linux aarch64; Vulkan on (Turnip).
  # Use GCC: more reliable on aarch64 for this project than Clang.
  cmake -S "$src_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -G Ninja \
    -DENABLE_QT=ON \
    -DENABLE_SDL2=ON \
    -DUSE_SYSTEM_SDL2=ON \
    -DENABLE_VULKAN=ON \
    -DENABLE_OPENGL=OFF \
    -DENABLE_NATIVE_OPTIMIZATION=OFF \
    -DENABLE_ROOM_STANDALONE=OFF \
    -DCITRA_WARNINGS_AS_ERRORS=OFF

  masi_log "Compiling with $(masi_nproc) jobs..."
  cmake --build "$build_dir" --parallel "$(masi_nproc)"

  MASI_PREFIX="$PREFIX" masi_cmake_install "$build_dir" "$APP_ID"

  local desktop_file="${PREFIX}/share/applications/org.azahar_emu.Azahar.desktop"
  if [[ -f "$desktop_file" && -x "${PREFIX}/bin/azahar" ]]; then
    masi_sudo sed -i \
      -e "s|^Exec=.*|Exec=${PREFIX}/bin/azahar %f|" \
      -e '/^TryExec=/d' \
      "$desktop_file"
  fi
  masi_refresh_desktop_and_icons "${PREFIX}/share"
  if command -v update-mime-database >/dev/null 2>&1; then
    masi_sudo update-mime-database "${PREFIX}/share/mime" >/dev/null 2>&1 || true
  fi

  masi_log "Removing source/build tree..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:   ${PREFIX}/bin/azahar"
  masi_log "Desktop:  ${desktop_file}"
  masi_log "Manifest: ${MASI_MANIFESTS}/${APP_ID}.txt"
  masi_log "Run: azahar"
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
