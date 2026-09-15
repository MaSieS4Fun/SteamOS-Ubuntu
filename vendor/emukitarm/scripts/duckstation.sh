#!/usr/bin/env bash
# Install / uninstall DuckStation via the official ARM64 AppImage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="duckstation"
APP_NAME="DuckStation"
APPIMAGE_URL="https://github.com/stenzek/duckstation/releases/download/latest/DuckStation-arm64.AppImage"

APPIMAGE_PATH="${MASI_APPLICATIONS}/DuckStation.AppImage"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/512x512/apps"
ICON_PATH="${ICON_DIR}/org.duckstation.DuckStation.png"
DESKTOP_PATH="${MASI_DESKTOP}/org.duckstation.DuckStation.desktop"
LAUNCHER_PATH="${MASI_BIN}/duckstation"

RUNTIME_DEPS=(
  ca-certificates curl libfuse2t64 fuse3
)

cleanup_legacy_masiscript_install() {
  local legacy="${XDG_DATA_HOME:-$HOME/.local/share}/masiscript/apps/duckstation"
  if [[ -e "$legacy" ]]; then
    masi_log "Removing legacy MasiScript app dir: $legacy"
    rm -rf "$legacy"
  fi
  rm -f "${MASI_DESKTOP}/duckstation.desktop"
}

extract_icon_from_appimage() {
  local appimage="$1"
  local dest="$2"
  local extract_dir="${MASI_WORK}/appimage-extract"

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"

  masi_log "Extracting official icon from AppImage..."
  (
    cd "$extract_dir"
    export APPIMAGE_EXTRACT_AND_RUN=1
    if ! "$appimage" --appimage-extract \
      'usr/share/icons/hicolor/512x512/apps/org.duckstation.DuckStation.png' \
      >/dev/null 2>&1; then
      "$appimage" --appimage-extract >/dev/null
    fi
  )

  local found
  found="$(find "$extract_dir" -type f \( \
    -name 'org.duckstation.DuckStation.png' -o \
    -name 'duckstation.png' -o \
    -path '*/hicolor/512x512/apps/*.png' \
  \) | head -n1 || true)"

  if [[ -z "$found" ]]; then
    found="$(find "$extract_dir/squashfs-root" -type f -name '*.png' \
      \( -path '*/icons/*' -o -path '*/apps/*' -o -name 'DuckStation.png' \) \
      | head -n1 || true)"
  fi

  [[ -n "$found" && -f "$found" ]] || masi_die "Could not find DuckStation icon inside the AppImage"
  mkdir -p "$(dirname "$dest")"
  cp -a "$found" "$dest"
  masi_log "Icon installed from AppImage: $dest"
}

write_desktop_entry() {
  cat >"$DESKTOP_PATH" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=DuckStation
GenericName=PlayStation 1 Emulator
Comment=Fast PlayStation 1 emulator
Exec=${APPIMAGE_PATH} %f
Icon=org.duckstation.DuckStation
Terminal=false
Categories=Game;Emulator;Qt;
Keywords=PS1;PSX;PlayStation;DuckStation;
StartupNotify=true
EOF
  chmod 644 "$DESKTOP_PATH"
}

install_files() {
  local appimage_src="$1"

  mkdir -p "$MASI_APPLICATIONS" "$MASI_BIN" "$ICON_DIR" "$MASI_DESKTOP"

  masi_log "Installing AppImage to ${APPIMAGE_PATH}"
  cp -a "$appimage_src" "$APPIMAGE_PATH"
  chmod +x "$APPIMAGE_PATH"

  extract_icon_from_appimage "$appimage_src" "$ICON_PATH"

  rm -f "$LAUNCHER_PATH"
  cat >"$LAUNCHER_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "${APPIMAGE_PATH}" "\$@"
EOF
  chmod +x "$LAUNCHER_PATH"

  write_desktop_entry

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$MASI_DESKTOP" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" >/dev/null 2>&1 || true
  fi
}

do_uninstall() {
  masi_log "=== Uninstalling ${APP_NAME} ==="
  cleanup_legacy_masiscript_install
  rm -f "$APPIMAGE_PATH" "$LAUNCHER_PATH" "$DESKTOP_PATH" "$ICON_PATH"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$MASI_DESKTOP" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" >/dev/null 2>&1 || true
  fi
  masi_log "=== ${APP_NAME} removed ==="
}

do_install() {
  masi_require_aarch64
  masi_log "=== Installing ${APP_NAME} (official AppImage) ==="
  masi_log "Source builds are not used for DuckStation on aarch64 (no practical make install)."
  masi_apt_install "${RUNTIME_DEPS[@]}"

  cleanup_legacy_masiscript_install

  masi_prepare_build "$APP_ID"
  local appimage_dl="${MASI_WORK}/DuckStation-arm64.AppImage"

  masi_log "Downloading AppImage..."
  curl -fL --connect-timeout 30 --max-time 600 --retry 3 --retry-delay 2 \
    -o "$appimage_dl" "$APPIMAGE_URL"
  chmod +x "$appimage_dl"

  install_files "$appimage_dl"

  masi_log "Removing download leftovers..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "AppImage: ${APPIMAGE_PATH}"
  masi_log "Command:  duckstation"
  masi_log "Desktop:  ${DESKTOP_PATH}"
  masi_log "Icon:     ${ICON_PATH}"
  masi_appimage_steam_warning "$APP_NAME"
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
