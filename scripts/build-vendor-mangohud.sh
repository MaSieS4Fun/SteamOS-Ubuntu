#!/usr/bin/env bash
# Build SM8550-adapted MangoHud (+ mangoapp) from vendor/MangoHud into rootfs.
# Usage: build-vendor-mangohud.sh <rootfs>
#
# mangoapp is required for Steam Deck "Performance overlay level" (Interfaz de rendimiento).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
SRC="${ROOT_DIR}/vendor/MangoHud"
BUILD_DIR="${MANGOHUD_BUILD_DIR:-${ROOT_DIR}/output/work/mangohud-build}"
JOBS="${JOBS:-$(nproc)}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"

log() { printf '==> [mangohud] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ -f "${SRC}/meson.build" ]] || die "Missing vendor/MangoHud"

need_cmd() { command -v "$1" >/dev/null || die "Missing tool: $1"; }
need_cmd meson
need_cmd ninja
need_cmd git
need_cmd pkg-config
pkg-config --exists glfw3 || die "Need libglfw3-dev (mangoapp)"
pkg-config --exists dbus-1 || die "Need libdbus-1-dev (mangoapp)"
pkg-config --exists x11 || die "Need libx11-dev (mangoapp)"

(
  cd "$SRC"
  git submodule update --init --recursive 2>/dev/null || true
)

mkdir -p "$(dirname "$BUILD_DIR")"

# Rebuild if mangoapp was never enabled in this build dir
if [[ -f "${BUILD_DIR}/meson-info/intro-buildoptions.json" ]] \
  && ! grep -q '"name": "mangoapp"[^}]*"value": true' "${BUILD_DIR}/meson-info/intro-buildoptions.json" 2>/dev/null; then
  log "Existing meson setup lacks mangoapp=true — forcing reconfigure"
  FORCE_REBUILD=1
fi
if [[ "$FORCE_REBUILD" == "1" ]]; then
  log "FORCE_REBUILD=1 — wiping ${BUILD_DIR}"
  rm -rf "$BUILD_DIR"
fi

MESON_OPTS=(
  --prefix=/usr
  --libdir=lib/mangohud/lib64
  --buildtype=release
  -Dappend_libdir_mangohud=false
  -Dwith_xnvctrl=disabled
  -Dwith_x11=enabled
  -Dmangoapp=true
  -Dmangohudctl=true
)

log "Meson setup → ${BUILD_DIR} (mangoapp=true)"
if [[ ! -f "${BUILD_DIR}/build.ninja" ]]; then
  meson setup "$BUILD_DIR" "$SRC" "${MESON_OPTS[@]}"
else
  meson setup --reconfigure "$BUILD_DIR" "$SRC" "${MESON_OPTS[@]}" || true
fi

log "Compiling vendor MangoHud + mangoapp"
meson compile -C "$BUILD_DIR" -j "$JOBS"

log "Installing MangoHud + mangoapp into rootfs"
DESTDIR="$ROOTFS" meson install -C "$BUILD_DIR" --no-rebuild

[[ -x "${ROOTFS}/usr/bin/mangoapp" ]] \
  || die "mangoapp missing after install — check glfw3/dbus/x11 deps and -Dmangoapp=true"

# Second binary for Gaming Mode (gamescope-session): defaults to ~/.config/MangoHud/steam/
# Same build; basename mangoapp-steam selects the steam config subdir (see config.cpp).
# Desktop / Lutris keep using /usr/bin/mangoapp → ~/.config/MangoHud/
install -D -m 0755 "${ROOTFS}/usr/bin/mangoapp" "${ROOTFS}/usr/bin/mangoapp-steam"
if [[ -x "${ROOTFS}/usr/bin/mangohud" ]]; then
  # Wrapper so LD_PRELOAD games get the steam profile via env (exe name is the game).
  cat >"${ROOTFS}/usr/bin/mangohud-steam" <<'EOF'
#!/bin/sh
# Same as mangohud, but default conf/presets under ~/.config/MangoHud/steam/
export MANGOHUD_PROFILE=steam
exec mangohud "$@"
EOF
  chmod 0755 "${ROOTFS}/usr/bin/mangohud-steam"
fi
log "Installed dual overlay binaries: mangoapp (desktop) + mangoapp-steam (gaming session)"

# Overlay configs (after steam user exists): copy vendor tree as-is — no edits.
# Source: vendor/MangoHud/MangoHud/ → ~/.config/MangoHud/
#   ~/.config/MangoHud/          → desktop / Lutris / Goverlay (mangoapp)
#   ~/.config/MangoHud/steam/    → gamescope session (mangoapp-steam)
PRESETS="${SRC}/MangoHud"
if [[ -d "$PRESETS" ]]; then
  install -d "${ROOTFS}/etc/skel/.config/MangoHud"
  cp -a "${PRESETS}/." "${ROOTFS}/etc/skel/.config/MangoHud/"
  install -d "${ROOTFS}/usr/share/sm8550-steamos/MangoHud"
  cp -a "${PRESETS}/." "${ROOTFS}/usr/share/sm8550-steamos/MangoHud/"
  if [[ -d "${ROOTFS}/home/steam" ]]; then
    install -d "${ROOTFS}/home/steam/.config/MangoHud"
    cp -a "${PRESETS}/." "${ROOTFS}/home/steam/.config/MangoHud/"
    chown -R --reference="${ROOTFS}/home/steam" "${ROOTFS}/home/steam/.config/MangoHud" 2>/dev/null \
      || chown -R 1000:1000 "${ROOTFS}/home/steam/.config/MangoHud" 2>/dev/null || true
    log "Copied overlay configs → /home/steam/.config/MangoHud/"
  else
    log "WARN: /home/steam missing — configs only in etc/skel + /usr/share/sm8550-steamos/MangoHud"
  fi
else
  log "WARN: missing ${PRESETS} — no user overlay configs copied"
fi

log "Vendor MangoHud + mangoapp + mangoapp-steam installed"
