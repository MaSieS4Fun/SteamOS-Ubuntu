#!/usr/bin/env bash
# Build / install / uninstall ARMSX3 (RPCS3 fork) from source for Linux aarch64.
#
# Upstream README focuses on Android APKs (no Linux release branch), but the
# tree still builds the desktop RPCS3 Qt frontend. CI scripts
# (.ci/build-linux-aarch64.sh) use cmake + ninja install — we follow that,
# then rename the binary to armsx3 so it does not collide with the official
# RPCS3 AppImage launcher.
#
# Critical on sm8550: USE_NATIVE_INSTRUCTIONS=OFF (no -march=native).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="armsx3"
APP_NAME="ARMSX3"
REPO_URL="https://github.com/ARMSX2/ARMSX3.git"
PREFIX="${MASI_PREFIX:-/usr/local}"
BIN_NAME="armsx3"

BUILD_DEPS=(
  build-essential git cmake ninja-build pkg-config ca-certificates
  clang lld llvm-21-dev
  libasound2-dev libpulse-dev libopenal-dev libglew-dev zlib1g-dev libedit-dev
  libvulkan-dev libudev-dev libevdev-dev libsdl3-dev libjack-dev libsndio-dev
  libcurl4-openssl-dev libxkbcommon-dev libxkbcommon-x11-dev libx11-dev
  qt6-base-dev qt6-base-private-dev qt6-multimedia-dev qt6-svg-dev
  libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev
  libopencv-dev
)

find_llvm_dir() {
  local d
  for d in /usr/lib/llvm-21 /usr/lib/llvm-20 /usr/lib/llvm-19; do
    if [[ -f "${d}/lib/cmake/llvm/LLVMConfig.cmake" ]]; then
      printf '%s\n' "${d}/lib/cmake/llvm"
      return 0
    fi
  done
  return 1
}

