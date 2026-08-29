#!/usr/bin/env bash
# Recursively resolve ALL shared libs for gamescope via readelf (no ldd —
# mixing Ubuntu Resolute rootfs libs into host LD_LIBRARY_PATH causes SIGBUS).
#
# Usage:
#   sudo ./scripts/ensure-gamescope-libs.sh <rootfs> [gamescope-bin] [--check-only]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
CHECK_ONLY=0
GS=""

shift || true
for arg in "${@:-}"; do
  case "$arg" in
    --check-only) CHECK_ONLY=1 ;;
    '') ;;
    *) GS="$arg" ;;
  esac
done

log() { printf '==> [gamescope-libs] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs> [gamescope-bin] [--check-only]"

if [[ -z "$GS" ]]; then
  for c in "${ROOTFS}/usr/local/bin/gamescope" "${ROOTFS}/usr/bin/gamescope"; do
    [[ -x "$c" ]] && GS="$c" && break
  done
fi
[[ -n "$GS" && -x "$GS" ]] || die "gamescope binary not found under ${ROOTFS}"
command -v readelf >/dev/null || die "need readelf"

LIBDIRS=(
  "${ROOTFS}/usr/local/lib/aarch64-linux-gnu"
  "${ROOTFS}/usr/local/lib"
  "${ROOTFS}/usr/lib/aarch64-linux-gnu"
  "${ROOTFS}/lib/aarch64-linux-gnu"
  "${ROOTFS}/usr/lib"
  "${ROOTFS}/lib"
  "${ROOTFS}/usr/lib/aarch64-linux-gnu/pulseaudio"
  "${ROOTFS}/lib/aarch64-linux-gnu/pulseaudio"
)

HOST_LIBDIRS=(
  /usr/local/lib/aarch64-linux-gnu
  /usr/local/lib
  /usr/lib/aarch64-linux-gnu
  /lib/aarch64-linux-gnu
  /usr/lib
  /lib
  /usr/lib/aarch64-linux-gnu/pulseaudio
  /lib/aarch64-linux-gnu/pulseaudio
)

soname_to_pkg() {
  case "$1" in
    libwayland-client.so.0) echo libwayland-client0 ;;
    libwayland-server.so.0) echo libwayland-server0 ;;
    libwayland-cursor.so.0) echo libwayland-cursor0 ;;
    libwayland-egl.so.1) echo libwayland-egl1 ;;
    libX11.so.6) echo libx11-6 ;;
    libX11-xcb.so.1) echo libx11-xcb1 ;;
    libXdamage.so.1) echo libxdamage1 ;;
    libXfixes.so.3) echo libxfixes3 ;;
    libXcomposite.so.1) echo libxcomposite1 ;;
    libXrender.so.1) echo libxrender1 ;;
    libXext.so.6) echo libxext6 ;;
    libXxf86vm.so.1) echo libxxf86vm1 ;;
    libXRes.so.1) echo libxres1 ;;
    libXrandr.so.2) echo libxrandr2 ;;
    libXss.so.1) echo libxss1 ;;
    libXcursor.so.1) echo libxcursor1 ;;
    libXi.so.6) echo libxi6 ;;
    libXtst.so.6) echo libxtst6 ;;
    libXmu.so.6) echo libxmu6 ;;
    libXt.so.6) echo libxt6 ;;
    libXau.so.6) echo libxau6 ;;
    libXdmcp.so.6) echo libxdmcp6 ;;
    libxcb.so.1) echo libxcb1 ;;
    libxcb-render.so.0) echo libxcb-render0 ;;
    libxcb-render-util.so.0) echo libxcb-render-util0 ;;
    libxcb-shm.so.0) echo libxcb-shm0 ;;
    libxcb-xfixes.so.0) echo libxcb-xfixes0 ;;
    libxcb-randr.so.0) echo libxcb-randr0 ;;
    libxcb-shape.so.0) echo libxcb-shape0 ;;
    libxcb-sync.so.1) echo libxcb-sync1 ;;
    libxcb-present.so.0) echo libxcb-present0 ;;
    libxcb-dri3.so.0) echo libxcb-dri3-0 ;;
    libxcb-dri2.so.0) echo libxcb-dri2-0 ;;
    libxcb-glx.so.0) echo libxcb-glx0 ;;
    libxcb-icccm.so.4) echo libxcb-icccm4 ;;
    libxcb-image.so.0) echo libxcb-image0 ;;
    libxcb-keysyms.so.1) echo libxcb-keysyms1 ;;
    libxcb-util.so.1) echo libxcb-util1 ;;
    libxcb-cursor.so.0) echo libxcb-cursor0 ;;
    libxcb-res.so.0) echo libxcb-res0 ;;
    libxcb-errors.so.0) echo libxcb-errors0 ;;
    libxcb-xinput.so.0) echo libxcb-xinput0 ;;
    libxcb-composite.so.0) echo libxcb-composite0 ;;
    libxcb-ewmh.so.2) echo libxcb-ewmh2 ;;
    libdrm.so.2) echo libdrm2 ;;
    libgbm.so.1) echo libgbm1 ;;
    libxkbcommon.so.0) echo libxkbcommon0 ;;
    libxkbcommon-x11.so.0) echo libxkbcommon-x11-0 ;;
    libSDL2-2.0.so.0) echo libsdl2-2.0-0 ;;
    libpixman-1.so.0) echo libpixman-1-0 ;;
    libudev.so.1) echo libudev1 ;;
    libseat.so.1) echo libseat1 ;;
    libinput.so.10) echo libinput10 ;;
    libcap.so.2) echo libcap2 ;;
    libpipewire-0.3.so.0) echo libpipewire-0.3-0 ;;
    libdisplay-info.so.2) echo libdisplay-info2 ;;
    libavif.so.16) echo libavif16 ;;
    libdecor-0.so.0) echo libdecor-0-0 ;;
    libeis.so.1) echo libeis1 ;;
    libluajit-5.1.so.2) echo libluajit-5.1-2 ;;
    libliftoff.so.0|libliftoff.so.*) echo libliftoff0 ;;
    libstdc++.so.6) echo libstdc++6 ;;
    libgcc_s.so.1) echo libgcc-s1 ;;
    libm.so.6|libc.so.6|libmvec.so.1) echo libc6 ;;
    libffi.so.8) echo libffi8 ;;
    libasound.so.2) echo libasound2t64 ;;
    libpulse.so.0) echo libpulse0 ;;
    libpulsecommon-*.so|libpulsecommon-*) echo libpulse0 ;;
    libsamplerate.so.0) echo libsamplerate0 ;;
    libsystemd.so.0) echo libsystemd0 ;;
    libmtdev.so.1) echo libmtdev1 ;;
    libevdev.so.2) echo libevdev2 ;;
    libwacom.so.9) echo libwacom9 ;;
    libyuv.so.0) echo libyuv0 ;;
    libdav1d.so.7) echo libdav1d7 ;;
    libgav1.so.1) echo libgav1-1 ;;
    librav1e.so.0.7) echo librav1e0.7 ;;
    libSvtAv1Enc.so.2) echo libsvtav1enc2 ;;
    libaom.so.3) echo libaom3 ;;
    libdbus-1.so.3) echo libdbus-1-3 ;;
    libexpat.so.1) echo libexpat1 ;;
    libgudev-1.0.so.0) echo libgudev-1.0-0 ;;
    libgobject-2.0.so.0) echo libgobject-2.0-0 ;;
    libglib-2.0.so.0) echo libglib2.0-0t64 ;;
    libSM.so.6) echo libsm6 ;;
    libICE.so.6) echo libice6 ;;
    libjpeg.so.62) echo libjpeg62-turbo ;;
    libsndfile.so.1) echo libsndfile1 ;;
    libasyncns.so.0) echo libasyncns0 ;;
    libatomic.so.1) echo libatomic1 ;;
    libpcre2-8.so.0) echo libpcre2-8-0 ;;
    libuuid.so.1) echo libuuid1 ;;
    libFLAC.so.14) echo libflac14 ;;
    libvorbis.so.0) echo libvorbis0a ;;
    libvorbisenc.so.2) echo libvorbisenc2 ;;
    libopus.so.0) echo libopus0 ;;
    libogg.so.0) echo libogg0 ;;
    libmpg123.so.0) echo libmpg123-0t64 ;;
    libmp3lame.so.0) echo libmp3lame0 ;;
    libvulkan.so.1) echo libvulkan1 ;;
    libEGL.so.1) echo libegl1 ;;
    libGLESv2.so.2) echo libgles2 ;;
    libGLdispatch.so.0) echo libglvnd0 ;;
    libOpenGL.so.0) echo libopengl0 ;;
    libz.so.1) echo zlib1g ;;
    libzstd.so.1) echo libzstd1 ;;
    liblzma.so.5) echo liblzma5 ;;
    libbz2.so.1.0) echo libbz2-1.0 ;;
    libpng16.so.16) echo libpng16-16t64 ;;
    libbrotlidec.so.1|libbrotlicommon.so.1) echo libbrotli1 ;;
    libssl.so.3|libcrypto.so.3) echo libssl3t64 ;;
    libabsl_*) echo libabsl20240722 ;;
    libwlroots-0.19.so) echo "" ;;
    libwlroots-0.18.so) echo libwlroots-0.18 ;;
    ld-linux-aarch64.so.1) echo libc6 ;;
    *) echo "" ;;
  esac
}

