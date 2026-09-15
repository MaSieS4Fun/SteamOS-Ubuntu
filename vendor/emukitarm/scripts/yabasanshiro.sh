#!/usr/bin/env bash
# Build / install / uninstall YabaSanshiro (SEGA Saturn) from official GPL source.
#
# https://www.yabasanshiro.com/download
#
# The GitHub repo (devmiyax/yabause) is no longer publicly cloneable (Git asks
# for credentials / ksshaskpass). Use the GPL tarball hosted on CloudFront
# instead — same tree the site offers as "Source Code (GPL)".
#
# Desktop Qt6 port + SH2 dynarec. The GPL tarball omits:
#   - firebase-cpp-sdk (and the real v6.11.0 SDK breaks on CMake 4) → no-op stub
#   - rcheevos git submodule under src/retroachievements/ → fetch from GitHub
# Never install Ubuntu Mesa; vendor Adreno/Turnip stays in place.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="yabasanshiro"
APP_NAME="YabaSanshiro"
# Override with MASI_YABA_SRC_URL if the site bumps the version.
SOURCE_URL_DEFAULT="https://d1t36rsydvwkyk.cloudfront.net/yabasanshiro-src-1.20.46.tar.gz"
# GPL tarball leaves src/retroachievements/rcheevos empty (submodule).
RCHEEVOS_URL_DEFAULT="https://github.com/RetroAchievements/rcheevos/archive/refs/heads/master.tar.gz"
PREFIX="${MASI_PREFIX:-/usr/local}"

BUILD_DEPS=(
  build-essential cmake ninja-build pkg-config ca-certificates curl
  libsdl2-dev libopenal-dev zlib1g-dev libcurl4-openssl-dev libicu-dev
  libboost-dev libboost-system-dev libboost-filesystem-dev
  libboost-date-time-dev libboost-locale-dev
  qt6-base-dev qt6-base-private-dev qt6-multimedia-dev
  libegl-dev libopengl-dev libgl-dev
  libglew-dev freeglut3-dev
  libprotobuf-dev protobuf-compiler libsecret-1-dev libssl-dev
)

resolve_source_url() {
  if [[ -n "${MASI_YABA_SRC_URL:-}" ]]; then
    printf '%s\n' "$MASI_YABA_SRC_URL"
    return 0
  fi
  printf '%s\n' "$SOURCE_URL_DEFAULT"
}

