#!/usr/bin/env bash
# Build zenithblue-oss/shadps4-arm64 (Bachata ARM64 core + embedded FEXCore)
# and install the binary under ~/shadps4/<version>/shadps4 for QtLauncher
# Version Manager → Add Custom.
#
# This fork has NO Qt GUI. Pair with scripts/shadps4-qtlauncher.sh.
# No Tegra/L4T -mcpu=native. Ubuntu Mesa is never installed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="shadps4"
APP_NAME="ShadPS4 (ARM64)"
REPO_URL="https://github.com/zenithblue-oss/shadps4-arm64.git"
BIN_NAME="shadps4"
INSTALL_ROOT="${MASI_SHADPS4_HOME:-$HOME/shadps4}"

BUILD_DEPS=(
  git cmake ninja-build pkg-config clang lld llvm ca-certificates
  nodejs
  libasound2-dev libpulse-dev libopenal-dev libssl-dev zlib1g-dev
  libedit-dev libudev-dev libevdev-dev libjack-dev libsndio-dev
  libpng-dev libvulkan-dev vulkan-validationlayers
  libx11-dev libxext-dev libxi-dev libxrandr-dev libxcursor-dev
  uuid-dev libdbus-1-dev
  libsdl3-dev
)

GTK_DEPS=(libgtk-3-dev)

current_install_dir() {
  local manifest="${MASI_MANIFESTS}/${APP_ID}.txt"
  if [[ -f "$manifest" ]]; then
    head -n1 "$manifest" || true
  fi
}

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  local dest
  dest="$(current_install_dir)"
  if [[ -z "$dest" || ! -d "$dest" ]]; then
    masi_die "No MasiScript install record for ${APP_ID} under ${INSTALL_ROOT}"
  fi
  masi_log "Removing ${dest}"
  rm -rf "$dest"
  rm -f "${MASI_MANIFESTS}/${APP_ID}.txt"
  # Drop empty parent if we own it.
  if [[ -d "$INSTALL_ROOT" ]] && [[ -z "$(ls -A "$INSTALL_ROOT" 2>/dev/null || true)" ]]; then
    rmdir "$INSTALL_ROOT" 2>/dev/null || true
  fi
  masi_log "=== ${APP_NAME} removed ==="
  masi_log "Note: QtLauncher under /usr/local is left installed (separate app)."
}

build_fexcore_native() {
  local src_dir="$1"
  local lock_path="${src_dir}/runtime/locks/components.lock.json"
  local fex_source="${src_dir}/runtime/sources/fex"
  local build_dir="${src_dir}/runtime/build/fexcore-smoke-build"
  local patch_path="${src_dir}/runtime/patches/fex-fexcore-only.patch"
  local smoke_source="${src_dir}/runtime/probes/fexcore-smoke.cpp"
  local guest_engine="${src_dir}/src/core/fex/fex_guest_engine.cpp"
  local fex_guest_cpu="${src_dir}/src/core/guest_cpu/fex_guest_cpu.cpp"
  local hle_adapter="${src_dir}/src/core/guest_cpu/hle_call_adapter.cpp"
  local fex_hle_bridge="${src_dir}/src/core/guest_cpu/fex_hle_bridge.cpp"
  local guest_harness="${src_dir}/runtime/probes/fexcore-guest-harness.cpp"

  [[ -f "$lock_path" ]] || masi_die "Missing FEX lock: ${lock_path}"
  [[ -f "$patch_path" ]] || masi_die "Missing FEX patch: ${patch_path}"

  local fex_url fex_rev
  mapfile -t _fex_lock < <(python3 - "$lock_path" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1]))
comp = next((c for c in lock.get("components", []) if c.get("name") == "fex"), None)
if not comp or not comp.get("url") or not comp.get("revision"):
    sys.exit(1)
