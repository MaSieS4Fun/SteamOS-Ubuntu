#!/usr/bin/env bash
# Install / uninstall ARMSX2 via official Linux arm64 AppImage.
#
# Compiling ARMSX2 is heavy (builds its own dependency tree). Nightly AppImages
# are preferred. Pick 4K vs 16K page-size build via getconf PAGESIZE.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

APP_ID="armsx2"
APP_NAME="ARMSX2"
RELEASES_API="https://api.github.com/repos/ARMSX2/ARMSX2/releases?per_page=20"
ICON_URL="https://raw.githubusercontent.com/ARMSX2/ARMSX2/master/bin/resources/icons/AppIconLarge.png"

APPIMAGE_PATH="${MASI_APPLICATIONS}/ARMSX2.AppImage"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
ICON_PATH="${ICON_DIR}/ARMSX2.png"
DESKTOP_PATH="${MASI_DESKTOP}/ARMSX2.desktop"
LAUNCHER_PATH="${MASI_BIN}/armsx2"

RUNTIME_DEPS=(
  ca-certificates curl libfuse2t64 fuse3
)

resolve_appimage_url() {
  local pagesize tag
  pagesize="$(getconf PAGESIZE 2>/dev/null || echo 4096)"
  case "$pagesize" in
    16384) tag="16K-pages" ;;
    65536) masi_die "Kernel page size ${pagesize} is not covered by ARMSX2 AppImages (need 4K or 16K)." ;;
    *) tag="4K-pages" ;;
  esac
  masi_log "Kernel page size: ${pagesize} -> selecting ${tag} AppImage"

  python3 - "$RELEASES_API" "$tag" <<'PY'
import json, sys, urllib.request
api, want = sys.argv[1], sys.argv[2]
req = urllib.request.Request(api, headers={"Accept": "application/vnd.github+json", "User-Agent": "EmuKitARM"})
with urllib.request.urlopen(req, timeout=60) as r:
    releases = json.load(r)
for rel in releases:
    for asset in rel.get("assets", []):
        name = asset.get("name", "")
        if (
            name.endswith(".AppImage")
            and "Linux-arm64" in name
            and want in name
        ):
            print(asset["browser_download_url"])
            print(name, file=sys.stderr)
            print(rel.get("tag_name", ""), file=sys.stderr)
            sys.exit(0)
sys.stderr.write(f"No Linux-arm64 {want} AppImage found in recent releases.\n")
sys.exit(1)
PY
}

write_desktop_entry() {
  cat >"$DESKTOP_PATH" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Name=ARMSX2
StartupWMClass=ARMSX2
GenericName=PlayStation 2 Emulator
Comment=Sony PlayStation 2 emulator (ARM64)
Exec=${APPIMAGE_PATH} %f
Icon=ARMSX2
Keywords=game;emulator;PS2;PlayStation;
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
  # Convenience alias matching upstream desktop Exec name.
  rm -f "${MASI_BIN}/armsx2-qt"
  ln -sfn "$LAUNCHER_PATH" "${MASI_BIN}/armsx2-qt"

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
  rm -f "$APPIMAGE_PATH" "$LAUNCHER_PATH" "${MASI_BIN}/armsx2-qt" "$DESKTOP_PATH" "$ICON_PATH"
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
  masi_log "Source builds are skipped (ARMSX2 rebuilds its own libraries; AppImage is preferred)."
  masi_apt_install "${RUNTIME_DEPS[@]}"

  masi_prepare_build "$APP_ID"
  local appimage_dl="${MASI_WORK}/ARMSX2.AppImage"
  local icon_dl="${MASI_WORK}/ARMSX2.png"
  local url

  url="$(resolve_appimage_url)"
  masi_log "Downloading ${url}..."
  curl -fL --connect-timeout 30 --max-time 600 --retry 3 --retry-delay 2 \
    -o "$appimage_dl" "$url"
  chmod +x "$appimage_dl"

  masi_log "Downloading icon..."
  curl -fL --connect-timeout 20 --max-time 120 --retry 3 --retry-delay 2 \
    -o "$icon_dl" "$ICON_URL" \
    || {
      masi_log "Icon download failed; extracting from AppImage..."
      local extract_dir="${MASI_WORK}/extract"
      mkdir -p "$extract_dir"
      (
        cd "$extract_dir"
        export APPIMAGE_EXTRACT_AND_RUN=1
        "$appimage_dl" --appimage-extract >/dev/null 2>&1 || true
      )
      local found
      found="$(find "$extract_dir" -type f \( -iname '*AppIcon*.png' -o -iname '*armsx2*.png' -o -iname '*pcsx2*.png' \) | head -n1 || true)"
      [[ -n "$found" ]] || masi_die "Could not obtain an ARMSX2 icon"
      cp -a "$found" "$icon_dl"
    }

  install_files "$appimage_dl" "$icon_dl"

  masi_log "Removing download leftovers..."
  rm -rf "$MASI_WORK"
  MASI_WORK=""

  masi_log "=== ${APP_NAME} installed successfully ==="
  masi_log "AppImage: ${APPIMAGE_PATH}"
  masi_log "Command:  armsx2"
  masi_log "Desktop:  ${DESKTOP_PATH}"
  masi_appimage_steam_warning "$APP_NAME"
}

case "${1:-}" in
  --uninstall|uninstall|remove) do_uninstall ;;
  *) do_install ;;
esac