fetch_official_source() {
  local dest_dir="$1"
  local url tarball top
  url="$(resolve_source_url)"
  tarball="${MASI_WORK}/yabasanshiro-src.tar.gz"

  masi_log "Downloading official GPL source (no private GitHub)..."
  masi_log "URL: ${url}"
  # CloudFront expects a normal browser-like request from the download page.
  curl -fL --connect-timeout 30 --max-time 1800 --retry 3 --retry-delay 2 \
    -A 'Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36' \
    -H 'Referer: https://www.yabasanshiro.com/download' \
    -H 'Accept: */*' \
    -o "$tarball" "$url" \
    || masi_die "Failed to download YabaSanshiro source. Set MASI_YABA_SRC_URL to the current .tar.gz from https://www.yabasanshiro.com/download"

  mkdir -p "$dest_dir"
  tar -xzf "$tarball" -C "$dest_dir"
  rm -f "$tarball"

  # Tarball root is yabasanshiro-<ver>/; flatten one level if needed.
  top="$(find "$dest_dir" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"
  if [[ -n "$top" && ! -f "${dest_dir}/yabause/CMakeLists.txt" && -f "${top}/yabause/CMakeLists.txt" ]]; then
    shopt -s dotglob
    mv "$top"/* "$dest_dir"/
    shopt -u dotglob
    rmdir "$top" 2>/dev/null || rm -rf "$top"
  fi

  [[ -f "${dest_dir}/yabause/CMakeLists.txt" ]] \
    || masi_die "Extracted source has no yabause/CMakeLists.txt"
}

# GPL tarball ships retroachievements/CMakeLists.txt but leaves the rcheevos
# submodule empty, so CMake fails looking for rcheevos/src/rc_client.c.
fetch_rcheevos() {
  local src_root="$1"
  local parent="${src_root}/yabause/src/retroachievements"
  local dest="${parent}/rcheevos"
  local url tarball extract_dir top

  [[ -f "${parent}/CMakeLists.txt" ]] || return 0
  if [[ -f "${dest}/src/rc_client.c" ]]; then
    masi_log "rcheevos already present."
    return 0
  fi

  url="${MASI_RCHEEVOS_URL:-$RCHEEVOS_URL_DEFAULT}"
  tarball="${MASI_WORK}/rcheevos.tar.gz"
  extract_dir="${MASI_WORK}/rcheevos-extract"

  masi_log "Fetching rcheevos (omitted submodule from GPL tarball)..."
  masi_log "URL: ${url}"
  curl -fL --connect-timeout 30 --max-time 600 --retry 3 --retry-delay 2 \
    -o "$tarball" "$url" \
    || masi_die "Failed to download rcheevos. Set MASI_RCHEEVOS_URL or check network."

  rm -rf "$dest" "$extract_dir"
  mkdir -p "$extract_dir" "$parent"
  tar -xzf "$tarball" -C "$extract_dir"
  rm -f "$tarball"

  top="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"
  [[ -n "$top" ]] || masi_die "rcheevos archive had no top-level directory"
  mv "$top" "$dest"
  rm -rf "$extract_dir"

  [[ -f "${dest}/src/rc_client.c" ]] \
    || masi_die "rcheevos extract missing src/rc_client.c"
}

# Upstream Qt CMake always add_subdirectory(firebase-cpp-sdk). Provide a tiny
# stub SDK that satisfies includes/link without building Google's CMake-4-broken
# v6.11 tree. Cloud features no-op.
install_firebase_stubs() {
  local qt_dir="$1"
  local dest="${qt_dir}/firebase-cpp-sdk"
  masi_log "Installing Firebase no-op stub (real SDK broken on CMake 4 / not in GPL tarball)..."
  python3 "${SCRIPT_DIR}/yaba_firebase_stub.py" "$dest"
}


# GPL Qt CMakeLists downloads a Windows ICU zip and links *.lib even on Linux.
# Replace that with system libicu on UNIX.
patch_qt_cmake_for_linux() {
  local qt_cmake="$1"
  [[ -f "$qt_cmake" ]] || masi_die "Missing ${qt_cmake}"
  if grep -q 'MasiScript: system ICU on Linux' "$qt_cmake"; then
    masi_log "Qt CMake Linux ICU patch already present."
    return 0
  fi
  masi_log "Patching Qt CMakeLists for system ICU (skip Windows FetchContent)..."
  python3 - "$qt_cmake" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old_fetch = '''# FetchContentモジュールのインクルード
include(FetchContent)

# ICUのバイナリダウンロードと解凍設定
FetchContent_Declare(
    icu
    URL https://github.com/unicode-org/icu/releases/download/release-76-1/icu4c-76_1-Win64-MSVC2022.zip
    URL_HASH SHA256=bedba77dd1feca09e9ae9922109a285c0ecf46d09c80b65eae6eae63a4e155dc
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE  # タイムスタンプを解凍時のものに設定
)

# ICUの解凍とインクルード設定
FetchContent_GetProperties(icu)
if(NOT icu_POPULATED)
    FetchContent_Populate(icu)
endif()

# ICUのインクルードパスとライブラリパスを設定
set(ICU_INCLUDE_DIR "${icu_SOURCE_DIR}/include")
set(ICU_LIBRARY_DIR "${icu_SOURCE_DIR}/lib64")
set(ICU_BIN_DIR "${icu_SOURCE_DIR}/bin64")
'''

new_fetch = '''# MasiScript: system ICU on Linux; keep Windows FetchContent for Win builds.
if(WIN32)
include(FetchContent)
FetchContent_Declare(
    icu
    URL https://github.com/unicode-org/icu/releases/download/release-76-1/icu4c-76_1-Win64-MSVC2022.zip
    URL_HASH SHA256=bedba77dd1feca09e9ae9922109a285c0ecf46d09c80b65eae6eae63a4e155dc
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_GetProperties(icu)
if(NOT icu_POPULATED)
    FetchContent_Populate(icu)
endif()
set(ICU_INCLUDE_DIR "${icu_SOURCE_DIR}/include")
set(ICU_LIBRARY_DIR "${icu_SOURCE_DIR}/lib64")
set(ICU_BIN_DIR "${icu_SOURCE_DIR}/bin64")
else()
find_package(ICU REQUIRED COMPONENTS uc i18n data)
set(ICU_INCLUDE_DIR ${ICU_INCLUDE_DIRS})
endif()
'''

if old_fetch not in text:
    sys.stderr.write("Could not find ICU FetchContent block to patch\n")
    sys.exit(1)
text = text.replace(old_fetch, new_fetch, 1)

old_link = 'target_link_libraries(yabause-qt ${ICU_LIBRARY_DIR}/icuuc.lib ${ICU_LIBRARY_DIR}/icuin.lib ${ICU_LIBRARY_DIR}/icudt.lib)'
new_link = '''# MasiScript: system ICU on Linux
if(WIN32)
target_link_libraries(yabause-qt ${ICU_LIBRARY_DIR}/icuuc.lib ${ICU_LIBRARY_DIR}/icuin.lib ${ICU_LIBRARY_DIR}/icudt.lib)
else()
include_directories(${ICU_INCLUDE_DIRS})
target_link_libraries(yabause-qt ICU::uc ICU::i18n ICU::data)
endif()'''
if old_link not in text:
    sys.stderr.write("Could not find ICU link line to patch\n")
    sys.exit(1)
text = text.replace(old_link, new_link, 1)

path.write_text(text)
print("Qt CMakeLists patched for Linux ICU", file=sys.stderr)
PY
}

# GPL memory.c defines ww_check only under CACHE_ENABLE, but always calls it.
# Default YAB_WANT_SH2_CACHE=OFF → implicit declaration / GCC 14 error.
patch_memory_ww_check() {
  local memory_c="$1"
  [[ -f "$memory_c" ]] || masi_die "Missing ${memory_c}"
  if grep -q 'MasiScript: ww_check stub' "$memory_c"; then
    masi_log "memory.c ww_check stub already present."
    return 0
  fi
  masi_log "Patching memory.c ww_check stub for CACHE_ENABLE=OFF..."
  python3 - "$memory_c" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="surrogateescape")
old = """#else
void FASTCALL MappedMemoryWriteByte(u32 addr, u8 val, u32 * cycle)
#endif
{
  ww_check(addr, val, 1);"""
new = """#else
/* MasiScript: ww_check stub — function only exists in CACHE_ENABLE path above. */
static void ww_check(u32 addr, u32 val, int size)
{
  (void)addr;
  (void)val;
  (void)size;
}
void FASTCALL MappedMemoryWriteByte(u32 addr, u8 val, u32 * cycle)
#endif
{
  ww_check(addr, val, 1);"""
if old not in text:
    sys.stderr.write("Could not find MappedMemoryWriteByte CACHE_ENABLE else-branch to patch\n")
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8", errors="surrogateescape")
print("memory.c ww_check stub patched", file=sys.stderr)
PY
}

# Broken Linux realtime sync: time(&timespec) / ctime(&tm) instead of clock_gettime
# and pthread_cond_timedwait(..., &tm). Mirror the working ANDROID branch.
patch_scsp_linux_timedwait() {
  local scsp_cpp="$1"
  [[ -f "$scsp_cpp" ]] || masi_die "Missing ${scsp_cpp}"
  if grep -q 'MasiScript: Linux SCSP timedwait' "$scsp_cpp"; then
    masi_log "scsp.cpp Linux timedwait patch already present."
    return 0
  fi
  masi_log "Patching scsp.cpp Linux pthread_cond_timedwait..."
  python3 - "$scsp_cpp" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="surrogateescape")
old = """#elif defined(ARCH_IS_LINUX)    
        time(&tm);    
        long n = tm.tv_nsec;
        tm.tv_nsec += sleeptime;
        if( n > tm.tv_nsec){
          tm.tv_sec += 1;
        }
        pthread_mutex_lock(&sync_mutex);
        int rtn = pthread_cond_timedwait(&sync_cnd,&sync_mutex,ctime(&tm));
"""
new = """#elif defined(ARCH_IS_LINUX)
        /* MasiScript: Linux SCSP timedwait — same as ANDROID (clock_gettime + &tm). */
        {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &tm);
        ts.tv_nsec = tm.tv_nsec + sleeptime;
        if (tm.tv_nsec > ts.tv_nsec) {
          tm.tv_sec += 1;
        }
        tm.tv_nsec = ts.tv_nsec;
        }
        pthread_mutex_lock(&sync_mutex);
        int rtn = pthread_cond_timedwait(&sync_cnd, &sync_mutex, &tm);
"""
if old not in text:
    sys.stderr.write("Could not find broken Linux SCSP timedwait block to patch\n")
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8", errors="surrogateescape")
print("scsp.cpp Linux timedwait patched", file=sys.stderr)
PY
}

# Scope ftello/fseeko feature macros to the nested libchdr ExternalProject only.
# Putting _GNU_SOURCE on the whole tree breaks Musashi (#define uint unsigned int).
# Also fix Linux LIBCHDR_LIBRARIES — upstream still lists flac/crypto/lzma-static
# paths that this libchdr tag does not produce.
patch_libchdr_external_cflags() {
  local cmake_file="$1"
  [[ -f "$cmake_file" ]] || masi_die "Missing ${cmake_file}"
  if grep -q 'MasiScript: libchdr CFLAGS' "$cmake_file"; then
    masi_log "external_libchdr.cmake CFLAGS patch already present."
  else
    masi_log "Patching external_libchdr.cmake for GNU/large-file CFLAGS..."
    python3 - "$cmake_file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="surrogateescape")
old = """  CMAKE_ARGS  -DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/libchdr 
              -DCMAKE_BUILD_TYPE:STRING=Release 
              -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
              -DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}
              ${ADDITIONAL_CMAKE_ARGS}
