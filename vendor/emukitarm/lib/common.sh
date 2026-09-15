#!/usr/bin/env bash
# Shared helpers for EmuKitARM installers.
set -euo pipefail

MASI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASI_CACHE="${MASI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/emukitarm}"
# System-style locations (not a private emukitarm apps tree).
MASI_APPLICATIONS="${MASI_APPLICATIONS:-$HOME/Applications}"
MASI_BIN="${MASI_BIN:-$HOME/.local/bin}"
MASI_DESKTOP="${MASI_DESKTOP:-${XDG_DATA_HOME:-$HOME/.local/share}/applications}"
MASI_ICONS="${MASI_ICONS:-${XDG_DATA_HOME:-$HOME/.local/share}/icons}"
MASI_BUILD_ROOT="${MASI_CACHE}/build"
MASI_MANIFESTS="${MASI_MANIFESTS:-${XDG_DATA_HOME:-$HOME/.local/share}/emukitarm/manifests}"
MASI_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/emukitarm"
MASI_SUDO_PASS_FILE="${MASI_SUDO_PASS_FILE:-${MASI_RUNTIME_DIR}/sudo_pass}"
MASI_ASKPASS="${MASI_ROOT}/lib/askpass"

mkdir -p "$MASI_CACHE" "$MASI_APPLICATIONS" "$MASI_BIN" "$MASI_DESKTOP" "$MASI_BUILD_ROOT" "$MASI_MANIFESTS" "$MASI_RUNTIME_DIR"
chmod 700 "$MASI_RUNTIME_DIR" 2>/dev/null || true

# Active build directory for the current script (set by masi_prepare_build).
MASI_WORK=""

masi_log() {
  # Always stderr so command substitutions like url="$(resolve...)" stay clean.
  # GUI merges stderr into the log view (stderr=STDOUT).
  printf '[EmuKitARM] %s\n' "$*" >&2
}

masi_die() {
  printf '[EmuKitARM] ERROR: %s\n' "$*" >&2
  exit 1
}

# Printed after every AppImage-based install.
masi_appimage_steam_warning() {
  local name="${1:-This AppImage}"
  cat <<EOF

[EmuKitARM] WARNING — Steam Gaming Mode / AppImage
If ${name} fails to launch under Steam Gaming Mode, add this to the
game/emulator launch options:

  APPIMAGE_EXTRACT_AND_RUN=1 %command%

Desktop sessions usually do not need this. It is for FUSE/AppImage
runtime issues inside Gaming Mode.

EOF
}

# Printed after shadPS4 QtLauncher install (log only, no GUI dialog).
masi_shadps4_qtlauncher_warning() {
  cat <<EOF

[EmuKitARM] WARNING — shadPS4 QtLauncher is GUI only
Install ShadPS4 (ARM64) as well, then in the launcher:
  Version Manager → Add Custom → ~/shadps4/<version>/shadps4
Official x86_64 downloads from the launcher will not work on aarch64.

EOF
}

# Printed after ShadPS4 ARM64 core install (log only, no GUI dialog).
masi_shadps4_core_warning() {
  local binary_path="${1:-~/shadps4/<version>/shadps4}"
  cat <<EOF

[EmuKitARM] WARNING — ShadPS4 (ARM64) is the emulator core only (no Qt GUI)
Also install shadPS4 QtLauncher, then:
  Version Manager → Add Custom → ${binary_path}

EOF
}

masi_require_aarch64() {
  local arch
  arch="$(uname -m)"
  [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] || masi_die "aarch64 is required (found: $arch)"
}

masi_nproc() {
  getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4
}

# Prefer sudo + session askpass (one password prompt per EmuKitARM session).
# Avoid pkexec: it asks again on every call.
masi_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
    return
  fi
  command -v sudo >/dev/null 2>&1 || masi_die "sudo is required"

  export SUDO_ASKPASS="$MASI_ASKPASS"
  export MASI_SUDO_PASS_FILE

  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [[ -r "$MASI_SUDO_PASS_FILE" ]]; then
    sudo -A "$@"
  elif [[ -t 0 ]]; then
    sudo "$@"
  else
    sudo -A "$@"
  fi
}

# Authenticate once for this session (no-op if already cached / password file present).
masi_ensure_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi
  command -v sudo >/dev/null 2>&1 || masi_die "sudo is required"
  export SUDO_ASKPASS="$MASI_ASKPASS"
  export MASI_SUDO_PASS_FILE

  if sudo -n true 2>/dev/null; then
    masi_log "Administrator privileges already available for this session."
    return 0
  fi

  masi_log "Requesting administrator privileges (once for this session)..."
  if [[ -r "$MASI_SUDO_PASS_FILE" ]]; then
    sudo -A -v
  elif [[ -t 0 ]]; then
    sudo -v
  else
    sudo -A -v
  fi
  masi_log "Administrator privileges cached for this session."
}

