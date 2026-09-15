#!/usr/bin/env bash
# Build / install / uninstall Vita3K from source (cmake --install).
#
# Upstream Linux install puts the binary + /usr/local/share/Vita3K data tree
# (shaders, icons, desktop entry). Prefer that over AppImage.
#
# Note: Vita3K currently requires Qt >= 6.11; Ubuntu 26.04 ships 6.10.x.
# We lower the CMake gate to the system Qt so the build can proceed.
# Do not pass Tegra/L4T -mcpu=native flags.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="vita3k"
APP_NAME="Vita3K"
REPO_URL="https://github.com/Vita3K/Vita3K.git"
PREFIX="${MASI_PREFIX:-/usr/local}"

BUILD_DEPS=(
  git cmake ninja-build pkg-config clang lld
  ca-certificates openssl libssl-dev
  libsdl3-dev
  xdg-desktop-portal
  qt6-base-dev qt6-base-private-dev qt6-svg-dev qt6-multimedia-dev qt6-tools-dev
  libboost-filesystem-dev
)

GTK_DEPS=(libgtk-3-dev)

system_qt_version() {
  python3 - <<'PY'
from pathlib import Path
import re
cands = list(Path("/usr/lib").rglob("Qt6ConfigVersionImpl.cmake"))
cands += list(Path("/usr/lib").rglob("Qt6ConfigVersion.cmake"))
ver = None
for p in cands:
    try:
        t = p.read_text(errors="ignore")
    except OSError:
        continue
    m = re.search(r'PACKAGE_VERSION\s+"([0-9.]+)"', t)
    if m:
        ver = m.group(1)
        break
print(ver or "")
PY
}

relax_qt_min_version() {
  local src_dir="$1"
  local qt_cmake="${src_dir}/cmake/qt6.cmake"
  local sys_ver want="6.10.0"
  [[ -f "$qt_cmake" ]] || return 0

  sys_ver="$(system_qt_version)"
  if [[ -z "$sys_ver" ]]; then
    masi_log "Could not detect system Qt6 version; leaving Vita3K Qt gate unchanged."
    return 0
  fi

  masi_log "System Qt6: ${sys_ver} (upstream Vita3K asks for >= 6.11.0)."
  # Only relax when distro is slightly behind (6.10.x).
  if [[ "$sys_ver" == 6.10.* ]]; then
    want="6.10.0"
    masi_log "Relaxing cmake/qt6.cmake VITA3K_QT_MIN_VER to ${want} for this distro."
    sed -i -E "s/set\(VITA3K_QT_MIN_VER[[:space:]]+[0-9.]+\)/set(VITA3K_QT_MIN_VER ${want})/" "$qt_cmake"
  elif [[ "$sys_ver" == 6.9.* || "$sys_ver" == 6.8.* ]]; then
    want="$sys_ver"
    masi_log "Relaxing cmake/qt6.cmake VITA3K_QT_MIN_VER to ${want} (may fail if 6.11 APIs are required)."
    sed -i -E "s/set\(VITA3K_QT_MIN_VER[[:space:]]+[0-9.]+\)/set(VITA3K_QT_MIN_VER ${want})/" "$qt_cmake"
  else
    masi_log "System Qt looks new enough; not patching qt6.cmake."
  fi
}

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  masi_uninstall_from_manifest "$APP_ID"
  masi_refresh_desktop_and_icons "${PREFIX}/share"
  if command -v update-mime-database >/dev/null 2>&1; then
    masi_sudo update-mime-database "${PREFIX}/share/mime" >/dev/null 2>&1 || true
  fi
  # cmake install may leave the share tree; remove if empty of other apps.
  if [[ -d "${PREFIX}/share/Vita3K" ]]; then
    masi_sudo rm -rf "${PREFIX}/share/Vita3K"
  fi
  masi_log "=== ${APP_NAME} removed ==="
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} (source build + cmake --install) ==="
  masi_log "Install prefix: ${PREFIX}"
  masi_log "AppImage skipped (prefer system install when cmake --install works)."
  masi_log "CPU tune flags disabled (not for sm8550)."
  masi_log "Ubuntu Mesa will not be installed (vendor Adreno/Turnip Mesa)."

  if [[ ! -f /usr/include/EGL/egl.h ]]; then
    masi_die "Missing EGL headers (/usr/include/EGL/egl.h). Use your vendor Mesa SDK, not Ubuntu Mesa."
  fi

  masi_ensure_sudo
  masi_ensure_mesa_dev_stubs
  masi_apt_install "${BUILD_DEPS[@]}" "${GTK_DEPS[@]}"

  command -v clang >/dev/null 2>&1 || masi_die "clang is required to build Vita3K"
  command -v clang++ >/dev/null 2>&1 || masi_die "clang++ is required to build Vita3K"
  command -v ld.lld >/dev/null 2>&1 || masi_die "lld is required (linux-ninja-clang uses -fuse-ld=lld)"

  masi_prepare_build "$APP_ID"
  local src_dir="${MASI_WORK}/src"
  local build_dir="${MASI_WORK}/build"

  masi_log "Cloning ${REPO_URL} (with submodules)..."
  git clone --depth 1 "$REPO_URL" "$src_dir"
  git -C "$src_dir" submodule update --init --recursive --depth 1 \
    || git -C "$src_dir" submodule update --init --recursive

  relax_qt_min_version "$src_dir"

  masi_log "Configuring CMake (Release, clang + lld, Discord off)..."
  export LDFLAGS="${LDFLAGS:-} -fuse-ld=lld"
  cmake -S "$src_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DUSE_DISCORD_RICH_PRESENCE=OFF \
    -DBUILD_APPIMAGE=OFF \
    -DVITA3K_FORCE_SYSTEM_BOOST=ON

  masi_log "Compiling with $(masi_nproc) jobs..."
  cmake --build "$build_dir" --parallel "$(masi_nproc)"

  MASI_PREFIX="$PREFIX" masi_cmake_install "$build_dir" "$APP_ID"

  local desktop_file="${PREFIX}/share/applications/org.vita3k.vita3k.desktop"
  if [[ -f "$desktop_file" && -x "${PREFIX}/bin/Vita3K" ]]; then
    masi_sudo sed -i \
      -e "s|^Exec=.*|Exec=${PREFIX}/bin/Vita3K %f|" \
      -e '/^TryExec=/d' \
      "$desktop_file"
  fi
  masi_refresh_desktop_and_icons "${PREFIX}/share"

  masi_log "Removing source/build tree..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:   ${PREFIX}/bin/Vita3K"
  masi_log "Data:     ${PREFIX}/share/Vita3K"
  masi_log "Desktop:  ${desktop_file}"
  masi_log "Manifest: ${MASI_MANIFESTS}/${APP_ID}.txt"
  masi_log "Run: Vita3K"
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