"""
new = """  # MasiScript: libchdr CFLAGS — need _GNU_SOURCE for ftello; do not apply to yabause.
  CMAKE_ARGS  -DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/libchdr
              -DCMAKE_BUILD_TYPE:STRING=Release
              -DCMAKE_POLICY_VERSION_MINIMUM=3.5
              -DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}
              "-DCMAKE_C_FLAGS=${CMAKE_C_FLAGS} -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64"
              ${ADDITIONAL_CMAKE_ARGS}
"""
if old not in text:
    sys.stderr.write("Could not find libchdr CMAKE_ARGS block to patch\n")
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8", errors="surrogateescape")
print("external_libchdr.cmake CFLAGS patched", file=sys.stderr)
PY
  fi

  if ! grep -q 'MasiScript: libchdr Linux libs' "$cmake_file"; then
    masi_log "Patching external_libchdr.cmake Linux library list..."
    python3 - "$cmake_file" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="surrogateescape")
old = """else()
set(LIBCHDR_LIBRARIES  
 ${BINARY_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}chdr-static${CMAKE_STATIC_LIBRARY_SUFFIX}
 ${BINARY_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}flac-static${CMAKE_STATIC_LIBRARY_SUFFIX}
 ${BINARY_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}crypto-static${CMAKE_STATIC_LIBRARY_SUFFIX}
 ${BINARY_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}lzma-static${CMAKE_STATIC_LIBRARY_SUFFIX}
 ${BINARY_DIR}/deps/zstd-1.5.6/build/cmake/lib/${CMAKE_STATIC_LIBRARY_PREFIX}zstd${CMAKE_STATIC_LIBRARY_SUFFIX}
 )
 set( LIBCHDR_LIB_DIR ${BINARY_DIR} )