print(comp["url"])
print(comp["revision"])
PY
  ) || masi_die "Invalid fex entry in components.lock.json"
  ((${#_fex_lock[@]} == 2)) || masi_die "Invalid fex entry in components.lock.json"
  fex_url="${_fex_lock[0]}"
  fex_rev="${_fex_lock[1]}"

  masi_log "Checking out FEX ${fex_rev:0:12}..."
  mkdir -p "$(dirname "$fex_source")"
  rm -rf "$fex_source"
  git clone --filter=blob:none --no-checkout "$fex_url" "$fex_source"
  git -C "$fex_source" fetch --depth 1 origin "$fex_rev"
  git -C "$fex_source" checkout --force "$fex_rev"
  [[ "$(git -C "$fex_source" rev-parse HEAD)" == "$fex_rev" ]] \
    || masi_die "FEX checkout does not match lock revision ${fex_rev}"

  local submods=(
    External/unordered_dense
    External/rpmalloc
    External/xxhash
    External/fmt
    External/range-v3
    Source/Common/cpp-optparse
  )
  git -C "$fex_source" submodule update --init --depth 1 --jobs 8 -- "${submods[@]}"

  # Clean any previous patch application, then apply once.
  git -C "$fex_source" reset --hard HEAD
  git -C "$fex_source" apply --check "$patch_path"
  git -C "$fex_source" apply "$patch_path"

  local llvm_ar llvm_ranlib
  llvm_ar="$(command -v llvm-ar-21 || command -v llvm-ar || true)"
  llvm_ranlib="$(command -v llvm-ranlib-21 || command -v llvm-ranlib || true)"
  [[ -n "$llvm_ar" && -n "$llvm_ranlib" ]] || masi_die "llvm-ar / llvm-ranlib required"

  masi_log "Configuring FEXCore (native aarch64, FEXCore-only, bundled fmt)..."
  rm -rf "$build_dir"
  mkdir -p "$build_dir"
  # /usr/local ships a newer/broken fmt (LLVM bitcode lib + headers) that FEX
  # find_package() would pick up and then fail on fmt::join(std::byte...).
  # Clear CMAKE_PREFIX_PATH for this configure so /usr/local is not preferred.
  env -u CMAKE_PREFIX_PATH cmake -S "$fex_source" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_AR="$llvm_ar" \
    -DCMAKE_RANLIB="$llvm_ranlib" \
    -DCMAKE_IGNORE_PREFIX_PATH="/usr/local" \
    -DCMAKE_DISABLE_FIND_PACKAGE_fmt=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_xxhash=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_range-v3=ON \
    -DTUNE_CPU=none \
    -DBUILD_FEXCORE_ONLY=ON \
    -DFEXCORE_PROJECT_SOURCE_DIR="${src_dir}/src" \
    -DFEXCORE_SMOKE_SOURCE="$smoke_source" \
    -DFEXCORE_GUEST_HARNESS_SOURCES="${guest_engine};${fex_guest_cpu};${hle_adapter};${fex_hle_bridge};${guest_harness}" \
    -DBUILD_TESTING=OFF \
    -DBUILD_FEX_LINUX_TESTS=OFF \
    -DBUILD_THUNKS=OFF \
    -DBUILD_FEXCONFIG=OFF \
    -DENABLE_GDB_SYMBOLS=OFF \
    -DENABLE_LTO=OFF \
    -DENABLE_JEMALLOC_GLIBC_ALLOC=OFF \
    -DENABLE_OFFLINE_TELEMETRY=OFF \
    -DENABLE_VIXL_DISASSEMBLER=OFF \
    -DENABLE_VIXL_SIMULATOR=OFF \
    -DENABLE_ZYDIS=OFF \
    -DENABLE_FEXCORE_PROFILER=OFF

  masi_log "Building FEXCore (fexcore-smoke + fexcore-guest-harness)..."
  # Match Bachata upstream: these targets pull in the static libs we need.
  ninja -C "$build_dir" -t clean fexcore-guest-harness >/dev/null 2>&1 || true
  cmake --build "$build_dir" --parallel "$(masi_nproc)" \
    --target fexcore-smoke fexcore-guest-harness

  local need_lib
  for need_lib in \
    "${build_dir}/FEXCore/Source/libFEXCore.a" \
    "${build_dir}/Source/Common/libCommon.a"; do
    [[ -f "$need_lib" ]] || masi_die "FEXCore build missing ${need_lib}"
  done
}

apply_sdl_x11_patch() {
  local src_dir="$1"
  local sdl_dir="${src_dir}/externals/sdl3"
  local patch="${src_dir}/runtime/patches/sdl3-embedded-x11.patch"
  [[ -d "$sdl_dir/.git" || -d "$sdl_dir" ]] || return 0
  [[ -f "$patch" ]] || return 0
  if git -C "$sdl_dir" apply --check "$patch" 2>/dev/null; then
    masi_log "Applying SDL3 embedded-X11 patch..."
    git -C "$sdl_dir" apply "$patch"
  elif git -C "$sdl_dir" apply --reverse --check "$patch" 2>/dev/null; then
    masi_log "SDL3 embedded-X11 patch already applied."
  else
    masi_log "WARNING: SDL3 embedded-X11 patch did not apply cleanly; continuing."
  fi
}

# bachata_audio_out.cpp and videoout/driver.cpp always reference Platform::Bachata
# symbols, but upstream only compiles those .cpp files when ENABLE_BACHATA_RUNTIME=ON.
# Enabling that flag forces Bachata socket audio (Android host) instead of SDL/OpenAL.
# For Linux desktop: always link the platform helpers, keep the define OFF.
patch_bachata_platform_link() {
  local src_dir="$1"
  local cmake_file="${src_dir}/CMakeLists.txt"
  [[ -f "$cmake_file" ]] || masi_die "Missing ${cmake_file}"

  if grep -q 'MasiScript: always link Bachata platform helpers' "$cmake_file"; then
    masi_log "Bachata platform link patch already applied."
    return 0
  fi

  python3 - "$cmake_file" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = """if (ENABLE_BACHATA_RUNTIME)
 target_compile_definitions(shadps4 PRIVATE ENABLE_BACHATA_RUNTIME)
 target_sources(shadps4 PRIVATE
 src/platform/bachata/runtime_client.cpp
 src/platform/bachata/controller_snapshot.cpp
 src/platform/bachata/audio_transport.cpp
 src/platform/bachata/runtime_client.h
 )
endif()"""
# Tolerate irregular indentation from the fetched file.
import re
pat = re.compile(
    r"if\s*\(\s*ENABLE_BACHATA_RUNTIME\s*\)\s*\n"
    r"[^\n]*target_compile_definitions\(shadps4 PRIVATE ENABLE_BACHATA_RUNTIME\)\s*\n"
    r"[^\n]*target_sources\(shadps4 PRIVATE\s*\n"
    r"[^\n]*src/platform/bachata/runtime_client\.cpp\s*\n"
    r"[^\n]*src/platform/bachata/controller_snapshot\.cpp\s*\n"
    r"[^\n]*src/platform/bachata/audio_transport\.cpp\s*\n"
    r"[^\n]*src/platform/bachata/runtime_client\.h\s*\n"
    r"[^\n]*\)\s*\n"
    r"endif\(\)",
    re.MULTILINE,
)
new = """# MasiScript: always link Bachata platform helpers
# (ReportPresentedFrame / AudioTransport). Keep ENABLE_BACHATA_RUNTIME OFF on
# Linux desktop so audio uses SDL/OpenAL instead of the Android socket backend.
target_sources(shadps4 PRIVATE
  src/platform/bachata/runtime_client.cpp
  src/platform/bachata/controller_snapshot.cpp
  src/platform/bachata/audio_transport.cpp
  src/platform/bachata/runtime_client.h
)
if (ENABLE_BACHATA_RUNTIME)
  target_compile_definitions(shadps4 PRIVATE ENABLE_BACHATA_RUNTIME)
endif()"""
m, n = pat.subn(new, text, count=1)
if n != 1:
    sys.stderr.write("Could not patch ENABLE_BACHATA_RUNTIME target_sources block\\n")
    sys.exit(1)
path.write_text(m)
PY
  masi_log "Patched CMakeLists.txt to always link Bachata platform helpers (runtime define still OFF)."
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} (zenithblue + FEXCore → ${INSTALL_ROOT}/<ver>/) ==="
  masi_log "Ubuntu Mesa will not be installed (vendor Adreno/Turnip Mesa)."

  if [[ ! -f /usr/include/EGL/egl.h ]]; then
    masi_die "Missing EGL headers (/usr/include/EGL/egl.h). Use your vendor Mesa SDK, not Ubuntu Mesa."
  fi

  masi_ensure_sudo
  masi_ensure_mesa_dev_stubs
  masi_apt_install "${BUILD_DEPS[@]}" "${GTK_DEPS[@]}"

  command -v clang >/dev/null 2>&1 || masi_die "clang is required"
  command -v clang++ >/dev/null 2>&1 || masi_die "clang++ is required"
  command -v node >/dev/null 2>&1 || masi_die "nodejs is required (FEX lock tooling)"
  command -v python3 >/dev/null 2>&1 || masi_die "python3 is required"

  masi_prepare_build "$APP_ID"
  local src_dir="${MASI_WORK}/src"
  local build_dir="${src_dir}/runtime/build/shadps4-arm64"
  local host_tools="${src_dir}/runtime/build/host-tools"
  local font_embed="${host_tools}/Dear_ImGui_FontEmbed"
  local font_src="${src_dir}/externals/dear_imgui/misc/fonts/binary_to_compressed_c.cpp"
  local fex_build="${src_dir}/runtime/build/fexcore-smoke-build"
  local fex_source="${src_dir}/runtime/sources/fex"

  masi_log "Cloning ${REPO_URL} (with submodules; large)..."
  git clone --depth 1 "$REPO_URL" "$src_dir"
  git -C "$src_dir" submodule update --init --recursive --depth 1 \
    || git -C "$src_dir" submodule update --init --recursive

  local short_rev version_id dest_dir binary
  short_rev="$(git -C "$src_dir" rev-parse --short HEAD)"
  version_id="arm64-${short_rev}"
  dest_dir="${INSTALL_ROOT}/${version_id}"

  apply_sdl_x11_patch "$src_dir"
  patch_bachata_platform_link "$src_dir"
  build_fexcore_native "$src_dir"

  mkdir -p "$host_tools" "$build_dir"
  [[ -f "$font_src" ]] || masi_die "Missing Dear ImGui font embed source: ${font_src}"
  masi_log "Building host Dear_ImGui_FontEmbed..."
  clang++ -std=c++23 -O2 "$font_src" -o "$font_embed"
  chmod +x "$font_embed"

  local llvm_ar llvm_ranlib
  llvm_ar="$(command -v llvm-ar-21 || command -v llvm-ar)"
  llvm_ranlib="$(command -v llvm-ranlib-21 || command -v llvm-ranlib)"

  masi_log "Configuring shadPS4 ARM64 (FEX guest CPU ON, Bachata Android runtime OFF)..."
  env -u CMAKE_PREFIX_PATH cmake -S "$src_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_AR="$llvm_ar" \
    -DCMAKE_RANLIB="$llvm_ranlib" \
    -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
    -DCMAKE_IGNORE_PREFIX_PATH="/usr/local" \
    -DCMAKE_DISABLE_FIND_PACKAGE_fmt=ON \
    -DIMGUI_FONT_EMBED_EXECUTABLE="$font_embed" \
    -DENABLE_BACHATA_RUNTIME=OFF \
    -DENABLE_FEX_GUEST_CPU=ON \
    -DFEXCORE_GUEST_CPU_SOURCE_DIR="$fex_source" \
    -DFEXCORE_GUEST_CPU_BUILD_DIR="$fex_build" \
    -DENABLE_USERFAULTFD=OFF \
    -DENABLE_DISCORD_RPC=OFF \
    -DENABLE_UPDATER=OFF \
    -DENABLE_TESTS=OFF

  masi_log "Compiling ${BIN_NAME} with $(masi_nproc) jobs..."
  cmake --build "$build_dir" --parallel "$(masi_nproc)" --target shadps4

  binary="${build_dir}/${BIN_NAME}"
  [[ -x "$binary" ]] || binary="$(find "$build_dir" -type f -name "$BIN_NAME" -executable | head -n1 || true)"
  [[ -n "$binary" && -x "$binary" ]] || masi_die "Built binary ${BIN_NAME} not found under ${build_dir}"

  file "$binary" | grep -qi 'aarch64\|ARM aarch64' \
    || masi_die "Expected an aarch64 binary, got: $(file "$binary")"

  # Replace previous MasiScript install of this app (one active version).
  local prev
  prev="$(current_install_dir)"
  if [[ -n "$prev" && -d "$prev" && "$prev" != "$dest_dir" ]]; then
    masi_log "Removing previous install: ${prev}"
    rm -rf "$prev"
  fi

  masi_log "Installing to ${dest_dir}/"
  mkdir -p "$dest_dir"
  install -m755 "$binary" "${dest_dir}/${BIN_NAME}"
  cat >"${dest_dir}/README.txt" <<EOF
ShadPS4 ARM64 core (zenithblue-oss/shadps4-arm64)
Version: ${version_id}
Commit:  $(git -C "$src_dir" rev-parse HEAD)
Built:   $(date -u +%Y-%m-%dT%H:%M:%SZ)

This folder is for QtLauncher manual import:
  1. Open shadPS4 QtLauncher
  2. Version Manager → Add Custom
  3. Select: ${dest_dir}/${BIN_NAME}

Official downloadable x86_64 builds from the launcher will NOT work on aarch64.
EOF
  printf '%s\n' "$dest_dir" >"${MASI_MANIFESTS}/${APP_ID}.txt"
  chmod 644 "${MASI_MANIFESTS}/${APP_ID}.txt" "${dest_dir}/README.txt"

  masi_log "Removing source/build tree..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:  ${dest_dir}/${BIN_NAME}"
  masi_log "README:  ${dest_dir}/README.txt"
  masi_shadps4_core_warning "${dest_dir}/${BIN_NAME}"
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