# ARMSX3 always lists OboeBackend.cpp, but Oboe headers/libs are Android-only
# (3rdparty::oboe is linked only when ANDROID). Desktop builds then fail with
# missing oboe/Oboe.h. Gate the source the same way as the link line.
#
# Also fix case-sensitive includes that work on Android/Windows but break on
# Linux (Emu/system.h -> Emu/System.h).
patch_for_linux_desktop() {
  local src_dir="$1"
  local emu_cmake="${src_dir}/rpcs3/Emu/CMakeLists.txt"
  local sync_cpp="${src_dir}/rpcs3/Emu/RSX/VK/vkutils/sync.cpp"
  [[ -f "$emu_cmake" ]] || masi_die "Missing ${emu_cmake}"

  if [[ -f "$sync_cpp" ]] && grep -q '#include "Emu/system.h"' "$sync_cpp"; then
    masi_log "Fixing case-sensitive include in sync.cpp (Emu/system.h -> Emu/System.h)."
    sed -i 's|#include "Emu/system.h"|#include "Emu/System.h"|' "$sync_cpp"
  fi

  # FrameGenTypes.h still pulls Eden's Config.h; settings already come from FrameGenConfig.h.
  local framegen_types="${src_dir}/rpcs3/Emu/RSX/VK/FrameGen/FrameGenTypes.h"
  if [[ -f "$framegen_types" ]] && grep -q '#include "Config.h"' "$framegen_types"; then
    masi_log "Removing unused Eden Config.h include from FrameGenTypes.h."
    sed -i '/#include "Config.h"/d' "$framegen_types"
  fi

  # ARM64 Linux cpu_capacity path uses ::open/O_RDONLY without <fcntl.h>
  # (Android headers often pull it transitively; desktop clang does not).
  local thread_cpp="${src_dir}/Utilities/Thread.cpp"
  if [[ -f "$thread_cpp" ]] && grep -q '::open(path, O_RDONLY' "$thread_cpp"; then
    if ! grep -q '#include <fcntl.h>' "$thread_cpp"; then
      masi_log "Adding #include <fcntl.h> to Utilities/Thread.cpp for ARM64 Linux."
      # Insert after the existing __linux__ unistd.h include block.
      if grep -q '#include <unistd.h>' "$thread_cpp"; then
        sed -i '/#include <unistd.h>/a #include <fcntl.h>' "$thread_cpp"
      else
        sed -i '/#ifdef __linux__/a #include <fcntl.h>' "$thread_cpp"
      fi
    fi
  fi

  # X11/X.h #define CWX clashes with SPU opcode GET(CWX) when VK/X11
  # headers are included before SPUOpcodes.h (overlay_perf_metrics.cpp).
  local spu_opcodes="${src_dir}/rpcs3/Emu/Cell/SPUOpcodes.h"
  if [[ -f "$spu_opcodes" ]] && grep -q 'GET(CWX)' "$spu_opcodes"; then
    if ! grep -q 'MasiScript: X11 CWX' "$spu_opcodes"; then
      masi_log "Undefining X11 CWX macro in SPUOpcodes.h before SPU opcode table."
      python3 - "$spu_opcodes" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
needle = '#include "Utilities/BitField.h"\n'
if needle not in text:
    raise SystemExit("BitField include not found in SPUOpcodes.h")
insert = (
    needle
    + "\n"
    + "// MasiScript: X11 CWX macro clashes with SPU opcode GET(CWX) on Linux.\n"
    + "#ifdef CWX\n"
    + "#undef CWX\n"
    + "#endif\n"
)
text = text.replace(needle, insert, 1)
path.write_text(text)
print("patched", path)
PY
    fi
  fi

  # FrameGen / swapchain.cpp read g_cfg.video.frame_generation* but those
  # cfg members are behind #ifdef __ANDROID__. Desktop still compiles FrameGen,
  # so expose the settings (default off) on Linux too.
  local sys_cfg="${src_dir}/rpcs3/Emu/system_config.h"
  if [[ -f "$sys_cfg" ]] && grep -q 'frame_generation{' "$sys_cfg"; then
    if ! grep -q 'MasiScript: frame_generation cfg' "$sys_cfg"; then
      masi_log "Exposing frame_generation config members for Linux desktop builds."
      python3 - "$sys_cfg" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
pattern = re.compile(
    r"#ifdef __ANDROID__\n"
    r"(?P<body>\t\t// ARMSX3: Lossless Scaling frame generation\..*?"
    r"cfg::string frame_generation_dll_path\{ this, \"Frame Generation Lossless Path\", \"\", true \};\n)"
    r"#endif\n",
    re.S,
)
m = pattern.search(text)
if not m:
    raise SystemExit("frame_generation ANDROID block not found in system_config.h")
replacement = (
    "// MasiScript: frame_generation cfg also needed on Linux (FrameGen/swapchain).\n"
    + m.group("body")
)
text = pattern.sub(replacement, text, count=1)
path.write_text(text)
print("patched", path)
PY
    fi
  fi

  # Non-Android stub of capture_presented_frame is missing guest_width/height
  # args, so the linker cannot resolve the symbol used by VKPresent.cpp.
  local vk_framegen="${src_dir}/rpcs3/Emu/RSX/VK/VKFrameGen.cpp"
  if [[ -f "$vk_framegen" ]]; then
    if grep -q 'bool capture_presented_frame(const vk::command_buffer&, const vk::render_device&, VkImage, VkImageLayout, u32, u32)$' "$vk_framegen" \
      || grep -q 'bool capture_presented_frame(const vk::command_buffer&, const vk::render_device&, VkImage, VkImageLayout, u32, u32)' "$vk_framegen"; then
      if ! grep -q 'MasiScript: capture_presented_frame stub' "$vk_framegen"; then
        masi_log "Fixing non-Android capture_presented_frame stub signature in VKFrameGen.cpp."
        python3 - "$vk_framegen" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
# Only patch the short desktop stub (6 params), not the Android implementation.
pattern = re.compile(
    r"bool capture_presented_frame\(const vk::command_buffer&, const vk::render_device&, "
    r"VkImage, VkImageLayout, u32, u32\)\n"
    r"\t\{\n"
    r"\t\treturn false;\n"
    r"\t\}"
)
replacement = (
    "// MasiScript: capture_presented_frame stub must match the 8-arg declaration.\n"
    "bool capture_presented_frame(const vk::command_buffer&, const vk::render_device&, "
    "VkImage, VkImageLayout, u32, u32, u32, u32)\n"
    "\t{\n"
    "\t\treturn false;\n"
    "\t}"
)
new_text, n = pattern.subn(replacement, text, count=1)
if n != 1:
    raise SystemExit(f"desktop capture_presented_frame stub not found (matches={n})")
path.write_text(new_text)
print("patched", path)
PY
      fi
    fi
  fi

  if ! grep -q 'Audio/Oboe/OboeBackend.cpp' "$emu_cmake"; then
    masi_log "OboeBackend.cpp not listed in Emu CMakeLists; skipping Oboe patch."
    return 0
  fi
  if grep -q 'MasiScript: Oboe is Android-only' "$emu_cmake"; then
    masi_log "Oboe Linux patch already applied."
    return 0
  fi

  masi_log "Patching Emu CMakeLists: compile OboeBackend only on Android."
  python3 - "$emu_cmake" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
line = "    Audio/Oboe/OboeBackend.cpp\n"
if line not in text:
    raise SystemExit(f"Expected OboeBackend.cpp line not found in {path}")
text = text.replace(line, "", 1)

marker = "    Audio/Cubeb/cubeb_enumerator.cpp\n)"
if marker not in text:
    raise SystemExit("Could not find Audio target_sources closing marker to patch")

replacement = (
    "    Audio/Cubeb/cubeb_enumerator.cpp\n"
    ")\n"
    "\n"
    "# MasiScript: Oboe is Android-only (oboe/Oboe.h); keep desktop builds working.\n"
    "if(ANDROID)\n"
    "    target_sources(rpcs3_emu PRIVATE\n"
    "        Audio/Oboe/OboeBackend.cpp\n"
    "    )\n"
    "endif()\n"
)
text = text.replace(marker, replacement, 1)
path.write_text(text)
print("patched", path)
PY
}