endif()
"""
new = """else()
# MasiScript: libchdr Linux libs — match libs produced by GIT_TAG 5a64235.
set(LIBCHDR_LIBRARIES
 ${BINARY_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}chdr-static${CMAKE_STATIC_LIBRARY_SUFFIX}
 ${BINARY_DIR}/deps/lzma-24.05/${CMAKE_STATIC_LIBRARY_PREFIX}lzma${CMAKE_STATIC_LIBRARY_SUFFIX}
 ${BINARY_DIR}/deps/zlib-1.3.1/${CMAKE_STATIC_LIBRARY_PREFIX}z${CMAKE_STATIC_LIBRARY_SUFFIX}
 ${BINARY_DIR}/deps/zstd-1.5.6/build/cmake/lib/${CMAKE_STATIC_LIBRARY_PREFIX}zstd${CMAKE_STATIC_LIBRARY_SUFFIX}
)
set(LIBCHDR_LIB_DIR ${BINARY_DIR} ${BINARY_DIR}/deps/lzma-24.05 ${BINARY_DIR}/deps/zlib-1.3.1 ${BINARY_DIR}/deps/zstd-1.5.6/build/cmake/lib)
endif()
"""
if old not in text:
    sys.stderr.write("Could not find Linux LIBCHDR_LIBRARIES block to patch\n")
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8", errors="surrogateescape")
print("external_libchdr.cmake Linux libs patched", file=sys.stderr)
PY
  fi
}

# Qt desktop sources still include Windows CRT / DEVMODE fullscreen helpers.
patch_qt_linux_winapis() {
  local qt_dir="$1"
  local main_cpp="${qt_dir}/main.cpp"
  local ui_h="${qt_dir}/ui/UIYabause.h"
  local ui_cpp="${qt_dir}/ui/UIYabause.cpp"

  [[ -f "$main_cpp" && -f "$ui_h" && -f "$ui_cpp" ]] \
    || masi_die "Missing Qt sources under ${qt_dir}"

  local gl_h="${qt_dir}/YabauseGL.h"
  if [[ -f "$gl_h" ]] && ! grep -q 'MasiScript: windows.h Windows-only' "$gl_h"; then
    masi_log "Patching YabauseGL.h (windows.h is Windows-only)..."
    python3 - "$gl_h" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="surrogateescape")
old = "#include <windows.h>\n#include <QOpenGLFunctions>"
new = """#ifdef Q_OS_WIN
#include <windows.h>
#endif
/* MasiScript: windows.h Windows-only */
#include <QOpenGLFunctions>"""
if old not in text:
    sys.stderr.write("Could not find windows.h include in YabauseGL.h\n")
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8", errors="surrogateescape")
print("YabauseGL.h windows.h patched", file=sys.stderr)
PY
  fi

  # WinSparkle is Windows-only; provide no-op headers on Linux.
  # Upstream only adds winsparkle/include on WIN32, so also drop a copy where
  # UIYabause.cpp (#include "winsparkle.h") can find it.
  local ws_inc="${qt_dir}/winsparkle/include"
  mkdir -p "$ws_inc" "${qt_dir}/ui"
  if [[ ! -f "${ws_inc}/winsparkle.h" ]] || ! grep -q 'MasiScript: WinSparkle stub' "${ws_inc}/winsparkle.h"; then
    masi_log "Installing WinSparkle no-op stub headers..."
    cat >"${ws_inc}/winsparkle.h" <<'EOF'
