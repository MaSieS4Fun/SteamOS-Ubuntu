#!/usr/bin/env bash
# Build / install / uninstall xemu (original Xbox emulator) from source.
#
# https://github.com/xemu-project/xemu
# Upstream Linux flow: recursive clone + ./build.sh → dist/xemu
# (QEMU-based; not a cmake --install project).
#
# Never install Ubuntu Mesa; vendor Adreno/Turnip stays in place.
# Do not pass Tegra/L4T -march=native flags.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="xemu"
APP_NAME="xemu"
REPO_URL="https://github.com/xemu-project/xemu.git"
PREFIX="${MASI_PREFIX:-/usr/local}"

BUILD_DEPS=(
  build-essential clang lld cmake ninja-build pkg-config git ca-certificates
  python3 python3-pip python3-venv python3-yaml
  libepoxy-dev libpixman-1-dev libsdl2-dev libsamplerate0-dev
  zlib1g-dev libssl-dev libpcap-dev libslirp-dev
  libvulkan-dev libusb-1.0-0-dev libcurl4-gnutls-dev
  libpipewire-0.3-dev
  libegl-dev libopengl-dev libgl-dev
  # Debian/Ubuntu glslang is built with ENABLE_OPT; SpvTools needs these.
  glslang-dev spirv-tools-dev
)

# Optional: tomli may be stdlib on 3.11+; try package if present.
OPTIONAL_DEPS=(python3-tomli)

# Debian/Ubuntu glslang.a is built with ENABLE_OPT; Meson's cmake dependency for
# glslang only passes libglslang.a and drops SPIRV-Tools / libSPIRV / etc.
# Also, Meson may emit those -l flags *before* libglslang.a — use --start-group.
patch_meson_glslang_spirv_tools() {
  local meson_build="$1"
  [[ -f "$meson_build" ]] || masi_die "Missing $meson_build"
  python3 - "$meson_build" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "MasiScript: glslang needs SPIRV-Tools"
final_token = "partial_dependency(compile_args: true, includes: true)"
if marker in text and final_token in text and "-Wl,--start-group" in text:
    print("meson.build already patched for glslang/SPIRV-Tools")
    raise SystemExit(0)

replacement = f"""if vulkan.found()
  libglslang = dependency('glslang', version: '>=15.0.0', required: false)
  if libglslang.found()
    # {marker}
    # System glslang (Debian/Ubuntu) ENABLE_OPT pulls SpvTools; cmake dep omits
    # transitive static libs. Keep everything in --start-group so link order
    # does not matter for static archives.
    libglslang = declare_dependency(
      dependencies: [
        libglslang.partial_dependency(compile_args: true, includes: true),
      ],
      link_args: [
        '-Wl,--start-group',
        '-lglslang',
        '-lSPIRV',
        '-lMachineIndependent',
        '-lGenericCodeGen',
        '-lOSDependent',
        '-lSPIRV-Tools-opt',
        '-lSPIRV-Tools',
        '-lSPIRV-Tools-link',
        '-Wl,--end-group',
      ],
    )
  endif
  if not libglslang.found()
"""

patterns = [
    # Prior MasiScript patch (any revision)
    re.compile(
        r"if vulkan\.found\(\)\n"
        r"  libglslang = dependency\('glslang', version: '>=15\.0\.0', required: false\)\n"
        r"  if libglslang\.found\(\)\n"
        r"    # MasiScript: glslang needs SPIRV-Tools\n"
        r".*?"
        r"  endif\n"
        r"  if not libglslang\.found\(\)\n",
        re.S,
    ),
    # Stock upstream
    re.compile(
        r"if vulkan\.found\(\)\n"
        r"  libglslang = dependency\('glslang', version: '>=15\.0\.0', required: false\)\n"
        r"  if not libglslang\.found\(\)\n",
    ),
]

for pat in patterns:
    text2, n = pat.subn(replacement, text, count=1)
    if n:
        path.write_text(text2, encoding="utf-8")
        print(f"patched {path}")
        raise SystemExit(0)

raise SystemExit(f"{path}: glslang dependency block not found")
PY
}

