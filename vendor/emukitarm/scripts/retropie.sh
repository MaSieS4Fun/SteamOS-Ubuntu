#!/usr/bin/env bash
# Install / uninstall RetroPie (basic: core + main) with EmulationStation.
#
# Based on https://retropie.org.uk/docs/Debian/
#
# This image reports lsb_release ID "SteamOS-Ubuntu" (ID=steamos-ubuntu) while
# still being Ubuntu 26.04 Resolute. Upstream RetroPie treats that as
# "Unsupported OS". We patch detection to map it like Ubuntu.
#
# On aarch64, RetroPie falls back to platform_native (-march=native), which is
# unsafe on sm8550. We inject platform_sm8550 (armv8.2-a, X11 + GLES + Vulkan).
#
# EmulationStation's default build probes glxinfo (desktop GL). Adreno/Turnip
# prefers GLES — we force -DGLES=On and skip the fragile glxinfo path.
#
# Never install Ubuntu Mesa; vendor Adreno/Turnip stays in place.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="retropie"
APP_NAME="RetroPie"
REPO_URL="https://github.com/RetroPie/RetroPie-Setup.git"
SETUP_DIR="${MASI_RETROPIE_SETUP:-$HOME/RetroPie-Setup}"
ROOTDIR="/opt/retropie"
DATADIR="${HOME}/RetroPie"
DESKTOP_PATH="${MASI_DESKTOP}/retropie-emulationstation.desktop"
LAUNCHER_PATH="${MASI_BIN}/emulationstation"

BUILD_DEPS=(
  git dialog unzip xmlstarlet curl ca-certificates
  build-essential cmake pkg-config
  libsdl2-dev libasound2-dev libavcodec-dev libavformat-dev libavdevice-dev
  libfreeimage-dev libfreetype6-dev libcurl4-openssl-dev libsm-dev
  libvlc-dev libvlccore-dev rapidjson-dev python3-sdl2 vlc
  libudev-dev libxkbcommon-dev libusb-1.0-0-dev libx11-xcb-dev libpulse-dev
  libvulkan-dev
)

OPTIONAL_DEPS=(gnome-terminal mesa-utils)

rp_sudo() {
  # Run RetroPie packages as root with forced platform + real user identity.
  # CMAKE_POLICY_VERSION_MINIMUM: Ubuntu 26.04 ships CMake 4.x which rejects
  # cmake_minimum_required < 3.5 (EmulationStation, pugixml, many cores).
  masi_sudo env \
    __nodialog=1 \
    __platform=sm8550 \
    __user="$(id -un)" \
    __group="$(id -gn)" \
    CMAKE_POLICY_VERSION_MINIMUM=3.5 \
    "$@"
}

write_desktop_entry() {
  local es_bin="${ROOTDIR}/supplementary/emulationstation/emulationstation"
  mkdir -p "$MASI_DESKTOP" "$MASI_BIN"
  cat >"$DESKTOP_PATH" <<EOF
[Desktop Entry]
Type=Application
Name=RetroPie EmulationStation
Comment=RetroPie frontend (EmulationStation)
Exec=${es_bin}
Icon=applications-games
Terminal=false
Categories=Game;Emulator;
StartupNotify=true
EOF
  chmod 644 "$DESKTOP_PATH"
  rm -f "$LAUNCHER_PATH"
  cat >"$LAUNCHER_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "${es_bin}" "\$@"
EOF
  chmod +x "$LAUNCHER_PATH"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$MASI_DESKTOP" >/dev/null 2>&1 || true
  fi
}

save_manifest() {
  mkdir -p "$MASI_MANIFESTS"
  cat >"${MASI_MANIFESTS}/${APP_ID}.txt" <<EOF
${SETUP_DIR}
${ROOTDIR}
${DESKTOP_PATH}
${LAUNCHER_PATH}
EOF
  chmod 644 "${MASI_MANIFESTS}/${APP_ID}.txt"
}