/* MasiScript: WinSparkle stub — real SDK is Windows-only. */
#pragma once
#ifdef __cplusplus
extern "C" {
#endif
static inline void win_sparkle_init(void) {}
static inline void win_sparkle_cleanup(void) {}
static inline void win_sparkle_set_appcast_url(const char*) {}
static inline void win_sparkle_set_app_details(const wchar_t*, const wchar_t*, const wchar_t*) {}
static inline void win_sparkle_set_app_build_version(const wchar_t*) {}
static inline void win_sparkle_set_dsa_pub_pem(const char*) {}
static inline void win_sparkle_set_automatic_check_for_updates(int) {}
static inline void win_sparkle_set_update_check_interval(int) {}
static inline void win_sparkle_check_update_with_ui(void) {}
#ifdef __cplusplus
}
#endif
EOF
  fi
  cp -f "${ws_inc}/winsparkle.h" "${qt_dir}/winsparkle.h"
  cp -f "${ws_inc}/winsparkle.h" "${qt_dir}/ui/winsparkle.h"

  if ! grep -q 'MasiScript: crtdbg Windows-only' "$main_cpp"; then
    masi_log "Patching qt/main.cpp (crtdbg.h is Windows-only)..."
    python3 - "$main_cpp" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="surrogateescape")