write_manifest() {
  local manifest="${MASI_MANIFESTS}/${APP_ID}.txt"
  mkdir -p "$MASI_MANIFESTS"
  : >"$manifest"
  local f
  for f in "$@"; do
    [[ -n "$f" ]] || continue
    printf '%s\n' "$f" >>"$manifest"
  done
  chmod 644 "$manifest"
  masi_log "Saved install manifest: $manifest"
}

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  if [[ -f "${MASI_MANIFESTS}/${APP_ID}.txt" ]]; then
    masi_uninstall_from_manifest "$APP_ID"
  else
    masi_ensure_sudo
    masi_sudo rm -f "${PREFIX}/bin/xemu" \
      "${PREFIX}/share/applications/xemu.desktop" \
      "${PREFIX}/share/icons/hicolor/256x256/apps/xemu.png"
  fi
  masi_refresh_desktop_and_icons "${PREFIX}/share"
  masi_log "=== ${APP_NAME} removed ==="
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} (./build.sh → ${PREFIX}) ==="
  masi_log "Install prefix: ${PREFIX}"
  masi_log "Ubuntu Mesa will not be installed (vendor Adreno/Turnip Mesa)."

  if [[ ! -f /usr/include/EGL/egl.h ]]; then
    masi_die "Missing EGL headers (/usr/include/EGL/egl.h). Use your vendor Mesa SDK, not Ubuntu Mesa."
  fi

  masi_ensure_sudo
  masi_ensure_mesa_dev_stubs
  masi_apt_install "${BUILD_DEPS[@]}"
  masi_apt_install "${OPTIONAL_DEPS[@]}" || true

  masi_prepare_build "$APP_ID"
  local src_dir="${MASI_WORK}/src"

  masi_log "Cloning ${REPO_URL} (recursive submodules — large)..."
  git clone --depth 1 --recursive "$REPO_URL" "$src_dir" \
    || {
      git clone --depth 1 "$REPO_URL" "$src_dir"
      git -C "$src_dir" submodule update --init --recursive --depth 1 \
        || git -C "$src_dir" submodule update --init --recursive
    }

  [[ -x "${src_dir}/build.sh" ]] || masi_die "Missing ${src_dir}/build.sh"

  masi_log "Patching meson.build for Debian glslang + SPIRV-Tools link..."
  patch_meson_glslang_spirv_tools "${src_dir}/meson.build"

  masi_log "Running upstream build.sh (this takes a long time)..."
  (
    cd "$src_dir"
    # Prefer system clang when available; avoid injecting Tegra CPU flags.
    export CC="${CC:-clang}"
    export CXX="${CXX:-clang++}"
    # Drop stale configure if glslang was linked without our -lglslang start-group.
    if [[ -f build/build.ninja ]] && ! grep -q -- '-lglslang' build/build.ninja; then
      masi_log "Reconfiguring (glslang/SPIRV-Tools start-group link missing)..."
      rm -rf build
    fi
    ./build.sh -j"$(masi_nproc)"
  )

  local binary="${src_dir}/dist/xemu"
  [[ -x "$binary" ]] || binary="${src_dir}/build/qemu-system-i386"
  [[ -x "$binary" ]] || masi_die "xemu binary not found (expected dist/xemu)"

  masi_ensure_sudo
  masi_log "Installing ${binary} → ${PREFIX}/bin/xemu"
  masi_sudo install -Dm755 "$binary" "${PREFIX}/bin/xemu"

  local desktop_src="${src_dir}/ui/xemu.desktop"
  local desktop_dst="${PREFIX}/share/applications/xemu.desktop"
  local icon_src="${src_dir}/ui/icons/xemu_256x256.png"
  local icon_dst="${PREFIX}/share/icons/hicolor/256x256/apps/xemu.png"

  masi_sudo mkdir -p "$(dirname "$desktop_dst")" "$(dirname "$icon_dst")"
  if [[ -f "$desktop_src" ]]; then
    masi_sudo sed "s|^Exec=.*|Exec=${PREFIX}/bin/xemu|" "$desktop_src" \
      | masi_sudo tee "$desktop_dst" >/dev/null
  else
    masi_sudo tee "$desktop_dst" >/dev/null <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Exec=${PREFIX}/bin/xemu
Name=xemu
Comment=Emulator for the original Xbox console
Icon=xemu
Categories=Game;Emulator;
Keywords=original;xbox;game;console;emulator;xemu;
EOF
  fi
  if [[ -f "$icon_src" ]]; then
    masi_sudo cp -a "$icon_src" "$icon_dst"
  fi

  write_manifest \
    "${PREFIX}/bin/xemu" \
    "$desktop_dst" \
    "$icon_dst"

  masi_refresh_desktop_and_icons "${PREFIX}/share"

  masi_log "Removing source/build tree..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:   ${PREFIX}/bin/xemu"
  masi_log "Desktop:  ${desktop_dst}"
  masi_log "Manifest: ${MASI_MANIFESTS}/${APP_ID}.txt"
  masi_log "Run: xemu"
  cat <<EOF

[EmuKitARM] WARNING — xemu
- Needs an original Xbox MCPX / ROM dump and HDD image (see https://xemu.app).
- Those files are not provided by MasiScript.

EOF
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