find_in_dirs() {
  local so="$1"; shift
  local d
  for d in "$@"; do
    if [[ -e "${d}/${so}" ]]; then
      printf '%s\n' "${d}/${so}"
      return 0
    fi
  done
  return 1
}

rootfs_has() { find_in_dirs "$1" "${LIBDIRS[@]}" >/dev/null; }
host_find() { find_in_dirs "$1" "${HOST_LIBDIRS[@]}"; }

needed_of() {
  # print DT_NEEDED sonames of an ELF file
  readelf -d "$1" 2>/dev/null | awk '/NEEDED/ {gsub(/[\[\]]/,"",$NF); print $NF}'
}

# BFS over DT_NEEDED using host libs to discover the full closure, then check rootfs
collect_closure() {
  declare -A seen=()
  local queue=() so lib next
  while read -r so; do
    [[ -n "$so" ]] || continue
    queue+=("$so")
  done < <(needed_of "$GS")

  while ((${#queue[@]})); do
    so="${queue[0]}"
    queue=("${queue[@]:1}")
    [[ -n "${seen[$so]:-}" ]] && continue
    seen["$so"]=1
    printf '%s\n' "$so"

    [[ "$so" == linux-vdso.so.1 || "$so" == ld-linux* ]] && continue

    # Prefer host copy to walk further NEEDED (stable); fall back to rootfs copy
    lib="$(host_find "$so" || true)"
    [[ -z "$lib" ]] && lib="$(find_in_dirs "$so" "${LIBDIRS[@]}" || true)"
    [[ -n "$lib" ]] || continue

    while read -r next; do
      [[ -z "$next" || -n "${seen[$next]:-}" ]] && continue
      queue+=("$next")
    done < <(needed_of "$lib")
  done
}

list_missing() {
  local so
  while read -r so; do
    [[ -z "$so" ]] && continue
    [[ "$so" == linux-vdso.so.1 || "$so" == ld-linux* ]] && continue
    rootfs_has "$so" || printf '%s\n' "$so"
  done < <(collect_closure | sort -u)
}

stage_into_rootfs() {
  local so="$1" src real base dest_dir
  src="$(host_find "$so")" || return 1
  real="$(readlink -f "$src")"
  if [[ "$real" == /usr/local/* ]]; then
    dest_dir="${ROOTFS}/usr/local/lib/aarch64-linux-gnu"
  elif [[ "$real" == */pulseaudio/* ]]; then
    dest_dir="${ROOTFS}/usr/lib/aarch64-linux-gnu/pulseaudio"
  else
    dest_dir="${ROOTFS}/usr/lib/aarch64-linux-gnu"
  fi
  mkdir -p "$dest_dir"
  cp -a "$real" "$dest_dir/"
  base="$(basename "$real")"
  ln -sfn "$base" "${dest_dir}/${so}"
  if [[ -L "$src" && "$(basename "$src")" != "$so" ]]; then
    ln -sfn "$base" "${dest_dir}/$(basename "$src")"
  fi
  log "staged ${so} ← ${real}"
}

apt_install_pkgs() {
  local pkgs=("$@")
  ((${#pkgs[@]})) || return 0
  mkdir -p "${ROOTFS}/dev/pts" "${ROOTFS}/proc"
  mountpoint -q "${ROOTFS}/proc" || mount -t proc proc "${ROOTFS}/proc"
  mountpoint -q "${ROOTFS}/dev" || mount --bind /dev "${ROOTFS}/dev"
  mountpoint -q "${ROOTFS}/dev/pts" || mount -t devpts devpts "${ROOTFS}/dev/pts" 2>/dev/null || true
  "${ROOT_DIR}/scripts/inject-chroot-dns.sh" "${ROOTFS}" 2>/dev/null || true
  install -d "${ROOTFS}/etc/apt/apt.conf.d"
  cat >"${ROOTFS}/etc/apt/apt.conf.d/90steamos-force-confold" <<'EOF'
Dpkg::Options { "--force-confdef"; "--force-confold"; };
APT::Get::Assume-Yes "true";
EOF
  export DEBIAN_FRONTEND=noninteractive
  chroot "${ROOTFS}" apt-get update -y >/dev/null || true
  log "apt install: ${pkgs[*]}"
  chroot "${ROOTFS}" env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y -o Dpkg::Options::="--force-confold" \
    --no-install-recommends "${pkgs[@]}" || true
  umount -l "${ROOTFS}/dev/pts" 2>/dev/null || true
  umount -l "${ROOTFS}/dev" 2>/dev/null || true
  umount -l "${ROOTFS}/proc" 2>/dev/null || true
  ldconfig -r "${ROOTFS}" 2>/dev/null || true
}

mark_pass() {
  install -d "${ROOTFS}/usr/share/sm8550-steamos"
  {
    date -Iseconds
    echo "gamescope=${GS}"
    collect_closure | sort -u | wc -l | awk '{print "sonames_checked="$1}'
  } > "${ROOTFS}/usr/share/sm8550-steamos/gamescope-libs-ok.txt"
  log "PASS — recursive readelf closure OK"
}

log "Recursive readelf lib check for ${GS#"$ROOTFS"}"
MISSING_FILE="$(mktemp)"
trap 'rm -f "$MISSING_FILE"' EXIT

list_missing > "$MISSING_FILE" || true
MISSING_COUNT="$(grep -c . "$MISSING_FILE" || true)"
log "Missing ${MISSING_COUNT} libraries"
if [[ "$MISSING_COUNT" -gt 0 ]]; then
  sed 's/^/  - /' "$MISSING_FILE"
fi

if [[ "$MISSING_COUNT" -eq 0 ]]; then
  mark_pass
  exit 0
fi
(( CHECK_ONLY )) && die "gamescope library check failed"

while read -r so; do
  [[ -z "$so" ]] && continue
  rootfs_has "$so" && continue
  stage_into_rootfs "$so" || true
done < "$MISSING_FILE"
ldconfig -r "${ROOTFS}" 2>/dev/null || true

list_missing > "$MISSING_FILE" || true
MISSING_COUNT="$(grep -c . "$MISSING_FILE" || true)"
if [[ "$MISSING_COUNT" -eq 0 ]]; then
  mark_pass
  exit 0
fi

PKGS=()
while read -r so; do
  [[ -z "$so" ]] && continue
  pkg="$(soname_to_pkg "$so")"
  [[ -n "$pkg" ]] && PKGS+=("$pkg")
done < "$MISSING_FILE"
if ((${#PKGS[@]})); then
  mapfile -t PKGS < <(printf '%s\n' "${PKGS[@]}" | sort -u)
  apt_install_pkgs "${PKGS[@]}"
fi

list_missing > "$MISSING_FILE" || true
while read -r so; do
  [[ -z "$so" ]] && continue
  stage_into_rootfs "$so" || true
done < "$MISSING_FILE"
ldconfig -r "${ROOTFS}" 2>/dev/null || true

list_missing > "$MISSING_FILE" || true
MISSING_COUNT="$(grep -c . "$MISSING_FILE" || true)"
if [[ "$MISSING_COUNT" -eq 0 ]]; then
  mark_pass
  exit 0
fi

install -d "${ROOTFS}/usr/share/sm8550-steamos"
cp "$MISSING_FILE" "${ROOTFS}/usr/share/sm8550-steamos/gamescope-missing-sonames.txt"
log "STILL MISSING:"
sed 's/^/  - /' "$MISSING_FILE"
die "gamescope recursive library check FAILED"