old = "#include <crtdbg.h>\nint main( int argc, char** argv )"
new = """#ifdef _WIN32
#include <crtdbg.h>
#endif
/* MasiScript: crtdbg Windows-only */
int main( int argc, char** argv )"""
if old not in text:
    sys.stderr.write("Could not find crtdbg include in main.cpp\n")
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8", errors="surrogateescape")
print("main.cpp crtdbg patched", file=sys.stderr)
PY
  fi

  if ! grep -q 'MasiScript: DEVMODE Windows-only' "$ui_h"; then
    masi_log "Patching UIYabause.h (DEVMODE is Windows-only)..."
    python3 - "$ui_h" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="surrogateescape")
old = "\tDEVMODE originalMode;"
new = """#if defined(Q_OS_WIN)
\t/* MasiScript: DEVMODE Windows-only */
\tDEVMODE originalMode;
#endif"""
if old not in text:
    sys.stderr.write("Could not find DEVMODE originalMode in UIYabause.h\n")
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8", errors="surrogateescape")
print("UIYabause.h DEVMODE patched", file=sys.stderr)
PY
  fi

  if ! grep -q 'MasiScript: Windows display APIs' "$ui_cpp"; then
    masi_log "Patching UIYabause.cpp Windows display APIs for Linux..."
    python3 - "$ui_cpp" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="surrogateescape")
old = """void UIYabause::saveCurrentResolution() {
	EnumDisplaySettings(nullptr, ENUM_CURRENT_SETTINGS, &originalMode);
}

void UIYabause::restoreResolution() {
	ChangeDisplaySettings(&originalMode, 0);
}

void UIYabause::setResolution(int width, int height) {

	QList<QScreen*> screens = QGuiApplication::screens();
	QScreen* targetScreen = screens[0];
	windowHandle()->setScreen(targetScreen);

	DEVMODE mode = originalMode;
	mode.dmPelsWidth = width;
	mode.dmPelsHeight = height;
	mode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT;
	ChangeDisplaySettingsEx(targetScreen->name().toStdWString().c_str(), &mode, NULL, CDS_FULLSCREEN, NULL );
}
"""
new = """void UIYabause::saveCurrentResolution() {
#if defined(Q_OS_WIN)
	/* MasiScript: Windows display APIs */
	EnumDisplaySettings(nullptr, ENUM_CURRENT_SETTINGS, &originalMode);
#else
	(void)0;
#endif
}

void UIYabause::restoreResolution() {
#if defined(Q_OS_WIN)
	ChangeDisplaySettings(&originalMode, 0);
#else
	(void)0;
#endif
}

void UIYabause::setResolution(int width, int height) {
#if defined(Q_OS_WIN)
	QList<QScreen*> screens = QGuiApplication::screens();
	QScreen* targetScreen = screens[0];
	windowHandle()->setScreen(targetScreen);

	DEVMODE mode = originalMode;
	mode.dmPelsWidth = width;
	mode.dmPelsHeight = height;
	mode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT;
	ChangeDisplaySettingsEx(targetScreen->name().toStdWString().c_str(), &mode, NULL, CDS_FULLSCREEN, NULL );
#else
	(void)width;
	(void)height;
#endif
}
"""
if old not in text:
    sys.stderr.write("Could not find Windows display API helpers in UIYabause.cpp\n")
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8", errors="surrogateescape")
print("UIYabause.cpp display APIs patched", file=sys.stderr)
PY
  fi

  local fsw="${qt_dir}/filesearchwidget.cpp"
  if [[ -f "$fsw" ]] && grep -q 'GametableView.h' "$fsw" && ! grep -q 'MasiScript: GameTableView include' "$fsw"; then
    masi_log "Patching filesearchwidget.cpp GameTableView include typo..."
    python3 - "$fsw" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="surrogateescape")