finalize_as_armsx3() {
  local prefix="$1"
  local rpcs3_bin="${prefix}/bin/rpcs3"
  local armsx3_bin="${prefix}/bin/${BIN_NAME}"
  local desktop_src="${prefix}/share/applications/rpcs3.desktop"
  local desktop_dst="${prefix}/share/applications/${BIN_NAME}.desktop"
  local icon_png="${prefix}/share/icons/hicolor/48x48/apps/rpcs3.png"
  local icon_svg="${prefix}/share/icons/hicolor/scalable/apps/rpcs3.svg"

  [[ -x "$rpcs3_bin" ]] || masi_die "cmake --install did not produce ${rpcs3_bin}"

  masi_log "Renaming system binary rpcs3 -> ${BIN_NAME} (avoid clash with RPCS3 AppImage)."
  masi_sudo mv -f "$rpcs3_bin" "$armsx3_bin"

  if [[ -f "$desktop_src" ]]; then
    masi_sudo cp -a "$desktop_src" "$desktop_dst"
    masi_sudo rm -f "$desktop_src"
    masi_sudo sed -i \
      -e "s|^Name=.*|Name=ARMSX3|" \
      -e "s|^GenericName=.*|GenericName=PlayStation 3 Emulator|" \
      -e "s|^Comment=.*|Comment=ARMSX3 — RPCS3 fork for ARM64 (desktop build)|" \
      -e "s|^Exec=.*|Exec=${armsx3_bin} %f|" \
      -e "s|^Icon=.*|Icon=${BIN_NAME}|" \
      -e "s|^StartupWMClass=.*|StartupWMClass=${BIN_NAME}|" \
      -e '/^TryExec=/d' \
      "$desktop_dst"
  fi

  # Alias icons under armsx3 name when present.
  if [[ -f "$icon_png" ]]; then
    masi_sudo install -Dm644 "$icon_png" \
      "${prefix}/share/icons/hicolor/48x48/apps/${BIN_NAME}.png"
  fi
  if [[ -f "$icon_svg" ]]; then
    masi_sudo install -Dm644 "$icon_svg" \
      "${prefix}/share/icons/hicolor/scalable/apps/${BIN_NAME}.svg"
  fi

  # Refresh manifest paths after rename.
  local manifest="${MASI_MANIFESTS}/${APP_ID}.txt"
  if [[ -f "$manifest" ]]; then
    sed -i \
      -e "s|${prefix}/bin/rpcs3|${armsx3_bin}|g" \
      -e "s|${prefix}/share/applications/rpcs3.desktop|${desktop_dst}|g" \
      "$manifest"
    {
      [[ -f "${prefix}/share/icons/hicolor/48x48/apps/${BIN_NAME}.png" ]] \
        && echo "${prefix}/share/icons/hicolor/48x48/apps/${BIN_NAME}.png"
      [[ -f "${prefix}/share/icons/hicolor/scalable/apps/${BIN_NAME}.svg" ]] \
        && echo "${prefix}/share/icons/hicolor/scalable/apps/${BIN_NAME}.svg"
    } >>"$manifest"
  fi
}

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  masi_uninstall_from_manifest "$APP_ID"
  # Share tree may remain partially if manifest missed dirs.
  if [[ -d "${PREFIX}/share/rpcs3" ]]; then
    masi_sudo rm -rf "${PREFIX}/share/rpcs3"
  fi
  masi_sudo rm -f \
    "${PREFIX}/bin/${BIN_NAME}" \
    "${PREFIX}/share/applications/${BIN_NAME}.desktop" \
    "${PREFIX}/share/icons/hicolor/48x48/apps/${BIN_NAME}.png" \
    "${PREFIX}/share/icons/hicolor/scalable/apps/${BIN_NAME}.svg"
  masi_refresh_desktop_and_icons "${PREFIX}/share"
  masi_log "=== ${APP_NAME} removed ==="
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} (source build + cmake --install) ==="
  masi_log "Install prefix: ${PREFIX}"
  masi_log "No Linux AppImage/release from upstream; building desktop Qt frontend from the ARMSX3 tree."
  masi_log "USE_NATIVE_INSTRUCTIONS=OFF (required on sm8550)."
  masi_log "Binary will be installed as ${BIN_NAME} (not rpcs3)."
  masi_log "Ubuntu Mesa will not be installed (vendor Adreno/Turnip Mesa)."

  if [[ ! -f /usr/include/EGL/egl.h ]]; then
    masi_die "Missing EGL headers (/usr/include/EGL/egl.h). Use your vendor Mesa SDK, not Ubuntu Mesa."
  fi

  masi_ensure_sudo
  masi_apt_install "${BUILD_DEPS[@]}"

  command -v clang >/dev/null 2>&1 || masi_die "clang is required"
  command -v clang++ >/dev/null 2>&1 || masi_die "clang++ is required"

  local llvm_dir
  llvm_dir="$(find_llvm_dir)" || masi_die "LLVM CMake package not found (install llvm-21-dev)"

  masi_prepare_build "$APP_ID"
  local src_dir="${MASI_WORK}/src"
  local build_dir="${MASI_WORK}/build"

  masi_log "Cloning ${REPO_URL} (with submodules; LLVM/OpenCV/SDL/curl/zlib skipped like CI)..."
  git clone --depth 1 "$REPO_URL" "$src_dir"
  (
    cd "$src_dir"
    # Match .ci/build-linux-aarch64.sh submodule selection.
    # shellcheck disable=SC2046
    git submodule update --init --depth 1 \
      $(awk '/path/ && !/llvm/ && !/opencv/ && !/libsdl-org/ && !/curl/ && !/zlib/ { print $3 }' .gitmodules) \
      || git submodule update --init --recursive
  )

  patch_for_linux_desktop "$src_dir"

  masi_log "Configuring CMake (Release, clang, no native CPU tune)..."
  cmake -S "$src_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld" \
    -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld" \
    -DCMAKE_MODULE_LINKER_FLAGS="-fuse-ld=lld" \
    -DUSE_NATIVE_INSTRUCTIONS=OFF \
    -DUSE_PRECOMPILED_HEADERS=OFF \
    -DUSE_SYSTEM_CURL=ON \
    -DUSE_SDL=ON \
    -DUSE_SYSTEM_SDL=ON \
    -DUSE_SYSTEM_FFMPEG=ON \
    -DUSE_SYSTEM_OPENCV=ON \
    -DUSE_DISCORD_RPC=OFF \
    -DOpenGL_GL_PREFERENCE=LEGACY \
    -DLLVM_DIR="$llvm_dir" \
    -DWITH_LLVM=ON \
    -DBUILD_LLVM=OFF \
    -DSTATIC_LINK_LLVM=OFF \
    -DBUILD_RPCS3_TESTS=OFF \
    -DRUN_RPCS3_TESTS=OFF \
    -DUSE_LTO=ON

  masi_log "Compiling with $(masi_nproc) jobs (this is a long build)..."
  cmake --build "$build_dir" --parallel "$(masi_nproc)"

  MASI_PREFIX="$PREFIX" masi_cmake_install "$build_dir" "$APP_ID"
  finalize_as_armsx3 "$PREFIX"
  masi_refresh_desktop_and_icons "${PREFIX}/share"

  masi_log "Removing source/build tree..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:   ${PREFIX}/bin/${BIN_NAME}"
  masi_log "Data:     ${PREFIX}/share/rpcs3 (upstream layout)"
  masi_log "Desktop:  ${PREFIX}/share/applications/${BIN_NAME}.desktop"
  masi_log "Manifest: ${MASI_MANIFESTS}/${APP_ID}.txt"
  masi_log "Run: ${BIN_NAME}"
  masi_log "Note: config may share ~/.config/rpcs3 with official RPCS3."
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