patch_retropie_for_sm8550() {
  local setup="$1"
  local system_sh="${setup}/scriptmodules/system.sh"
  local es_sh="${setup}/scriptmodules/supplementary/emulationstation.sh"
  local ra_sh="${setup}/scriptmodules/emulators/retroarch.sh"

  [[ -f "$system_sh" ]] || masi_die "Missing ${system_sh}"
  [[ -f "$es_sh" ]] || masi_die "Missing ${es_sh}"

  masi_log "Patching RetroPie OS detection (SteamOS-Ubuntu → Ubuntu)..."
  python3 - "$system_sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = "MasiScript: SteamOS-Ubuntu is Ubuntu 26.04 Resolute"
if marker in text:
    print("OS patch already present", file=sys.stderr)
    raise SystemExit(0)

needle = (
    "        Ubuntu|[Nn]eon|Pop)\n"
    "            if compareVersions \"$__os_release\" lt 16.04; then\n"
    "                error=\"You need Ubuntu 16.04 or newer\""
)
insert = (
    "        # MasiScript: SteamOS-Ubuntu is Ubuntu 26.04 Resolute\n"
    "        SteamOS-Ubuntu|steamos-ubuntu)\n"
    "            if compareVersions \"$__os_release\" lt 16.04; then\n"
    "                error=\"You need Ubuntu 16.04 or newer\"\n"
    "            elif compareVersions \"$__os_release\" le 16.10; then\n"
    "                __os_debian_ver=\"8\"\n"
    "            elif compareVersions \"$__os_release\" lt 18.04; then\n"
    "                __os_debian_ver=\"9\"\n"
    "            elif compareVersions \"$__os_release\" lt 20.04; then\n"
    "                __os_debian_ver=\"10\"\n"
    "            elif compareVersions \"$__os_release\" lt 22.10; then\n"
    "                __os_debian_ver=\"11\"\n"
    "            else\n"
    "                __os_debian_ver=\"12\"\n"
    "            fi\n"
    "            __os_ubuntu_ver=\"$__os_release\"\n"
    "            ;;\n"
    + needle
)
if needle not in text:
    sys.stderr.write("Could not find Ubuntu OS case in system.sh\n")
    sys.exit(1)
path.write_text(text.replace(needle, insert, 1))
print("OS detection patched", file=sys.stderr)
PY

  masi_log "Injecting platform_sm8550 (no -march=native)..."
  python3 - "$system_sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
if "function platform_sm8550()" in text:
    print("platform_sm8550 already present", file=sys.stderr)
    raise SystemExit(0)

fn = """
function platform_sm8550() {
    # Snapdragon 8 Gen 2 (sm8550) — Eden-like tune, never -march=native.
    __default_cpu_flags="-march=armv8.2-a+lse+rcpc"
    __platform_flags+=(aarch64 x11 gles gles3 vulkan)
}

"""
marker = "function platform_native() {"
if marker not in text:
    sys.stderr.write("platform_native not found\n")
    sys.exit(1)
path.write_text(text.replace(marker, fn + marker, 1))
print("platform_sm8550 injected", file=sys.stderr)
PY

  masi_log "Patching EmulationStation build (GLES + CMake 4)..."
  python3 - "$es_sh" <<'PY'
from pathlib import Path
import sys
import re

path = Path(sys.argv[1])
text = path.read_text()
if "MasiScript: CMake4 + GLES" in text:
    print("ES build patch already present", file=sys.stderr)
    raise SystemExit(0)

text = text.replace(
    'isPlatform "x11" && depends+=(gnome-terminal mesa-utils)',
    '# MasiScript: mesa-utils/gnome-terminal optional on vendor Mesa handhelds\n'
    '    # isPlatform "x11" && depends+=(gnome-terminal mesa-utils)',
    1,
)

pat = re.compile(r"function build_emulationstation\(\) \{.*?\n\}", re.DOTALL)
new = '''function build_emulationstation() {
    # MasiScript: CMake4 + GLES — Adreno GLES; bump ancient cmake_minimum_required.
    local params=(
        -DFREETYPE_INCLUDE_DIRS=/usr/include/freetype2/
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    )
    if isPlatform "rpi"; then
        params+=(-DRPI=On)
        isPlatform "mesa" && params+=("-DGL=On" "-DUSE_GL21=On")
        isPlatform "videocore" && params+=(-DUSE_GLES1=On)
    elif isPlatform "gles" || isPlatform "aarch64"; then
        params+=(-DGLES=On)
    elif isPlatform "x11"; then
        if isPlatform "gles"; then
            params+=(-DGLES=On)
        else
            params+=(-DGL=On -DUSE_GL21=On)
        fi
    elif isPlatform "gl"; then
        params+=(-DGL=On)
    else
        params+=(-DGLES=On)
    fi
    if isPlatform "dispmanx"; then
        params+=(-DOMX=On)
    fi

    # CMake 4.x removed support for cmake_minimum_required < 3.5 (ES + pugixml).
    find . -name CMakeLists.txt -print0 | xargs -0 sed -i \
        -e 's/cmake_minimum_required([[:space:]]*VERSION[[:space:]]*2\\.[0-9][^)]*)/cmake_minimum_required(VERSION 3.5)/g' \
        -e 's/cmake_minimum_required([[:space:]]*VERSION[[:space:]]*3\\.[0-4][^)]*)/cmake_minimum_required(VERSION 3.5)/g' \
        || true

    rpSwap on 1000
    cmake . "${params[@]}"
    make clean
    make VERBOSE=1
    rpSwap off
    md_ret_require="$md_build/emulationstation"
}'''
m, n = pat.subn(new, text, count=1)
if n != 1:
    sys.stderr.write("Could not replace build_emulationstation()\n")
    sys.exit(1)
path.write_text(m)
print("EmulationStation build patched (CMake4 + GLES)", file=sys.stderr)
PY

  if [[ -f "$ra_sh" ]] && ! grep -q 'MasiScript: skip mesa-vulkan-drivers' "$ra_sh"; then
    masi_log "Softening RetroArch mesa-vulkan-drivers dependency..."
    sed -i \
      's/isPlatform "vulkan" && depends+=(libvulkan-dev mesa-vulkan-drivers)/# MasiScript: skip mesa-vulkan-drivers (vendor Turnip)\n    isPlatform "vulkan" \&\& depends+=(libvulkan-dev)/' \
      "$ra_sh"
  fi
}