old = '#include "GametableView.h"'
new = '/* MasiScript: GameTableView include */\n#include "GameTableView.h"'
if old not in text:
    sys.stderr.write("Could not find GametableView.h include\n")
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8", errors="surrogateescape")
print("filesearchwidget.cpp include patched", file=sys.stderr)
PY
  fi
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
    masi_sudo rm -f "${PREFIX}/bin/yabasanshiro" \
      "${PREFIX}/share/applications/yabasanshiro.desktop" \
      "${PREFIX}/share/icons/hicolor/256x256/apps/yabasanshiro.png"
  fi
  masi_refresh_desktop_and_icons "${PREFIX}/share"
  masi_log "=== ${APP_NAME} removed ==="
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} (GPL source → Qt desktop) ==="
  masi_log "Install prefix: ${PREFIX}"
  masi_log "Source: official tarball from yabasanshiro.com (GitHub repo is private)."
  masi_log "Ubuntu Mesa will not be installed (vendor Adreno/Turnip Mesa)."

  if [[ ! -f /usr/include/EGL/egl.h ]]; then
    masi_die "Missing EGL headers (/usr/include/EGL/egl.h). Use your vendor Mesa SDK, not Ubuntu Mesa."
  fi

  masi_ensure_sudo
  masi_ensure_mesa_dev_stubs
  masi_apt_install "${BUILD_DEPS[@]}"

  masi_prepare_build "$APP_ID"
  local src_dir="${MASI_WORK}/src"
  local build_dir="${MASI_WORK}/build"

  fetch_official_source "$src_dir"
  fetch_rcheevos "$src_dir"

  local cmake_src="${src_dir}/yabause"
  local qt_dir="${cmake_src}/src/qt"
  [[ -f "${cmake_src}/CMakeLists.txt" ]] || masi_die "Missing ${cmake_src}/CMakeLists.txt"
  [[ -f "${qt_dir}/CMakeLists.txt" ]] || masi_die "Missing ${qt_dir}/CMakeLists.txt"

  install_firebase_stubs "$qt_dir"
  patch_qt_cmake_for_linux "${qt_dir}/CMakeLists.txt"
  patch_memory_ww_check "${cmake_src}/src/memory.c"
  patch_scsp_linux_timedwait "${cmake_src}/src/scsp.cpp"
  patch_libchdr_external_cflags "${cmake_src}/CMake/Packages/external_libchdr.cmake"
  patch_qt_linux_winapis "$qt_dir"
  masi_log "Installing OpenGL-only Vulkan UI stubs..."
  python3 "${SCRIPT_DIR}/yaba_opengl_vulkan_skip.py" "$qt_dir" \
    "${SCRIPT_DIR}/yaba_qyabvulkan_stub.cpp"

  # Nested ExternalProject (libchdr) still ships cmake_minimum_required < 3.5.
  export CMAKE_POLICY_VERSION_MINIMUM=3.5
  # GCC 14+ turns several legacy-C issues into hard errors; keep them warnings.
  # Do NOT add _GNU_SOURCE here — it breaks Musashi's uint macro.
  # VIDCORE_VULKAN is only declared when YAB_WANT_VULKAN=ON, but Qt UI compares
  # against it unconditionally — provide the same numeric id as vulkan/VIDVulkanCInterface.h.
  local yaba_cflags="-Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=implicit-function-declaration"
  local yaba_cxxflags="-DVIDCORE_VULKAN=4"

  # Ninja cannot see ExternalProject outputs without BUILD_BYPRODUCTS (upstream
  # omits them), so use Makefiles like RetroPie's yabasanshiro scriptmodule.
  masi_log "Configuring CMake (Qt6 port + dynarec + Firebase stub)..."
  cmake -S "$cmake_src" -B "$build_dir" -G "Unix Makefiles" \
    -Wno-dev \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_C_FLAGS="${yaba_cflags}" \
    -DCMAKE_CXX_FLAGS="${yaba_cxxflags}" \
    -DOpenGL_GL_PREFERENCE=LEGACY \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,--as-needed -lGL" \
    -DYAB_PORTS=qt \
    -DYAB_WANT_DYNAREC_DEVMIYAX=ON

  masi_log "Building ExternalProject libchdr..."
  cmake --build "$build_dir" --target libchdr --parallel "$(masi_nproc)"

  masi_log "Compiling with $(masi_nproc) jobs..."
  cmake --build "$build_dir" --parallel "$(masi_nproc)"

  local binary=""
  if [[ -x "${build_dir}/src/qt/yabasanshiro" ]]; then
    binary="${build_dir}/src/qt/yabasanshiro"
  elif [[ -x "${build_dir}/src/qt/yabause-qt" ]]; then
    binary="${build_dir}/src/qt/yabause-qt"
  else
    binary="$(find "$build_dir" -type f -executable \( -name 'yabasanshiro' -o -name 'yabause-qt' \) | head -n1 || true)"
  fi
  [[ -n "$binary" && -x "$binary" ]] || masi_die "yabasanshiro/yabause-qt binary not found after build"

  masi_ensure_sudo
  masi_log "Installing ${binary} → ${PREFIX}/bin/yabasanshiro"
  masi_sudo install -Dm755 "$binary" "${PREFIX}/bin/yabasanshiro"

  local desktop_dst="${PREFIX}/share/applications/yabasanshiro.desktop"
  local icon_dst="${PREFIX}/share/icons/hicolor/256x256/apps/yabasanshiro.png"
  masi_sudo mkdir -p "$(dirname "$desktop_dst")" "$(dirname "$icon_dst")"

  local icon_src=""
  icon_src="$(find "$src_dir" -type f \( -iname '*yabasanshiro*.png' -o -iname '*yabause*.png' \) | head -n1 || true)"
  if [[ -n "$icon_src" ]]; then
    masi_sudo cp -a "$icon_src" "$icon_dst"
  fi

  masi_sudo tee "$desktop_dst" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=YabaSanshiro
GenericName=SEGA Saturn Emulator
Comment=SEGA Saturn emulator (YabaSanshiro)
Exec=${PREFIX}/bin/yabasanshiro %f
Icon=yabasanshiro
Terminal=false
Categories=Game;Emulator;
Keywords=Saturn;SEGA;YabaSanshiro;Yabause;
StartupNotify=true
EOF

  write_manifest \
    "${PREFIX}/bin/yabasanshiro" \
    "$desktop_dst" \
    "$icon_dst"

  masi_refresh_desktop_and_icons "${PREFIX}/share"

  masi_log "Removing source/build tree..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "Binary:   ${PREFIX}/bin/yabasanshiro"
  masi_log "Desktop:  ${desktop_dst}"
  masi_log "Manifest: ${MASI_MANIFESTS}/${APP_ID}.txt"
  masi_log "Run: yabasanshiro"
  cat <<EOF

[EmuKitARM] WARNING — YabaSanshiro
- Point the GUI at your Saturn BIOS and enable OpenGL + SH2 recompiler for speed.
- Cloud sync is a no-op stub (real Firebase SDK omitted / broken on CMake 4).
- ROMs / disc images are not included.

EOF
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
