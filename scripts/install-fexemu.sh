#!/usr/bin/env bash
# Install / update / uninstall FEXEmu on the live handheld (aarch64).
# In this repo: clones under vendor/FEXEmu/FEX.
# On the device: clones under $HOME/src/fex-emu (user-writable), then installs
# binaries system-wide with one sudo password prompt.
#
# Usage (Desktop / konsole — will ask for your password):
#   ./scripts/install-fexemu.sh
#   /usr/bin/install-fexemu
#   sudo ./scripts/install-fexemu.sh install|update|uninstall
#
# Notes:
#   - Source/build live in the user home tree (no /usr/local/src permission fights).
#   - Build deps + ninja install still need root once (apt + /usr binaries).
#   - Do not install BOX64 and FEX together (binfmt conflict).
set -euo pipefail

# Elevate early so konsole/desktop launch gets a password prompt instead of exiting.
if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer the invoking user for ~/.config, RootFS paths, and source checkout
REAL_USER="${SUDO_USER:-${USER:-}}"
[[ -n "$REAL_USER" && "$REAL_USER" != "root" ]] || REAL_USER="$(logname 2>/dev/null || true)"
REAL_USER="${REAL_USER:-steam}"
REAL_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6 || true)"
REAL_HOME="${REAL_HOME:-/home/${REAL_USER}}"
REAL_UID="$(id -u "$REAL_USER" 2>/dev/null || echo 1000)"
REAL_GID="$(id -g "$REAL_USER" 2>/dev/null || echo 1000)"

# Repo checkout: scripts/install-fexemu.sh → vendor/FEXEmu
# On-device (ARM-Manager): /usr/bin/install-fexemu → ~/src/fex-emu
if [[ -d "${_SCRIPT_DIR}/../vendor" && -f "${_SCRIPT_DIR}/../create-image.sh" ]]; then
  ROOT_DIR="$(cd "${_SCRIPT_DIR}/.." && pwd)"
  VENDOR_DIR="${ROOT_DIR}/vendor/FEXEmu"
else
  VENDOR_DIR="${FEX_VENDOR_DIR:-${REAL_HOME}/src/fex-emu}"
fi
SRC_DIR="${VENDOR_DIR}/FEX"
BUILD_DIR="${SRC_DIR}/build"
MANIFEST_SYS="/usr/local/share/fex-emu/install_manifest.txt"
ROOTFS_JSON_URL="https://rootfs.fex-emu.gg/RootFS_links.json"
FEX_REPO="https://github.com/FEX-Emu/FEX.git"

