#!/usr/bin/env bash
# Build / install / uninstall Cemu (Wii U emulator) from source.
#
# Same flow as a manual PC/Linux build (vcpkg + cmake + ninja). Cemu has no
# useful cmake --install on Linux; we install bin/ + desktop metadata like a
# packager would, and keep a manifest for uninstall.
#
# Do not pass Tegra/L4T CPU tune flags.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="cemu"
APP_NAME="Cemu"
REPO_URL="https://github.com/cemu-project/Cemu.git"
PREFIX="${MASI_PREFIX:-/usr/local}"

BUILD_DEPS=(
  build-essential clang cmake ninja-build pkg-config git curl ca-certificates
  nasm unzip zip libtool
  freeglut3-dev libgcrypt20-dev libglm-dev
  libpulse-dev libsecret-1-dev libsystemd-dev libudev-dev libbluetooth-dev
  libusb-1.0-0-dev
  libegl-dev libopengl-dev libgl-dev libwayland-dev wayland-protocols
  libx11-dev libxext-dev libxi-dev libxrandr-dev libxcursor-dev
  libxinerama-dev libxxf86vm-dev libxkbcommon-dev libdbus-1-dev
  # Installed after Mesa -dev stubs (see do_install):
  # libgtk-3-dev
)

GTK_DEPS=(libgtk-3-dev)

write_manifest() {
  local manifest="${MASI_MANIFESTS}/${APP_ID}.txt"
  mkdir -p "$MASI_MANIFESTS"
  : >"$manifest"
  local f
  for f in "$@"; do
    [[ -n "$f" ]] || continue
    printf '%s\n' "$f" >>"$manifest"
  done
  # Also record share tree files for uninstall.
  if [[ -d "${PREFIX}/share/Cemu" ]]; then
    find "${PREFIX}/share/Cemu" -print >>"$manifest" || true
  fi
  chmod 644 "$manifest"
  masi_log "Saved install manifest: $manifest"
}

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  if [[ -f "${MASI_MANIFESTS}/${APP_ID}.txt" ]]; then
    masi_uninstall_from_manifest "$APP_ID"
  else
    masi_ensure_sudo
    masi_sudo rm -f "${PREFIX}/bin/Cemu" \
      "${PREFIX}/share/applications/info.cemu.Cemu.desktop" \
      "${PREFIX}/share/icons/hicolor/128x128/apps/info.cemu.Cemu.png"
    masi_sudo rm -rf "${PREFIX}/share/Cemu"
  fi
  masi_refresh_desktop_and_icons "${PREFIX}/share"
  masi_log "=== ${APP_NAME} removed ==="
}

install_cemu_tree() {
  local src_dir="$1"
  local bin_dir="${src_dir}/bin"
  local binary=""

  if [[ -x "${bin_dir}/Cemu_release" ]]; then
    binary="${bin_dir}/Cemu_release"
  elif [[ -x "${bin_dir}/Cemu" ]]; then
    binary="${bin_dir}/Cemu"
  else
    binary="$(find "$bin_dir" -maxdepth 1 -type f -executable -name 'Cemu*' | head -n1 || true)"
  fi
  [[ -n "$binary" && -x "$binary" ]] || masi_die "Cemu binary not found under ${bin_dir}"

  masi_ensure_sudo
  masi_log "Installing ${binary} -> ${PREFIX}/bin/Cemu"
  masi_sudo install -Dm755 "$binary" "${PREFIX}/bin/Cemu"

  masi_sudo mkdir -p "${PREFIX}/share/Cemu"
  local item base
  for item in "$bin_dir"/*; do
    [[ -e "$item" ]] || continue
    base="$(basename "$item")"
    # Skip the built executables; binary already installed as Cemu.
    if [[ -f "$item" && -x "$item" && "$base" == Cemu* ]]; then
      continue
    fi
    masi_sudo cp -a "$item" "${PREFIX}/share/Cemu/"
  done

  local desktop_src="${src_dir}/dist/linux/info.cemu.Cemu.desktop"
  local icon_src="${src_dir}/dist/linux/info.cemu.Cemu.png"
  local desktop_dst="${PREFIX}/share/applications/info.cemu.Cemu.desktop"
  local icon_dst="${PREFIX}/share/icons/hicolor/128x128/apps/info.cemu.Cemu.png"

  [[ -f "$desktop_src" ]] || masi_die "Missing $desktop_src"
  [[ -f "$icon_src" ]] || masi_die "Missing $icon_src"

  masi_sudo install -Dm644 "$icon_src" "$icon_dst"
  masi_sudo install -Dm644 "$desktop_src" "$desktop_dst"
  masi_sudo sed -i \
    -e "s|^Exec=.*|Exec=${PREFIX}/bin/Cemu|" \
    -e '/^TryExec=/d' \
    "$desktop_dst"

  write_manifest \
    "${PREFIX}/bin/Cemu" \
    "$desktop_dst" \
    "$icon_dst"

  masi_refresh_desktop_and_icons "${PREFIX}/share"
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} (source build, PC-style) ==="
  masi_log "Install prefix: ${PREFIX}"
  masi_log "CPU tune flags disabled."
  masi_log "Ubuntu Mesa will not be installed (vendor Adreno/Turnip Mesa)."

  if [[ ! -f /usr/include/EGL/egl.h ]]; then
    masi_die "Missing EGL headers (/usr/include/EGL/egl.h). Use your vendor Mesa SDK, not Ubuntu Mesa."
  fi

  masi_ensure_sudo
  # GTK3 -dev needs Mesa -dev stubs on this platform.
  masi_ensure_mesa_dev_stubs
  masi_apt_install "${BUILD_DEPS[@]}" "${GTK_DEPS[@]}"

  masi_prepare_build "$APP_ID"
  local src_dir="${MASI_WORK}/src"
  local build_dir="${MASI_WORK}/build"

  masi_log "Cloning ${REPO_URL} (recursive submodules / vcpkg)..."
  git clone --recursive "$REPO_URL" "$src_dir"

  # aarch64 vcpkg often needs this.
  export VCPKG_FORCE_SYSTEM_BINARIES=1

  masi_log "Configuring CMake (Release + vcpkg)..."
  cmake -S "$src_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -G Ninja \
    -DENABLE_VCPKG=ON \
    -DENABLE_VULKAN=ON \
    -DENABLE_OPENGL=ON \
    -DENABLE_WXWIDGETS=ON \
    -DALLOW_PORTABLE=ON

  masi_log "Compiling with $(masi_nproc) jobs (first run fetches vcpkg deps)..."
  cmake --build "$build_dir" --parallel "$(masi_nproc)"

  install_cemu_tree "$src_dir"

  masi_log "Removing source/build tree..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:   ${PREFIX}/bin/Cemu"
  masi_log "Data:     ${PREFIX}/share/Cemu"
  masi_log "Desktop:  ${PREFIX}/share/applications/info.cemu.Cemu.desktop"
  masi_log "Manifest: ${MASI_MANIFESTS}/${APP_ID}.txt"
  masi_log "Run: Cemu"
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
