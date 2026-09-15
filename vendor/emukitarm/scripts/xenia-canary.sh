#!/usr/bin/env bash
# Build / install / uninstall Xenia Canary from source via upstream ./xb.
#
# No cmake --install on Linux: we install the Release binary + desktop/icon
# under /usr/local ourselves (manifest-backed uninstall).
#
# Linux/ARM64 support is experimental upstream. Do not pass -mcpu=native.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/xenia_common.sh
source "${SCRIPT_DIR}/../lib/xenia_common.sh"

APP_ID="xenia-canary"
APP_NAME="Xenia Canary"
REPO_URL="https://github.com/xenia-canary/xenia-canary.git"
REPO_BRANCH="canary_experimental"
BIN_NAME="xenia_canary"
PREFIX="${MASI_PREFIX:-/usr/local}"

BUILD_DEPS=(
  build-essential git cmake ninja-build python3 ca-certificates
  clang llvm
  libc++-dev libc++abi-dev
  liblz4-dev libsdl2-dev libvulkan-dev libx11-xcb-dev
)

GTK_DEPS=(libgtk-3-dev)

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  masi_uninstall_from_manifest "$APP_ID"
  masi_refresh_desktop_and_icons "${PREFIX}/share"
  masi_log "=== ${APP_NAME} removed ==="
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} (./xb build + manual system install) ==="
  masi_log "Install prefix: ${PREFIX}"
  masi_log "Upstream has no cmake --install on Linux; packaging binary/desktop ourselves."
  masi_log "Linux/ARM64 support is experimental upstream."
  masi_log "Ubuntu Mesa will not be installed (vendor Adreno/Turnip Mesa)."

  if [[ ! -f /usr/include/EGL/egl.h ]]; then
    masi_die "Missing EGL headers (/usr/include/EGL/egl.h). Use your vendor Mesa SDK, not Ubuntu Mesa."
  fi

  masi_ensure_sudo
  masi_ensure_mesa_dev_stubs
  masi_apt_install "${BUILD_DEPS[@]}" "${GTK_DEPS[@]}"

  command -v clang >/dev/null 2>&1 || masi_die "clang is required (Xenia builds with Clang, not GCC)"
  command -v clang++ >/dev/null 2>&1 || masi_die "clang++ is required"
  command -v python3 >/dev/null 2>&1 || masi_die "python3 is required for ./xb"

  masi_prepare_build "$APP_ID"
  local src_dir="${MASI_WORK}/src"

  masi_log "Cloning ${REPO_URL} (${REPO_BRANCH})..."
  git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$src_dir"

  masi_log "Running ./xb setup (submodules + cmake)..."
  masi_xenia_run_xb "$src_dir" setup

  masi_log "Running ./xb build --config=release ($(masi_nproc) cores via ninja)..."
  masi_xenia_run_xb "$src_dir" build --config=release

  local binary
  binary="$(masi_xenia_find_binary "$src_dir" "$BIN_NAME")" \
    || masi_die "Built binary ${BIN_NAME} not found under ${src_dir}/build"

  masi_xenia_system_install \
    "$APP_ID" \
    "$BIN_NAME" \
    "$APP_NAME" \
    "Xbox 360 research emulator (Canary)" \
    "$binary" \
    "${src_dir}/assets/xenia_canary.desktop" \
    "${src_dir}/assets/icon/256.png"

  masi_log "Removing source/build tree..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:   ${PREFIX}/bin/${BIN_NAME}"
  masi_log "Desktop:  ${PREFIX}/share/applications/${BIN_NAME}.desktop"
  masi_log "Manifest: ${MASI_MANIFESTS}/${APP_ID}.txt"
  masi_log "Run: ${BIN_NAME}"
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