stop_retropie_helpers() {
  # RetroPie starts joy2key for dialog navigation; it can outlive the installer
  # and keep MasiScript's stdout pipe open (GUI stuck on "success").
  local j2k="${ROOTDIR}/admin/joy2key/joy2key"
  if [[ -x "$j2k" ]]; then
    masi_sudo "$j2k" stop >/dev/null 2>&1 || true
  fi
  masi_sudo pkill -f 'joy2key_sdl\.py' >/dev/null 2>&1 || true
  masi_sudo pkill -f '/opt/retropie/admin/joy2key/' >/dev/null 2>&1 || true
}

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  stop_retropie_helpers
  if [[ -x "${SETUP_DIR}/retropie_packages.sh" ]]; then
    masi_log "Removing common RetroPie modules..."
    for mod in emulationstation retroarch runcommand retropiemenu; do
      rp_sudo bash "${SETUP_DIR}/retropie_packages.sh" "$mod" remove || true
    done
  fi
  masi_ensure_sudo
  if [[ -d "$ROOTDIR" ]]; then
    masi_log "Removing ${ROOTDIR}"
    masi_sudo rm -rf "$ROOTDIR"
  fi
  rm -f "$DESKTOP_PATH" "$LAUNCHER_PATH"
  rm -f "${MASI_MANIFESTS}/${APP_ID}.txt"
  # Keep ~/RetroPie-Setup — needed to add cores / reconfigure later.
  # Keep ~/RetroPie (ROMs/BIOS) — user data.
  masi_log "Left setup tree in place: ${SETUP_DIR}"
  masi_log "Left user data in place: ${DATADIR} (ROMs/BIOS). Delete manually if desired."
  masi_log "=== ${APP_NAME} removed ==="
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} (basic_install: core + main + EmulationStation) ==="
  masi_log "Setup tree: ${SETUP_DIR}"
  masi_log "Install root: ${ROOTDIR}"
  masi_log "Data (ROMs):  ${DATADIR}"
  masi_log "OS ID from lsb_release: $(lsb_release -si 2>/dev/null || echo unknown) — mapped as Ubuntu."
  masi_log "Platform forced: sm8550 (armv8.2-a, no -march=native)."
  masi_log "Ubuntu Mesa will not be installed (vendor Adreno/Turnip Mesa)."

  masi_ensure_sudo
  masi_ensure_mesa_dev_stubs
  masi_apt_install "${BUILD_DEPS[@]}"
  masi_apt_install "${OPTIONAL_DEPS[@]}" || true

  if [[ ! -d "${SETUP_DIR}/.git" ]]; then
    masi_log "Cloning ${REPO_URL} → ${SETUP_DIR}"
    rm -rf "$SETUP_DIR"
    git clone --depth 1 "$REPO_URL" "$SETUP_DIR"
  else
    masi_log "Updating existing ${SETUP_DIR}"
    git -C "$SETUP_DIR" fetch --depth 1 origin master \
      || git -C "$SETUP_DIR" fetch --depth 1 origin main \
      || true
    git -C "$SETUP_DIR" reset --hard FETCH_HEAD \
      || git -C "$SETUP_DIR" pull --ff-only \
      || true
  fi

  patch_retropie_for_sm8550 "$SETUP_DIR"
  masi_sudo chown -R "$(id -un):$(id -gn)" "$SETUP_DIR"

  masi_log "Running RetroPie basic_install (core + main). This takes a long time..."
  if ! rp_sudo bash "${SETUP_DIR}/retropie_packages.sh" setup basic_install; then
    masi_log "basic_install reported errors — retrying EmulationStation alone..."
    # Drop stale CMake cache from the failed CMake-4 attempt.
    rp_sudo bash "${SETUP_DIR}/retropie_packages.sh" emulationstation clean || true
    masi_sudo rm -rf "${SETUP_DIR}/tmp/build/emulationstation" || true
    rp_sudo bash "${SETUP_DIR}/retropie_packages.sh" emulationstation \
      || masi_die "EmulationStation install failed. See ${SETUP_DIR}/logs"
  fi

  local es_bin="${ROOTDIR}/supplementary/emulationstation/emulationstation"
  [[ -x "$es_bin" ]] || masi_die "EmulationStation binary missing at ${es_bin}"

  write_desktop_entry
  save_manifest
  stop_retropie_helpers

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "EmulationStation: ${es_bin}"
  masi_log "Command:          emulationstation"
  masi_log "Desktop:          ${DESKTOP_PATH}"
  masi_log "ROMs/BIOS:        ${DATADIR}"
  masi_log "Setup tree kept:  ${SETUP_DIR}"
  masi_log "Re-run setup UI:  cd ${SETUP_DIR} && sudo ./retropie_setup.sh"
  cat <<EOF

[EmuKitARM] WARNING — RetroPie / EmulationStation
- OS was treated as Ubuntu 26.04 (SteamOS-Ubuntu ID is branding only).
- Builds use platform sm8550 (no -march=native).
- Put ROMs under ~/RetroPie/roms/<system>/ and BIOS under ~/RetroPie/BIOS/
- Setup tree ~/RetroPie-Setup is kept (not a disposable build folder).
- Use RetroPie Setup later to add more cores: cd ~/RetroPie-Setup && sudo ./retropie_setup.sh

EOF
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