log()  { printf '==> [fexemu] %s\n' "$*" >&2; }
warn() { printf '==> [fexemu] WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

ask_yes_no() {
  local prompt="$1" default="${2:-n}" ans
  local hint="[y/N]"
  [[ "$default" == "y" ]] && hint="[Y/n]"
  while true; do
    read -r -p "${prompt} ${hint} " ans || return 1
    ans="${ans,,}"
    [[ -z "$ans" ]] && ans="$default"
    case "$ans" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
    esac
  done
}

box64_detected() {
  command -v box64 >/dev/null 2>&1 && return 0
  [[ -f /etc/binfmt.d/box64.conf || -f /usr/lib/binfmt.d/box64.conf ]] && return 0
  [[ -x /usr/local/bin/box64 ]] && return 0
  return 1
}

fex_installed() {
  command -v FEX >/dev/null 2>&1 && return 0
  [[ -f /usr/lib/binfmt.d/FEX-x86_64.conf ]] && return 0
  [[ -f "$MANIFEST_SYS" ]] && return 0
  return 1
}

run_as_user() {
  if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
    sudo -u "$REAL_USER" -H -- "$@"
  else
    "$@"
  fi
}

chown_vendor_tree() {
  if [[ -d "$VENDOR_DIR" && -n "$REAL_UID" && -n "$REAL_GID" ]]; then
    chown -R "${REAL_UID}:${REAL_GID}" "$VENDOR_DIR" 2>/dev/null || true
  fi
}

cleanup_build_tree() {
  # Installed binaries and manifest live under /usr — source tree is compile-only.
  [[ -d "$VENDOR_DIR" ]] || return 0
  if [[ -n "${ROOT_DIR:-}" && "$VENDOR_DIR" == "${ROOT_DIR}/vendor/FEXEmu" ]]; then
    log "Keeping repo vendor tree (${VENDOR_DIR})"
    return 0
  fi
  # Leave build dir before rm -rf or subshells hit getcwd errors.
  cd "${REAL_HOME}" 2>/dev/null || cd / || true
  log "Removing FEX source/build tree: ${VENDOR_DIR}"
  rm -rf "$VENDOR_DIR"
  local src_parent="${REAL_HOME}/src"
  if [[ -d "$src_parent" ]] && [[ -z "$(ls -A "$src_parent" 2>/dev/null)" ]]; then
    log "Removing empty ${src_parent}"
    rmdir "$src_parent" 2>/dev/null || true
  fi
}

# --- Dependency resolution (Ubuntu Resolute / Debian-like) ---
pick_cross_ver() {
  # Prefer newest available among 14 13 12
  local v
  for v in 14 13 12; do
    if apt-cache show "libgcc-${v}-dev-amd64-cross" >/dev/null 2>&1; then
      echo "$v"
      return 0
    fi
  done
  echo "12"
}

ensure_man_cache_permissions() {
  # man-db apt triggers run mandb as user "man" (Ubuntu tmpfiles: man:man 0755).
  # Image bake chown -R root:root on /var/cache breaks that → Permission denied spam.
  local fix_script="${_SCRIPT_DIR}/fix-man-cache.sh"
  if [[ -x "$fix_script" ]]; then
    log "Fixing /var/cache/man (fix-man-cache.sh)..."
    "$fix_script" / || true
    return 0
  fi
  local man_dir="/var/cache/man"
  [[ -d "$man_dir" ]] || mkdir -p "$man_dir"
  local owner group
  owner="$(stat -c '%U' "$man_dir" 2>/dev/null || echo unknown)"
  group="$(stat -c '%G' "$man_dir" 2>/dev/null || echo unknown)"
  if [[ "$owner" != "man" || "$group" != "man" ]]; then
    log "Fixing ${man_dir} ownership (was ${owner}:${group} → man:man)..."
    chown -R man:man "$man_dir" 2>/dev/null || chown -R root:man "$man_dir"
    find "$man_dir" -type d -exec chmod 0755 {} + 2>/dev/null || true
    find "$man_dir" -type f -exec chmod 0644 {} + 2>/dev/null || true
    chmod 0755 "$man_dir" 2>/dev/null || true
  fi
  if command -v runuser >/dev/null 2>&1; then
    runuser -u man -- mandb -pq 2>/dev/null || true
  fi
}

ensure_fex_user_data_permissions() {
  # Steam Gaming Mode can create ~/.local/share/fex-emu as root; steam user then
  # cannot mkdir/curl RootFS. Repair tree + parents we need for writes.
  local paths=(
    "${REAL_HOME}/.local"
    "${REAL_HOME}/.local/share"
    "${REAL_HOME}/.local/share/fex-emu"
    "${REAL_HOME}/.local/share/fex-emu/RootFS"
    "${REAL_HOME}/.config"
    "${REAL_HOME}/.config/fex-emu"
  )
  local p owner
  for p in "${paths[@]}"; do
    [[ -e "$p" ]] || continue
    owner="$(stat -c '%u' "$p" 2>/dev/null || echo "")"
    if [[ -n "$owner" && "$owner" != "$REAL_UID" ]]; then
      log "Repairing FEX path ownership: ${p} (was uid ${owner})"
      chown -R "${REAL_UID}:${REAL_GID}" "$p" 2>/dev/null || true
    fi
  done
  install -d -o "$REAL_UID" -g "$REAL_GID" -m 0755 \
    "${REAL_HOME}/.local/share/fex-emu/RootFS" \
    "${REAL_HOME}/.config/fex-emu" 2>/dev/null || true
}

steam_fex_status() {
  # Steam may ship its own FEX for Proton-on-ARM inside pressure-vessel; that is
  # not the same as system binfmt FEX required by Decky PluginLoader.
  local steam_roots=(
    "${REAL_HOME}/.local/share/Steam"
    "${REAL_HOME}/.steam/steam"
  )
  local root found=0 owner_uid
  for root in "${steam_roots[@]}"; do
    [[ -d "$root" ]] || continue
    if find "$root" -maxdepth 6 -type f -name 'FEX' 2>/dev/null | grep -q .; then
      found=1
      break
    fi
  done
  if (( found )); then
    warn "Steam-bundled FEX detected (Proton/pressure-vessel only — not system binfmt)."
    warn "Decky PluginLoader needs system FEX (/usr/bin/FEX + binfmt + RootFS here)."
  fi
  if [[ -d "${REAL_HOME}/.local/share/fex-emu" ]]; then
    owner_uid="$(stat -c '%u' "${REAL_HOME}/.local/share/fex-emu" 2>/dev/null || echo "")"
    if [[ -n "$owner_uid" && "$owner_uid" != "$REAL_UID" ]]; then
      warn "fex-emu data dir owned by uid ${owner_uid} — Steam may have broken permissions (will repair)."
    fi
  fi
}

clear_stale_apt_lists() {
  rm -rf /var/lib/apt/lists/partial/* 2>/dev/null || true
  rm -f /var/lib/apt/lists/*resolute-security* 2>/dev/null || true
}

apt_update_without_security() {
  # FEX build deps (clang, cmake, cross-gcc, …) live in main/universe, not
  # resolute-security. When ports.ubuntu.com is mid-sync, security alone can
  # block the whole update — install deps from the other pockets instead.
  local tmp dir
  tmp="$(mktemp -d)"
  dir="${tmp}/apt"
  mkdir -p "${dir}/sources.list.d"
  if [[ -f /etc/apt/sources.list ]]; then
    grep -v 'resolute-security' /etc/apt/sources.list >"${dir}/sources.list" || true
  else
    : >"${dir}/sources.list"
  fi
  if [[ -d /etc/apt/sources.list.d ]]; then
    local f base
    for f in /etc/apt/sources.list.d/*; do
      [[ -f "$f" ]] || continue
      base="$(basename "$f")"
      if grep -q 'resolute-security' "$f" 2>/dev/null; then
        grep -v 'resolute-security' "$f" >"${dir}/sources.list.d/${base}" || true
      else
        cp "$f" "${dir}/sources.list.d/${base}"
      fi
    done
  fi
  clear_stale_apt_lists
  log "apt update without resolute-security (mirror sync workaround)..."
  apt-get update -y \
    -o "Dir::Etc::sourcelist=${dir}/sources.list" \
    -o "Dir::Etc::sourceparts=${dir}/sources.list.d" \
    -o Acquire::Retries=5
  rm -rf "$tmp"
}

apt_update_resilient() {
  local attempt max=5 wait=8
  export DEBIAN_FRONTEND=noninteractive
  for attempt in $(seq 1 "$max"); do
    log "apt update (attempt ${attempt}/${max})..."
    clear_stale_apt_lists
    if apt-get update -y -o Acquire::Retries=5 2>&1; then
      return 0
    fi
    warn "apt update failed — mirror may be syncing (ports.ubuntu.com resolute-security is a common culprit)"
    if (( attempt < max )); then
      log "Retrying in ${wait}s..."
      sleep "$wait"
      wait=$((wait + 7))
    fi
  done
  warn "Full apt update still failing — continuing with main/universe only (enough for FEX build deps)"
  apt_update_without_security \
    || die "apt update failed even without resolute-security — check network, then: sudo rm -f /var/lib/apt/lists/*resolute-security* && sudo apt update"
  warn "When ports.ubuntu.com finishes syncing, run: sudo apt update"
}

install_build_deps() {
  local ver pkgs missing=()
  ver="$(pick_cross_ver)"
  ensure_man_cache_permissions
  log "Installing build dependencies (cross GCC ${ver}, Ubuntu/Debian packages)..."

  pkgs=(
    python3 python3-pip git cmake ninja-build pkgconf ccache clang llvm lld
    binfmt-support libssl-dev python3-setuptools nasm python3-clang
    squashfs-tools squashfuse debootstrap patchelf
    g++-x86-64-linux-gnu
    "libgcc-${ver}-dev-amd64-cross"
    "libstdc++-${ver}-dev-amd64-cross"
    "libstdc++-${ver}-dev-arm64-cross"
    libc-devtools
    libc6-dev-i386-amd64-cross
    "lib32stdc++-${ver}-dev-amd64-cross"
    # FEXConfig Qt5 UI (optional but useful)
    qtdeclarative5-dev
    qml-module-qtquick-controls
    qml-module-qtquick-controls2
    qml-module-qtquick-dialogs
  )

  # libgcc i386-cross may be named differently; try both
  if apt-cache show "libgcc-${ver}-dev-i386-cross" >/dev/null 2>&1; then
    pkgs+=("libgcc-${ver}-dev-i386-cross" "libstdc++-${ver}-dev-i386-cross")
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt_update_resilient
  for p in "${pkgs[@]}"; do
    if ! apt-get install -y --no-install-recommends "$p"; then
      warn "Could not install package: $p (continuing)"
      missing+=("$p")
    fi
  done
  if ((${#missing[@]})); then
    warn "Missing packages: ${missing[*]}"
    warn "Build may still succeed; if cmake fails, install them manually."
  fi
}

ensure_source() {
  log "FEX source tree: ${SRC_DIR}"
  install -d -o "$REAL_UID" -g "$REAL_GID" "$VENDOR_DIR" 2>/dev/null || install -d "$VENDOR_DIR"
  if [[ -d "${SRC_DIR}/.git" ]]; then
    log "Updating FEX source in ${SRC_DIR}..."
    run_as_user git -C "$SRC_DIR" fetch --recurse-submodules origin
    run_as_user git -C "$SRC_DIR" pull --ff-only || true
    run_as_user git -C "$SRC_DIR" submodule update --init --recursive
  else
    log "Cloning FEX into ${SRC_DIR} (user-writable)..."
    rm -rf "$SRC_DIR"
    run_as_user git clone --recurse-submodules "$FEX_REPO" "$SRC_DIR"
  fi
  chown_vendor_tree
}

build_and_install_fex() {
  ensure_source
  install_build_deps

  log "Configuring (clang + lld + LTO)..."
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"
  CC=clang CXX=clang++ cmake \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_LINKER=lld \
    -DENABLE_LTO=True \
    -DBUILD_TESTING=False \
    -DENABLE_ASSERTIONS=False \
    -G Ninja \
    ..

  log "Building (ninja -j$(nproc))..."
  ninja -j"$(nproc)"

  log "Installing to /usr..."
  ninja install
  chown_vendor_tree

  log "Registering binfmt (systemd-binfmt)..."
  ninja binfmt_misc || {
    warn "ninja binfmt_misc failed — trying systemctl restart systemd-binfmt"
    systemctl restart systemd-binfmt 2>/dev/null || service systemd-binfmt restart 2>/dev/null || true
  }

  # Persist manifest for uninstall
  install -d /usr/local/share/fex-emu
  if [[ -f "${BUILD_DIR}/install_manifest.txt" ]]; then
    cp -f "${BUILD_DIR}/install_manifest.txt" "$MANIFEST_SYS"
    # Ensure binfmt configs are listed
    grep -qxF '/usr/lib/binfmt.d/FEX-x86.conf' "$MANIFEST_SYS" 2>/dev/null \
      || printf '%s\n' '/usr/lib/binfmt.d/FEX-x86.conf' >>"$MANIFEST_SYS"
    grep -qxF '/usr/lib/binfmt.d/FEX-x86_64.conf' "$MANIFEST_SYS" 2>/dev/null \
      || printf '%s\n' '/usr/lib/binfmt.d/FEX-x86_64.conf' >>"$MANIFEST_SYS"
  else
    warn "install_manifest.txt missing after build — uninstall may be incomplete"
  fi

  command -v FEX >/dev/null || die "FEX binary missing after install"
  log "FEX installed: $(command -v FEX)"
  FEX --version 2>/dev/null || true
  cleanup_build_tree
}

# --- RootFS (SquashFS only; newest recommended) ---
fetch_rootfs_menu() {
  local json tmp choice i=0 name url folder
  declare -a NAMES URLS FOLDERS

  ensure_fex_user_data_permissions

  tmp="$(mktemp)"
  log "Fetching RootFS list from ${ROOTFS_JSON_URL}..."
  curl -fsSL "$ROOTFS_JSON_URL" -o "$tmp" \
    || die "Failed to download RootFS list (network?)"

  # Prefer SquashFS entries (extractable); keep JSON order (newest Fedora first)
  mapfile -t NAMES < <(python3 - "$tmp" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["v1"]
for name, meta in d.items():
    t = (meta.get("Type") or "").lower()
    if "squash" in name.lower() or t == "squashfs":
        print(name)
PY
)
  mapfile -t URLS < <(python3 - "$tmp" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["v1"]
for name, meta in d.items():
    t = (meta.get("Type") or "").lower()
    if "squash" in name.lower() or t == "squashfs":
        print(meta["URL"])
PY
)
  rm -f "$tmp"

  ((${#NAMES[@]})) || die "No SquashFS RootFS entries found"

  echo
  echo "RootFS selection (SquashFS — recommended for extract + best compatibility)"
  echo "  Tip: option 1 is usually the newest (best compatibility / performance)."
  echo
  for ((i = 0; i < ${#NAMES[@]}; i++)); do
    printf '  %2d) %s\n' "$((i + 1))" "${NAMES[$i]}"
  done
  echo "   0) Cancel"
  echo

  while true; do
    read -r -p "Select RootFS [1 recommended]: " choice
    [[ -z "$choice" ]] && choice=1
    [[ "$choice" == "0" ]] && { log "Cancelled."; return 1; }
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#NAMES[@]})); then
      break
    fi
    echo "Invalid choice."
  done

  i=$((choice - 1))
  name="${NAMES[$i]}"
  url="${URLS[$i]}"
  folder="$(basename "$url" .sqsh)"
  folder="${folder%.ero}"

  log "Selected: ${name}"
  log "URL: ${url}"

  download_and_extract_rootfs "$url" "$folder"
}

download_and_extract_rootfs() {
  local url="$1" folder="$2"
  local dest_base="${REAL_HOME}/.local/share/fex-emu/RootFS"
  local sqsh="${dest_base}/$(basename "$url")"
  local extract_dir="${dest_base}/${folder}"
  local cfg_dir="${REAL_HOME}/.config/fex-emu"

  ensure_fex_user_data_permissions
  install -d -o "$REAL_UID" -g "$REAL_GID" -m 0755 "$dest_base" "$cfg_dir"

  log "Downloading RootFS as user ${REAL_USER} → ${sqsh}"
  run_as_user curl -fL --progress-bar -o "$sqsh" "$url" \
    || die "Download failed"

  if [[ -d "$extract_dir" ]]; then
    warn "Extract dir already exists: ${extract_dir}"
    if ask_yes_no "Remove and re-extract?" "y"; then
      rm -rf "$extract_dir"
    else
      log "Keeping existing extract; setting as default."
      write_rootfs_config "$folder"
      return 0
    fi
  fi

  log "Extracting SquashFS (unsquashfs) → ${extract_dir}"
  run_as_user mkdir -p "$extract_dir"
  # unsquashfs as the real user into the target dir
  if ! run_as_user unsquashfs -f -d "$extract_dir" "$sqsh"; then
    die "unsquashfs failed — is squashfs-tools installed?"
  fi

  # Ownership fix if any root-owned files slipped in
  chown -R "${REAL_UID}:${REAL_GID}" "$dest_base" "$cfg_dir" 2>/dev/null || true

  write_rootfs_config "$folder"
  log "RootFS '${folder}' set as default for user ${REAL_USER}"
}

write_rootfs_config() {
  local folder="$1"
  local cfg="${REAL_HOME}/.config/fex-emu/Config.json"
  run_as_user mkdir -p "$(dirname "$cfg")"
  run_as_user bash -c "printf '%s\n' '{\"Config\":{\"RootFS\":\"${folder}\"},\"ThunksDB\":{}}' >'${cfg}'"
  chown "${REAL_UID}:${REAL_GID}" "$cfg" 2>/dev/null || true
}

# --- Uninstall ---
uninstall_fex() {
  local manifest="$MANIFEST_SYS" line
  local alt_manifests=(
    "$MANIFEST_SYS"
    "${BUILD_DIR}/install_manifest.txt"
    "${VENDOR_DIR}/install_manifest.txt"
    "/home/odin2/Documents/FEX/build/install_manifest.txt"
  )

  manifest=""
  for m in "${alt_manifests[@]}"; do
    if [[ -f "$m" ]]; then
      manifest="$m"
      break
    fi
  done

  if [[ -z "$manifest" ]]; then
    warn "No install_manifest.txt found."
    if ! ask_yes_no "Remove known FEX binaries/binfmt configs anyway?"; then
      die "Nothing to uninstall."
    fi
    rm -f /usr/bin/FEX /usr/bin/FEXBash /usr/bin/FEXConfig /usr/bin/FEXGetConfig \
      /usr/bin/FEXInterpreter /usr/bin/FEXOfflineCompiler /usr/bin/FEXRootFSFetcher \
      /usr/bin/FEXServer /usr/bin/FEXpidof \
      /usr/lib/binfmt.d/FEX-x86.conf /usr/lib/binfmt.d/FEX-x86_64.conf \
      /usr/lib/aarch64-linux-gnu/libFEXCore.so 2>/dev/null || true
    rm -rf /usr/include/FEXCore /usr/share/fex-emu /usr/local/share/fex-emu 2>/dev/null || true
  else
    log "Removing files from manifest: ${manifest}"
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      # Manifest paths are absolute (/usr/...)
      if [[ -e "$line" || -L "$line" ]]; then
        rm -rf "$line"
      fi
    done <"$manifest"
  fi

  # binfmt cleanup + reload
  rm -f /usr/lib/binfmt.d/FEX-x86.conf /usr/lib/binfmt.d/FEX-x86_64.conf \
    /etc/binfmt.d/FEX-x86.conf /etc/binfmt.d/FEX-x86_64.conf 2>/dev/null || true
  log "Restarting systemd-binfmt..."
  systemctl restart systemd-binfmt 2>/dev/null || service systemd-binfmt restart 2>/dev/null || true

  rm -f "$MANIFEST_SYS" 2>/dev/null || true

  if [[ -d "$VENDOR_DIR" ]]; then
    log "Removing leftover FEX source tree: ${VENDOR_DIR}"
    rm -rf "$VENDOR_DIR"
  fi
  if [[ -d "${REAL_HOME}/src" ]] && [[ -z "$(ls -A "${REAL_HOME}/src" 2>/dev/null)" ]]; then
    rmdir "${REAL_HOME}/src" 2>/dev/null || true
  fi

  echo
  if ask_yes_no "Also delete user RootFS and config (${REAL_HOME}/.config/fex-emu and ${REAL_HOME}/.local/share/fex-emu)?"; then
    rm -rf "${REAL_HOME}/.config/fex-emu" "${REAL_HOME}/.local/share/fex-emu"
    log "Removed user FEX data for ${REAL_USER}"
  else
    log "Kept user FEX data under ${REAL_HOME}"
  fi

  log "FEXEmu uninstall finished."
}

do_install() {
  ensure_man_cache_permissions
  ensure_fex_user_data_permissions
  steam_fex_status

  if box64_detected; then
    warn "BOX64 appears to be installed."
    warn "BOX64 and FEX both register x86/x86_64 binfmt handlers and will conflict."
    if ! ask_yes_no "Continue installing FEXEmu anyway?"; then
      log "Aborted."
      exit 0
    fi
  fi

  build_and_install_fex
  echo
  log "FEX binaries installed. Next: choose a RootFS (x86_64 guest userspace)."
  fetch_rootfs_menu || true
  _decky_fix="${_SCRIPT_DIR}/apply-decky-plugin-loader-fix.sh"
  if [[ -x "$_decky_fix" ]]; then
    log "Decky PluginLoader: install FEX RootFS systemd drop-in (aarch64)"
    "$_decky_fix" / || warn "Decky drop-in install failed (install Decky first?)"
  fi
  echo
  log "Done. Test with: FEX /path/to/x86_64-binary"
}

do_update() {
  if ! fex_installed && [[ ! -d "${SRC_DIR}/.git" ]]; then
    die "FEX does not look installed and no source tree found. Use: install"
  fi
  if box64_detected; then
    warn "BOX64 is also present — binfmt conflict possible after update."
  fi

  build_and_install_fex
  echo
  log "Update complete. Your RootFS was left intact."
  log "If you want a newer/alternative RootFS, run as your user:"
  log "  FEXRootFSFetcher"
  log "Or re-run: sudo $0 install   (will offer RootFS selection again)"
}

main_menu() {
  local choice
  echo
  echo "FEXEmu manager"
  echo "  1) Install   (build + binfmt + RootFS download)"
  echo "  2) Update    (rebuild FEX only; keep RootFS)"
  echo "  3) Uninstall (remove FEX + optional user data)"
  echo "  0) Quit"
  echo
  read -r -p "Choice: " choice
  case "$choice" in
    1) do_install ;;
    2) do_update ;;
    3) uninstall_fex ;;
    0|"") log "Bye."; exit 0 ;;
    *) die "Unknown choice: $choice" ;;
  esac
}

# --- entry ---
# (root elevation happens at the top via exec sudo)
[[ "$(uname -m)" == "aarch64" ]] || die "FEXEmu targets aarch64 hosts"
log "Source/build under ${VENDOR_DIR} (user ${REAL_USER})"

ACTION="${1:-}"
case "$ACTION" in
  install)   do_install ;;
  update)    do_update ;;
  uninstall|remove) uninstall_fex ;;
  ""|-i|--interactive) main_menu ;;
  -h|--help)
    cat <<EOF
Usage: $0 [install|update|uninstall]

  Asks for sudo password if not already root.

  install     Build FEX, register binfmt, download+extract RootFS (interactive pick)
  update      Rebuild/reinstall FEX only; leave RootFS untouched
  uninstall   Remove FEX files (manifest) + binfmt; optional wipe of user data
  (no args)   Interactive menu

Source tree: ${SRC_DIR}  (removed after successful install/update on device)
User data:   ${REAL_HOME}/.config/fex-emu  ${REAL_HOME}/.local/share/fex-emu
EOF
    exit 0
    ;;
  *) die "Unknown argument: $ACTION (try --help)" ;;
esac