# Ubuntu stock Mesa is blocked on this platform (vendor Adreno/Turnip Mesa).
# Never install these packages or anything that hard-depends on them.
MASI_MESA_BLOCKED_PKGS=(
  libegl1-mesa-dev libgles2-mesa-dev libegl-mesa0 libgl1-mesa-dri libglx-mesa0
  mesa-libgallium mesa-vulkan-drivers mesa-va-drivers mesa-vdpau-drivers
  libgl1-mesa-glx libgbm-dev libgbm1
)

masi_is_mesa_blocked_pkg() {
  local pkg="$1" blocked
  for blocked in "${MASI_MESA_BLOCKED_PKGS[@]}"; do
    [[ "$pkg" == "$blocked" || "$pkg" == "${blocked}:"* ]] && return 0
  done
  case "$pkg" in
    mesa-*|libegl1-mesa*|libgles2-mesa*|libgl1-mesa*|libglx-mesa*|libgbm*) return 0 ;;
  esac
  return 1
}

# True if apt can install the package without pulling blocked Mesa packages.
masi_apt_is_safe() {
  local pkg="$1"
  masi_is_mesa_blocked_pkg "$pkg" && return 1
  dpkg -s "$pkg" >/dev/null 2>&1 && return 0

  local sim
  sim="$(apt-get -s -o Debug::NoLocking=1 install "$pkg" 2>&1)" || return 1
  local line name
  while IFS= read -r line; do
    [[ "$line" =~ ^Inst[[:space:]]+([^[:space:]]+) ]] || continue
    name="${BASH_REMATCH[1]}"
    name="${name%%:*}"
    if masi_is_mesa_blocked_pkg "$name"; then
      return 1
    fi
  done <<<"$sim"
  return 0
}

