#!/usr/bin/env bash
# Install / uninstall RPCS3 via official Linux aarch64 AppImage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="rpcs3"
APP_NAME="RPCS3"
RELEASES_API="https://api.github.com/repos/RPCS3/rpcs3-binaries-linux-arm64/releases/latest"
ICON_URL="https://rpcs3.net/cdn/branding/core-color-png.png"

APPIMAGE_PATH="${MASI_APPLICATIONS}/RPCS3.AppImage"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
ICON_PATH="${ICON_DIR}/rpcs3.png"
DESKTOP_PATH="${MASI_DESKTOP}/rpcs3.desktop"
LAUNCHER_PATH="${MASI_BIN}/rpcs3"

RUNTIME_DEPS=(
  ca-certificates curl libfuse2t64 fuse3
)

resolve_appimage_url() {
  python3 - "$RELEASES_API" <<'PY'
import json, sys, urllib.request
api = sys.argv[1]
req = urllib.request.Request(api, headers={"Accept": "application/vnd.github+json", "User-Agent": "EmuKitARM"})
with urllib.request.urlopen(req, timeout=60) as r:
    rel = json.load(r)
for asset in rel.get("assets", []):
    name = asset.get("name", "")
    if name.endswith(".AppImage") and ("aarch64" in name or "arm64" in name):
        print(asset["browser_download_url"])
        print(name, file=sys.stderr)
        print(rel.get("tag_name", ""), file=sys.stderr)
        sys.exit(0)
sys.stderr.write("No linux aarch64 AppImage found in latest RPCS3 release.\n")
sys.exit(1)
PY
}

extract_icon_from_appimage() {
  local appimage="$1"
  local dest="$2"
  local extract_dir="${MASI_WORK}/appimage-extract"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  masi_log "Extracting icon from AppImage..."
  (
    cd "$extract_dir"
    export APPIMAGE_EXTRACT_AND_RUN=1
    "$appimage" --appimage-extract >/dev/null 2>&1 || true
  )
  local found
  found="$(find "$extract_dir" -type f \( \
    -iname 'rpcs3.png' -o -iname 'rpcs3.svg' -o \
    -path '*/hicolor/*/apps/rpcs3.png' \
  \) | head -n1 || true)"
  if [[ -n "$found" && -f "$found" ]]; then
    mkdir -p "$(dirname "$dest")"
    if [[ "$found" == *.svg ]]; then
      # Prefer PNG for menu themes; fall back to downloading branding if only SVG.
      return 1
    fi
    cp -a "$found" "$dest"
    return 0
  fi
  return 1
}

write_desktop_entry() {
  cat >"$DESKTOP_PATH" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Name=RPCS3
StartupWMClass=rpcs3
GenericName=PlayStation 3 Emulator
Comment=Sony PlayStation 3 emulator
Exec=${APPIMAGE_PATH} %f
Icon=rpcs3
Keywords=game;emulator;PS3;PlayStation;
Categories=Game;Emulator;
StartupNotify=true
EOF
  chmod 644 "$DESKTOP_PATH"
}

install_files() {
  local appimage_src="$1"
  local icon_src="$2"

  mkdir -p "$MASI_APPLICATIONS" "$MASI_BIN" "$ICON_DIR" "$MASI_DESKTOP"

  masi_log "Installing AppImage to ${APPIMAGE_PATH}"
  cp -a "$appimage_src" "$APPIMAGE_PATH"
  chmod +x "$APPIMAGE_PATH"

  masi_log "Installing icon to ${ICON_PATH}"
  cp -a "$icon_src" "$ICON_PATH"

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
  masi_log "=== Installing ${APP_NAME} (official aarch64 AppImage) ==="
  masi_apt_install "${RUNTIME_DEPS[@]}"

  masi_prepare_build "$APP_ID"
  local appimage_dl="${MASI_WORK}/RPCS3.AppImage"
  local icon_dl="${MASI_WORK}/rpcs3.png"
  local url

  url="$(resolve_appimage_url)"
  masi_log "Downloading ${url}..."
  curl -fL --connect-timeout 30 --max-time 900 --retry 3 --retry-delay 2 \
    -o "$appimage_dl" "$url"
  chmod +x "$appimage_dl"

  masi_log "Downloading icon..."
  if ! curl -fL --connect-timeout 20 --max-time 120 --retry 3 --retry-delay 2 \
    -o "$icon_dl" "$ICON_URL"; then
    extract_icon_from_appimage "$appimage_dl" "$icon_dl" \
      || masi_die "Could not obtain an RPCS3 icon"
  fi

  install_files "$appimage_dl" "$icon_dl"

  masi_log "Removing download leftovers..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "AppImage: ${APPIMAGE_PATH}"
  masi_log "Command:  rpcs3"
  masi_log "Desktop:  ${DESKTOP_PATH}"
  masi_appimage_steam_warning "$APP_NAME"
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
