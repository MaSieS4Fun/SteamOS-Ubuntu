#!/usr/bin/env bash
# Shared helpers for Xenia Canary / Xenia Edge installers.
#
# Neither project ships a useful cmake --install on Linux. We build with the
# upstream ./xb script, then install binary + desktop + icon under /usr/local
# (same idea as a manual packaging step) and keep a manifest for uninstall.

masi_xenia_find_binary() {
  local src_dir="$1"
  local bin_name="$2"
  local cand
  for cand in \
    "${src_dir}/build/bin/Linux/Release/${bin_name}" \
    "${src_dir}/build/bin/linux/Release/${bin_name}" \
    "${src_dir}/build/bin/Linux/release/${bin_name}"
  do
    if [[ -x "$cand" ]]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  cand="$(find "${src_dir}/build" -type f -name "$bin_name" -perm -111 2>/dev/null | head -n1 || true)"
  [[ -n "$cand" ]] || return 1
  printf '%s\n' "$cand"
}

# Install binary + FreeDesktop entry + PNG icon; write uninstall manifest.
# Args: app_id bin_name display_name comment binary_src desktop_src icon_src
masi_xenia_system_install() {
  local app_id="$1"
  local bin_name="$2"
  local display_name="$3"
  local comment="$4"
  local binary_src="$5"
  local desktop_src="$6"
  local icon_src="$7"
  local prefix="${MASI_PREFIX:-/usr/local}"

  local bin_dst="${prefix}/bin/${bin_name}"
  local desktop_dst="${prefix}/share/applications/${bin_name}.desktop"
  local icon_dst="${prefix}/share/icons/hicolor/256x256/apps/${bin_name}.png"
  local manifest="${MASI_MANIFESTS}/${app_id}.txt"

  [[ -x "$binary_src" ]] || masi_die "Missing built binary: $binary_src"
  [[ -f "$icon_src" ]] || masi_die "Missing icon: $icon_src"

  masi_ensure_sudo
  masi_log "Installing ${binary_src} -> ${bin_dst}"
  masi_sudo install -Dm755 "$binary_src" "$bin_dst"

  masi_log "Installing icon -> ${icon_dst}"
  masi_sudo install -Dm644 "$icon_src" "$icon_dst"

  masi_log "Installing desktop entry -> ${desktop_dst}"
  if [[ -f "$desktop_src" ]]; then
    masi_sudo install -Dm644 "$desktop_src" "$desktop_dst"
    masi_sudo sed -i \
      -e "s|^Exec=.*|Exec=${bin_dst} %f|" \
      -e "s|^Icon=.*|Icon=${bin_name}|" \
      -e '/^TryExec=/d' \
      "$desktop_dst"
  else
    masi_sudo tee "$desktop_dst" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=${display_name}
GenericName=Xbox 360 Emulator
Comment=${comment}
Exec=${bin_dst} %f
Icon=${bin_name}
Terminal=false
Categories=Game;Emulator;
MimeType=application/x-xbox360-executable;application/x-xbox360-iso;
StartupNotify=true
StartupWMClass=${bin_name}
EOF
    masi_sudo chmod 644 "$desktop_dst"
  fi

  mkdir -p "$MASI_MANIFESTS"
  printf '%s\n' "$bin_dst" "$desktop_dst" "$icon_dst" >"$manifest"
  chmod 644 "$manifest"
  masi_log "Saved install manifest: $manifest"

  masi_refresh_desktop_and_icons "${prefix}/share"
}

masi_xenia_run_xb() {
  local src_dir="$1"
  shift
  (
    cd "$src_dir"
    export CC="${CC:-clang}"
    export CXX="${CXX:-clang++}"
    chmod +x ./xb ./xenia-build.py 2>/dev/null || true
    ./xb "$@"
  )
}