masi_apt_install() {
  local pkgs=("$@")
  local missing=()
  local skipped=()
  local pkg
  for pkg in "${pkgs[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      continue
    fi
    if masi_is_mesa_blocked_pkg "$pkg"; then
      skipped+=("$pkg (mesa blocked)")
      continue
    fi
    if ! masi_apt_is_safe "$pkg"; then
      skipped+=("$pkg (requires Ubuntu Mesa)")
      continue
    fi
    missing+=("$pkg")
  done

  if ((${#skipped[@]} > 0)); then
    masi_log "Skipping packages that would touch Mesa (vendor Adreno/Turnip): ${skipped[*]}"
  fi
  if ((${#missing[@]} == 0)); then
    masi_log "System dependencies already installed (or safely skipped)."
    return 0
  fi

  masi_ensure_sudo
  masi_log "Installing packages: ${missing[*]}"
  masi_sudo apt-get update -y
  masi_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# Dummy Ubuntu Mesa -dev packages so GTK/etc. can install without replacing vendor Mesa.
# Satisfies Depends: libegl1-mesa-dev / libgles2-mesa-dev using glvnd headers already present.
masi_ensure_mesa_dev_stubs() {
  local stub
  local stubs=(libegl1-mesa-dev libgles2-mesa-dev mesa-common-dev)
  local need=()
  for stub in "${stubs[@]}"; do
    if dpkg -s "$stub" >/dev/null 2>&1; then
      continue
    fi
    need+=("$stub")
  done
  if ((${#need[@]} == 0)); then
    return 0
  fi

  masi_ensure_sudo
  masi_log "Installing Mesa -dev stubs (keeps vendor Adreno Mesa): ${need[*]}"
  local work="${MASI_CACHE}/mesa-stubs"
  rm -rf "$work"
  mkdir -p "$work"

  for stub in "${need[@]}"; do
    local pkgdir="${work}/${stub}"
    mkdir -p "${pkgdir}/DEBIAN"
    cat >"${pkgdir}/DEBIAN/control" <<EOF
Package: ${stub}
Version: 999:0+emukitarm1
Architecture: all
Maintainer: EmuKitARM <emukitarm@local>
Depends: libegl-dev | libgl-dev | libgles-dev
Section: libdevel
Priority: optional
Description: EmuKitARM stub for ${stub}
 Dummy package that satisfies build dependencies without installing
 Ubuntu Mesa. Real GL/EGL/Vulkan come from the vendor Adreno stack.
EOF
    dpkg-deb -b "$pkgdir" "${work}/${stub}.deb" >/dev/null
    masi_sudo dpkg -i "${work}/${stub}.deb"
  done
}

# Create a fresh work dir and register cleanup on EXIT / INT / TERM.
masi_prepare_build() {
  local name="$1"
  MASI_WORK="${MASI_BUILD_ROOT}/${name}"
  rm -rf "$MASI_WORK"
  mkdir -p "$MASI_WORK"
  trap 'masi_cleanup_build' EXIT INT TERM
  masi_log "Work directory: $MASI_WORK"
}

masi_cleanup_build() {
  local code=$?
  if [[ -n "${MASI_WORK:-}" && -d "$MASI_WORK" ]]; then
    # Keep failed trees by default so the next fix pass can inspect logs/objects.
    # Set MASI_KEEP_FAILED_BUILD=0 to always wipe. Successful installs still
    # remove the tree explicitly in each script when they finish cleanly.
    if [[ "$code" -ne 0 && "${MASI_KEEP_FAILED_BUILD:-1}" != "0" ]]; then
      masi_log "Keeping failed build tree for inspection: $MASI_WORK"
    else
      masi_log "Removing build leftovers: $MASI_WORK"
      rm -rf "$MASI_WORK"
    fi
  fi
  return "$code"
}

# Default system prefix for compiled apps (classic manual cmake --install).
MASI_PREFIX="${MASI_PREFIX:-/usr/local}"

masi_cmake_install() {
  local build_dir="$1"
  local app_id="${2:-}"
  masi_ensure_sudo
  masi_log "Installing to ${MASI_PREFIX} (cmake --install)..."
  masi_sudo cmake --install "$build_dir"
  if [[ -n "$app_id" && -f "${build_dir}/install_manifest.txt" ]]; then
    masi_save_install_manifest "$app_id" "${build_dir}/install_manifest.txt"
  fi
}

masi_save_install_manifest() {
  local app_id="$1"
  local src_manifest="$2"
  local dest="${MASI_MANIFESTS}/${app_id}.txt"
  mkdir -p "$MASI_MANIFESTS"
  cp -a "$src_manifest" "$dest"
  chmod 644 "$dest"
  masi_log "Saved install manifest: $dest"
}

masi_uninstall_from_manifest() {
  local app_id="$1"
  local manifest="${MASI_MANIFESTS}/${app_id}.txt"
  if [[ ! -f "$manifest" ]]; then
    masi_die "No install manifest for '${app_id}' at $manifest (was it installed with EmuKitARM?)"
  fi
  masi_ensure_sudo
  masi_log "Uninstalling '${app_id}' from manifest..."
  # Remove files in reverse order (binaries/dirs often listed leaves-first).
  local path
  mapfile -t _masi_paths < <(
    if command -v tac >/dev/null 2>&1; then
      tac "$manifest"
    else
      awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}' "$manifest"
    fi
  )
  for path in "${_masi_paths[@]}"; do
    [[ -n "$path" ]] || continue
    if [[ -e "$path" || -L "$path" ]]; then
      masi_sudo rm -f "$path" 2>/dev/null || masi_sudo rm -rf "$path"
      masi_log "Removed $path"
    fi
  done
  rm -f "$manifest"
  masi_log "Removed manifest $manifest"
}

masi_refresh_desktop_and_icons() {
  local data_root="${1:-${MASI_PREFIX}/share}"
  if command -v update-desktop-database >/dev/null 2>&1 && [[ -d "${data_root}/applications" ]]; then
    masi_sudo update-desktop-database "${data_root}/applications" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1 && [[ -d "${data_root}/icons/hicolor" ]]; then
    masi_sudo gtk-update-icon-cache -f -t "${data_root}/icons/hicolor" >/dev/null 2>&1 || true
  fi
}

masi_install_desktop_entry() {
  local app_id="$1"
  local name="$2"
  local exec_cmd="$3"
  local comment="${4:-}"
  local icon="${5:-application-x-executable}"
  local desktop_file="${MASI_DESKTOP}/${app_id}.desktop"

  cat >"$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=${name}
Comment=${comment}
Exec=${exec_cmd}
Icon=${icon}
Terminal=false
Categories=Game;Emulator;
StartupNotify=true
EOF
  chmod 644 "$desktop_file"
  masi_log "Desktop entry: $desktop_file"
}

masi_link_bin() {
  local target="$1"
  local link_name="$2"
  mkdir -p "$MASI_BIN"
  # Drop broken/outdated links first so writers don't follow them.
  rm -f "${MASI_BIN}/${link_name}"
  ln -sfn "$target" "${MASI_BIN}/${link_name}"
  masi_log "Symlink: ${MASI_BIN}/${link_name} -> ${target}"
}

# Copy shared libs referenced by a binary that live under a given prefix.
masi_bundle_libs() {
  local binary="$1"
  local lib_src="$2"
  local lib_dst="$3"
  mkdir -p "$lib_dst"
  local line libbase
  while IFS= read -r line; do
    [[ "$line" == *"${lib_src}"* ]] || continue
    local path
    path="$(awk '{print $3}' <<<"$line")"
    [[ -f "$path" ]] || continue
    libbase="$(basename "$path")"
    cp -a "$path" "${lib_dst}/${libbase}"
  done < <(ldd "$binary" 2>/dev/null || true)

  if [[ -d "$lib_src" ]]; then
    local f
    for f in "$lib_src"/libQt6*.so* "$lib_src"/libSDL3*.so* "$lib_src"/libshaderc*.so* \
             "$lib_src"/libspirv*.so* "$lib_src"/libwebp*.so* "$lib_src"/libjpeg*.so* \
             "$lib_src"/libpng*.so* "$lib_src"/libzstd*.so* "$lib_src"/libfreetype*.so* \
             "$lib_src"/libharfbuzz*.so* "$lib_src"/libzip*.so* "$lib_src"/libSoundTouch*.so* \
             "$lib_src"/libplutosvg*.so* "$lib_src"/libdiscord-rpc*.so* "$lib_src"/libcpuinfo*.so*; do
      [[ -e "$f" ]] || continue
      cp -a "$f" "$lib_dst/" 2>/dev/null || true
    done
  fi
}
