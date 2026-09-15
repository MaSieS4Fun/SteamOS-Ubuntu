#!/usr/bin/env bash
# Build / install / uninstall official shadPS4 QtLauncher (GUI only).
#
# zenithblue-oss/shadps4-arm64 does NOT embed Qt — use this launcher, then
# point Version Manager → Add Custom at ~/shadps4/<version>/shadps4 from
# scripts/shadps4.sh.
#
# No Tegra/L4T -mcpu=native. Ubuntu Mesa is never installed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="shadps4-qtlauncher"
APP_NAME="shadPS4 QtLauncher"
REPO_URL="https://github.com/shadps4-emu/shadps4-qtlauncher.git"
PREFIX="${MASI_PREFIX:-/usr/local}"
BIN_NAME="shadPS4QtLauncher"

BUILD_DEPS=(
  git cmake ninja-build pkg-config clang lld ca-certificates
  libasound2-dev libpulse-dev libopenal-dev libssl-dev zlib1g-dev
  libedit-dev libudev-dev libevdev-dev libjack-dev libsndio-dev
  libpng-dev libvulkan-dev vulkan-validationlayers
  qt6-base-dev qt6-base-private-dev qt6-tools-dev qt6-multimedia-dev
  qt6-svg-dev
  libsdl3-dev
)

GTK_DEPS=(libgtk-3-dev)

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  masi_uninstall_from_manifest "$APP_ID"
  masi_refresh_desktop_and_icons "${PREFIX}/share"
  masi_log "=== ${APP_NAME} removed ==="
  masi_log "Note: emulator cores under ~/shadps4 are left in place (use ShadPS4 uninstall)."
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
  masi_apt_install "${BUILD_DEPS[@]}" "${GTK_DEPS[@]}"

  command -v clang >/dev/null 2>&1 || masi_die "clang is required to build ${APP_NAME}"
  command -v clang++ >/dev/null 2>&1 || masi_die "clang++ is required to build ${APP_NAME}"
  command -v ld.lld >/dev/null 2>&1 || masi_die "lld is required (linker for QtLauncher build)"

  masi_prepare_build "$APP_ID"
  local src_dir="${MASI_WORK}/src"
  local build_dir="${MASI_WORK}/build"

  masi_log "Cloning ${REPO_URL} (with submodules)..."
  git clone --depth 1 "$REPO_URL" "$src_dir"
  git -C "$src_dir" submodule update --init --recursive --depth 1 \
    || git -C "$src_dir" submodule update --init --recursive

  masi_log "Configuring CMake (Release, clang, bundled fmt, updater off)..."
  # /usr/local/lib/libfmt.a on this machine is LLVM bitcode (LTO) and breaks
  # ld.bfd ("file format not recognized"). Force the in-tree fmt submodule.
  # Prefer lld so any remaining bitcode archives can still link.
  cmake -S "$src_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld" \
    -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld" \
    -DCMAKE_DISABLE_FIND_PACKAGE_fmt=ON \
    -DCMAKE_IGNORE_PREFIX_PATH="/usr/local" \
    -DENABLE_UPDATER=OFF

  masi_log "Compiling with $(masi_nproc) jobs..."
  cmake --build "$build_dir" --parallel "$(masi_nproc)"

  [[ -x "${build_dir}/${BIN_NAME}" ]] \
    || masi_die "Build did not produce ${build_dir}/${BIN_NAME}"

  MASI_PREFIX="$PREFIX" masi_cmake_install "$build_dir" "$APP_ID"
  masi_refresh_desktop_and_icons "${PREFIX}/share"

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:  ${PREFIX}/bin/${BIN_NAME}"
  masi_log "Desktop: ${PREFIX}/share/applications/net.shadps4.shadps4-qtlauncher.desktop"
  masi_shadps4_qtlauncher_warning
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
