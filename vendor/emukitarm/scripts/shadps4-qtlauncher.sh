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

# Adreno/Turnip has no VDPAU. libvdpau falls back to "nvidia" and prints a
# missing libvdpau_nvidia.so warning (red herring — do NOT install NVIDIA libs).
# Qt FFmpeg multimedia triggers that probe; GStreamer avoids it. Wayland often
# segfaults shadPS4 Qt UIs — default to xcb (overridable via QT_QPA_PLATFORM).
install_qtlauncher_wrapper() {
  local prefix="$1"
  local libexec_dir="${prefix}/libexec/shadps4"
  local real_bin="${libexec_dir}/${BIN_NAME}"
  local wrap_bin="${prefix}/bin/${BIN_NAME}"
  local desktop="${prefix}/share/applications/net.shadps4.shadps4-qtlauncher.desktop"
  local manifest="${MASI_MANIFESTS}/${APP_ID}.txt"

  masi_sudo mkdir -p "$libexec_dir"

  if [[ -x "$wrap_bin" && ! -L "$wrap_bin" ]]; then
    # Fresh cmake --install drops a real ELF in bin/; relocate it once.
    if file -b "$wrap_bin" 2>/dev/null | grep -qi 'elf'; then
      masi_sudo mv -f "$wrap_bin" "$real_bin"
    elif [[ ! -x "$real_bin" ]]; then
      masi_die "Expected ELF at ${wrap_bin} after cmake --install"
    fi
  elif [[ -x "$wrap_bin" && -L "$wrap_bin" && ! -x "$real_bin" ]]; then
    masi_die "Wrapper present but missing real binary: ${real_bin}"
  fi

  [[ -x "$real_bin" ]] || masi_die "Missing real ${APP_NAME} binary at ${real_bin}"

  masi_sudo tee "$wrap_bin" >/dev/null <<EOF
#!/usr/bin/env bash
# EmuKitARM wrapper for ${BIN_NAME} (Adreno — no NVIDIA VDPAU).
set -euo pipefail
export QT_MEDIA_BACKEND="\${QT_MEDIA_BACKEND:-gstreamer}"
export QT_QPA_PLATFORM="\${QT_QPA_PLATFORM:-xcb}"
exec "${real_bin}" "\$@"
EOF
  masi_sudo chmod 755 "$wrap_bin"

  if [[ -f "$desktop" ]]; then
    masi_sudo sed -i \
      "s|^Exec=.*|Exec=env QT_MEDIA_BACKEND=gstreamer QT_QPA_PLATFORM=xcb ${wrap_bin}|" \
      "$desktop"
  fi

  if [[ -f "$manifest" ]]; then
    grep -qxF "$real_bin" "$manifest" || echo "$real_bin" >>"$manifest"
    grep -qxF "$wrap_bin" "$manifest" || echo "$wrap_bin" >>"$manifest"
  fi

  masi_log "Installed Adreno-safe launcher wrapper → ${wrap_bin}"
  masi_log "  real binary: ${real_bin}"
  masi_log "  QT_MEDIA_BACKEND=gstreamer (skips FFmpeg→VDPAU nvidia fallback spam)"
  masi_log "  QT_QPA_PLATFORM=xcb (avoids Wayland Qt segfaults)"
}

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  masi_uninstall_from_manifest "$APP_ID"
  # Leftovers if an older install moved the ELF outside the manifest.
  masi_sudo rm -f "${PREFIX}/libexec/shadps4/${BIN_NAME}" 2>/dev/null || true
  masi_sudo rmdir "${PREFIX}/libexec/shadps4" 2>/dev/null || true
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
  install_qtlauncher_wrapper "$PREFIX"
  masi_refresh_desktop_and_icons "${PREFIX}/share"

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:  ${PREFIX}/bin/${BIN_NAME} (wrapper)"
  masi_log "Desktop: ${PREFIX}/share/applications/net.shadps4.shadps4-qtlauncher.desktop"
  masi_shadps4_qtlauncher_warning
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  --fix-wrapper|fix-wrapper)
    masi_require_aarch64
    masi_ensure_sudo
    install_qtlauncher_wrapper "$PREFIX"
    masi_refresh_desktop_and_icons "${PREFIX}/share"
    ;;
  *) do_install ;;
esac
