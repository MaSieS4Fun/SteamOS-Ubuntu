#!/usr/bin/env bash
# Build / install / uninstall Eden (Nintendo Switch emulator) from source.
#
# AppImages black-screen / hang on sm8550 — always compile.
# Required CMake flags on this platform (device lost without them):
#   -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
#   -DYUZU_TESTS=OFF -DYUZU_BUILD_PRESET=optimized
#
# optimized => -march=armv8.2-a+lse+rcpc (not native; native crashes on sm8550).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="megic"
APP_NAME="Eden"
REPO_URL="https://git.eden-emu.dev/eden-emu/eden.git"
PREFIX="${MASI_PREFIX:-/usr/local}"

# Curated for Ubuntu 26.04 / sm8550 (official docs list packages that do not exist here).
BUILD_DEPS=(
  autoconf cmake g++ gcc git clang glslang-tools libglu1-mesa-dev libhidapi-dev
  libpulse-dev libtool libudev-dev libxcb-icccm4 libxcb-image0 libxcb-keysyms1
  libxcb-render-util0 libxcb-xinerama0 libxcb-xkb1 libxext-dev libxkbcommon-x11-0
  nasm ninja-build qt6-base-private-dev catch2 libfmt-dev liblz4-dev
  nlohmann-json3-dev libzstd-dev libssl-dev libavfilter-dev libavcodec-dev
  libswscale-dev pkg-config zlib1g-dev libva-dev libvdpau-dev qt6-tools-dev
  qt6-charts-dev libvulkan-dev spirv-tools spirv-headers libusb-1.0-0-dev
  libboost-dev libboost-fiber-dev libboost-context-dev libsdl3-dev libopus-dev
  libasound2t64 vulkan-utility-libraries-dev ca-certificates
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
  masi_log "AppImage skipped (black screen / hang on sm8550)."
  masi_log "CMake: clang + YUZU_BUILD_PRESET=optimized (required; avoids Vulkan device lost)."
  masi_log "Ubuntu Mesa will not be installed (vendor Adreno/Turnip Mesa)."

  if [[ ! -f /usr/include/EGL/egl.h ]]; then
    masi_die "Missing EGL headers (/usr/include/EGL/egl.h). Use your vendor Mesa SDK, not Ubuntu Mesa."
  fi

  masi_ensure_sudo
  masi_apt_install "${BUILD_DEPS[@]}"
  command -v clang >/dev/null 2>&1 || masi_die "clang is required to build Eden"
  command -v clang++ >/dev/null 2>&1 || masi_die "clang++ is required to build Eden"

  masi_prepare_build "$APP_ID"
  local src_dir="${MASI_WORK}/src"
  local build_dir="${MASI_WORK}/build"

  masi_log "Cloning ${REPO_URL} (with submodules)..."
  git clone --depth 1 "$REPO_URL" "$src_dir"
  git -C "$src_dir" submodule update --init --recursive --depth 1 \
    || git -C "$src_dir" submodule update --init --recursive

  masi_log "Configuring CMake (Release, clang, optimized)..."
  # Flags match the known-good sm8550 build; do not use YUZU_BUILD_PRESET=native.
  cmake -S "$src_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DYUZU_TESTS=OFF \
    -DYUZU_BUILD_PRESET=optimized

  masi_log "Compiling with $(masi_nproc) jobs..."
  cmake --build "$build_dir" --parallel "$(masi_nproc)"

  MASI_PREFIX="$PREFIX" masi_cmake_install "$build_dir" "$APP_ID"

  local desktop_file="${PREFIX}/share/applications/dev.eden_emu.eden.desktop"
  if [[ -f "$desktop_file" && -x "${PREFIX}/bin/eden" ]]; then
    masi_sudo sed -i \
      -e "s|^Exec=.*|Exec=${PREFIX}/bin/eden %f|" \
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
  masi_log "Binary:   ${PREFIX}/bin/eden"
  masi_log "Desktop:  ${desktop_file}"
  masi_log "Manifest: ${MASI_MANIFESTS}/${APP_ID}.txt"
  masi_log "Run: eden"
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
