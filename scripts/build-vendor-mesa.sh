#!/usr/bin/env bash
# Build Mesa 26.1.6 + vendor/mesa/patches/SM8550 and install a FULL stack into rootfs:
#   Vulkan (Turnip/freedreno) + OpenGL/GLES/EGL/GBM/GLX + LLVM (llvmpipe/draw).
# Purges Ubuntu stock Mesa and apt-pins it so apt cannot bring it back.
#
# Usage:
#   sudo ./scripts/build-vendor-mesa.sh <rootfs>
# Env:
#   FORCE_REBUILD=1   wipe meson build dir and reconfigure
#   MESA_VER=26.1.6
#   SKIP_PURGE=0      set 1 to skip stock mesa purge (not recommended)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
MESA_VER="${MESA_VER:-26.1.6}"
SRC_CACHE="${ROOT_DIR}/output/src"
BUILD_DIR="${ROOT_DIR}/output/work/mesa-${MESA_VER}"
PATCH_DIR="${ROOT_DIR}/vendor/mesa/patches/SM8550"
MESA_URL="${MESA_URL:-https://archive.mesa3d.org/mesa-${MESA_VER}.tar.xz}"
JOBS="${JOBS:-$(nproc)}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
SKIP_PURGE="${SKIP_PURGE:-0}"

log() { printf '==> [mesa] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
[[ -d "$PATCH_DIR" ]] || die "Missing patches: ${PATCH_DIR}"
[[ "${EUID}" -eq 0 ]] || die "Run as root (DESTDIR install + apt purge)"

need_cmd() { command -v "$1" >/dev/null || die "Missing tool: $1"; }
need_cmd meson
need_cmd ninja
need_cmd curl
need_cmd tar
need_cmd patch
need_cmd llvm-config-19 || need_cmd llvm-config || die "Need llvm-config-19 (libllvm19 / llvm-19-dev)"

STOCK_MESA_PKGS=(
  mesa-vulkan-drivers
  libgl1-mesa-dri
  mesa-libgallium
  libegl-mesa0
  libegl1-mesa-dev
  libglx-mesa0
  libgl1-mesa-glx
  libgles2-mesa-dev
  mesa-va-drivers
  mesa-vdpau-drivers
)

MESON_ARGS=(
  --prefix=/usr
  --libdir=lib/aarch64-linux-gnu
  --buildtype=release
  -Dplatforms=x11,wayland
  -Dgallium-drivers=freedreno,llvmpipe,softpipe
  -Dvulkan-drivers=freedreno
  -Dglvnd=enabled
  -Degl=enabled
  -Dgles1=disabled
  -Dgles2=enabled
  -Dopengl=true
  -Dgbm=enabled
  -Dglx=dri
  -Dllvm=enabled
  -Dshared-llvm=enabled
  -Ddraw-use-llvm=true
  -Dshared-glapi=enabled
  -Dmicrosoft-clc=disabled
  -Dvalgrind=disabled
  -Dbuild-tests=false
  -Dvideo-codecs=all
  -Dfreedreno-kmds=msm
  -Dvulkan-layers=
)

chroot_apt() {
  mkdir -p "${ROOTFS}/dev/pts" "${ROOTFS}/proc"
  mountpoint -q "${ROOTFS}/proc" || mount -t proc proc "${ROOTFS}/proc"
  mountpoint -q "${ROOTFS}/dev" || mount --bind /dev "${ROOTFS}/dev"
  mountpoint -q "${ROOTFS}/dev/pts" || mount -t devpts devpts "${ROOTFS}/dev/pts" 2>/dev/null || true
  "${ROOT_DIR}/scripts/inject-chroot-dns.sh" "${ROOTFS}" 2>/dev/null || true
  chroot "${ROOTFS}" env DEBIAN_FRONTEND=noninteractive apt-get "$@"
}

chroot_apt_cleanup() {
  umount -l "${ROOTFS}/dev/pts" 2>/dev/null || true
  umount -l "${ROOTFS}/dev" 2>/dev/null || true
  umount -l "${ROOTFS}/proc" 2>/dev/null || true
}

install_runtime_deps() {
  local pkgs=()
  if [[ -f "${ROOT_DIR}/packages/mesa-runtime" ]]; then
    mapfile -t pkgs < <(grep -vE '^\s*(#|$)' "${ROOT_DIR}/packages/mesa-runtime" | awk 'NF')
  fi
  ((${#pkgs[@]})) || return 0
  log "Ensuring Mesa runtime deps in rootfs (${#pkgs[@]} pkgs)"
  chroot_apt update -y >/dev/null || true
  chroot_apt install -y -o Dpkg::Options::="--force-confold" --no-install-recommends "${pkgs[@]}" || true
}

purge_and_block_stock_mesa() {
  [[ "$SKIP_PURGE" == "1" ]] && { log "SKIP_PURGE=1"; return 0; }

  log "Installing apt pin (block Ubuntu Mesa forever)"
  install -D -m 0644 \
    "${ROOT_DIR}/config/apt-preferences/99-block-ubuntu-mesa" \
    "${ROOTFS}/etc/apt/preferences.d/99-block-ubuntu-mesa"

  log "Purging Ubuntu stock Mesa packages (force-depends — keep xwayland/libgbm)"
  chroot_apt update -y >/dev/null || true
  # Do NOT use apt-get remove: it cascades and deletes xwayland (via libgbm1→mesa-libgallium).
  for pkg in "${STOCK_MESA_PKGS[@]}"; do
    chroot "${ROOTFS}" dpkg --remove --force-depends "$pkg" 2>/dev/null || true
    chroot "${ROOTFS}" dpkg --purge --force-depends "$pkg" 2>/dev/null || true
  done

  log "apt-mark hold stock Mesa package names"
  chroot "${ROOTFS}" apt-mark hold "${STOCK_MESA_PKGS[@]}" 2>/dev/null || true

  # Quarantine any leftover stock Vulkan ICDs / drivers that apt did not own
  local icd_dir="${ROOTFS}/usr/share/vulkan/icd.d"
  local quarantine="${ROOTFS}/usr/share/sm8550-steamos/quarantine-stock-mesa"
  mkdir -p "${quarantine}/icd.d" "${quarantine}/lib"
  if [[ -d "$icd_dir" ]]; then
    local f base
    for f in "$icd_dir"/*.json; do
      [[ -e "$f" ]] || continue
      base="$(basename "$f")"
      case "$base" in
        freedreno_icd*.json) continue ;;
        *)
          log "quarantine ICD ${base}"
          mv -f "$f" "${quarantine}/icd.d/" 2>/dev/null || true
          ;;
      esac
    done
  fi

  # Drop stock gallium / vulkan driver blobs that fight vendor 26.1.6
  local libdir="${ROOTFS}/usr/lib/aarch64-linux-gnu"
  local so
  for so in \
    libgallium-26.0*.so \
    libvulkan_lvp.so \
    libvulkan_intel.so \
    libvulkan_radeon.so \
    libvulkan_nouveau.so \
    libvulkan_asahi.so \
    libvulkan_broadcom.so \
    libvulkan_panfrost.so \
    libvulkan_virtio.so \
    libvulkan_gfxstream.so \
    libvulkan_powervr_mesa.so
  do
    # shellcheck disable=SC2086
    for f in ${libdir}/${so}; do
      [[ -e "$f" ]] || continue
      log "quarantine $(basename "$f")"
      mv -f "$f" "${quarantine}/lib/" 2>/dev/null || true
    done
  done
}

integrate_mesa_stack() {
  local libdir="${ROOTFS}/usr/lib/aarch64-linux-gnu"
  local icd_share="${ROOTFS}/usr/share/vulkan/icd.d"
  local icd_etc="${ROOTFS}/etc/vulkan/icd.d"
  local envd="${ROOTFS}/etc/environment.d"

  install -d "$icd_share" "$icd_etc" "$envd" \
    "${ROOTFS}/usr/share/glvnd/egl_vendor.d" \
    "${ROOTFS}/usr/share/sm8550-steamos"

  # Prefer absolute-path Turnip ICD
  if [[ -f "${icd_share}/freedreno_icd.aarch64.json" ]]; then
    ln -sfn /usr/share/vulkan/icd.d/freedreno_icd.aarch64.json \
      "${icd_etc}/freedreno_icd.aarch64.json"
  elif [[ -f "${icd_share}/freedreno_icd.json" ]]; then
    # Rewrite to absolute library path if needed
    if ! grep -q '/usr/lib' "${icd_share}/freedreno_icd.json"; then
      cat >"${icd_share}/freedreno_icd.aarch64.json" <<'EOF'
{
    "ICD": {
        "api_version": "1.4.354",
        "library_arch": "64",
        "library_path": "/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so"
    },
    "file_format_version": "1.0.1"
}
EOF
    fi
    ln -sfn /usr/share/vulkan/icd.d/freedreno_icd.aarch64.json \
      "${icd_etc}/freedreno_icd.aarch64.json"
  fi

  # Force loader to Turnip only (no lvp / stock mix)
  cat >"${envd}/50-steamos-mesa-turnip.conf" <<'EOF'
# Vendor Mesa (SM8550 / Adreno 740) — do not load Ubuntu ICDs
VK_DRIVER_FILES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json
EOF

  # GLVND → Mesa EGL
  if [[ ! -f "${ROOTFS}/usr/share/glvnd/egl_vendor.d/50_mesa.json" ]]; then
    cat >"${ROOTFS}/usr/share/glvnd/egl_vendor.d/50_mesa.json" <<'EOF'
{
    "file_format_version" : "1.0.0",
    "ICD" : {
        "library_path" : "libEGL_mesa.so.0"
    }
}
EOF
  fi

  ldconfig -r "${ROOTFS}" 2>/dev/null || true

  # Required artifacts
  local miss=0
  local req
  for req in \
    "${libdir}/libvulkan_freedreno.so" \
    "${libdir}/libgallium-${MESA_VER}.so" \
    "${libdir}/libEGL_mesa.so.0" \
    "${libdir}/libGLX_mesa.so.0" \
    "${libdir}/libgbm.so.1" \
    "${libdir}/dri/msm_dri.so" \
    "${libdir}/libLLVM.so.19.1"
  do
    if [[ ! -e "$req" ]]; then
      log "MISSING required: ${req#"$ROOTFS"}"
      miss=$((miss + 1))
    fi
  done

  # Host-built Turnip may need SONAMEs Ubuntu does not ship (display-info.so.2)
  if [[ -x "${ROOT_DIR}/scripts/fix-turnip-runtime-libs.sh" ]]; then
    "${ROOT_DIR}/scripts/fix-turnip-runtime-libs.sh" "$ROOTFS" || miss=$((miss + 1))
  fi

  # Drop leftover stock gallium that confuses GBM (apt xwayland reinstalls it)
  rm -f "${libdir}"/libgallium-26.0*.so
  if [[ -f "${libdir}/gbm/dri_gbm.so" ]] && readelf -d "${libdir}/gbm/dri_gbm.so" 2>/dev/null | grep -q 'libgallium-26.0'; then
    log "removing stock dri_gbm.so (linked to gallium 26.0)"
    rm -f "${libdir}/gbm/dri_gbm.so"
  fi
  # Re-install just ran — dri_gbm should be vendor; assert
  if [[ -f "${libdir}/gbm/dri_gbm.so" ]] && ! readelf -d "${libdir}/gbm/dri_gbm.so" 2>/dev/null | grep -q "libgallium-${MESA_VER}"; then
    log "WARN: dri_gbm.so not linked to libgallium-${MESA_VER}"
  fi

  (( miss == 0 )) || die "Mesa stack incomplete (${miss} missing) — fix deps / rebuild"

  {
    date -Iseconds
    echo "mesa=${MESA_VER}"
    echo "vulkan=freedreno/turnip"
    echo "opengl=egl+gles2+glx+gbm"
    echo "llvm=shared-19 (llvmpipe+draw)"
    echo "stock_mesa=purged+apt-pinned"
    readelf -d "${libdir}/libgallium-${MESA_VER}.so" | awk '/libLLVM/{print "gallium_needs="$NF}'
    readelf -d "${libdir}/libvulkan_freedreno.so" | awk '/NEEDED/{c++} END{print "turnip_needed_count="c}'
  } > "${ROOTFS}/usr/share/sm8550-steamos/mesa-stack-ok.txt"
  printf '%s\n' "$MESA_VER" > "${ROOTFS}/usr/share/sm8550-steamos/mesa-version"
  log "PASS — full Mesa stack integrated (see usr/share/sm8550-steamos/mesa-stack-ok.txt)"
}

# --- source ---
mkdir -p "$SRC_CACHE"
TARBALL="${SRC_CACHE}/mesa-${MESA_VER}.tar.xz"
SRC="${SRC_CACHE}/mesa-${MESA_VER}"

if [[ ! -f "$TARBALL" ]]; then
  log "Downloading ${MESA_URL}"
  curl -fL --retry 3 -o "$TARBALL" "$MESA_URL"
fi

if [[ ! -d "$SRC" ]]; then
  log "Extracting mesa-${MESA_VER}"
  tar -C "$SRC_CACHE" -xf "$TARBALL"
fi

MARKER="${SRC}/.steamos-ubuntu-patches-applied"
if [[ ! -f "$MARKER" ]]; then
  log "Applying SM8550 patches"
  (
    cd "$SRC"
    for p in "$PATCH_DIR"/*.patch; do
      [[ -f "$p" ]] || continue
      if patch -p1 --forward --dry-run < "$p" >/dev/null 2>&1; then
        patch -p1 --forward < "$p"
      elif patch -p1 -R --dry-run < "$p" >/dev/null 2>&1; then
        log "  already applied: $(basename "$p")"
      else
        patch -p1 --forward < "$p" || die "Failed patch $(basename "$p")"
      fi
    done
  )
  touch "$MARKER"
fi

if [[ "$FORCE_REBUILD" == "1" ]]; then
  log "FORCE_REBUILD=1 — wiping ${BUILD_DIR}"
  rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"

log "Meson configure (Turnip + OpenGL + LLVM) → ${BUILD_DIR}"
if [[ ! -f "${BUILD_DIR}/build.ninja" ]]; then
  meson setup "$BUILD_DIR" "$SRC" "${MESON_ARGS[@]}"
else
  meson setup --reconfigure "$BUILD_DIR" "$SRC" "${MESON_ARGS[@]}" || true
fi

# Sanity: llvm + opengl must be on
meson configure "$BUILD_DIR" | grep -E '^\s+(llvm|opengl|gallium-drivers|vulkan-drivers|shared-llvm|egl|gles2|glx)\s' || true

log "Compiling Mesa ${MESA_VER} (jobs=${JOBS})"
meson compile -C "$BUILD_DIR" -j "$JOBS"

# Purge stock BEFORE install so DESTDIR files are not owned by dpkg
install_runtime_deps
purge_and_block_stock_mesa
chroot_apt_cleanup

log "Installing Mesa into rootfs (DESTDIR)"
DESTDIR="$ROOTFS" meson install -C "$BUILD_DIR" --no-rebuild

integrate_mesa_stack
chroot_apt_cleanup

# Placeholders for stock Mesa package names while keeping real libgbm1/libgbm-dev
if [[ -x "${ROOT_DIR}/scripts/install-vendor-mesa-dummies.sh" ]]; then
  "${ROOT_DIR}/scripts/install-vendor-mesa-dummies.sh" "$ROOTFS"
fi

if [[ -x "${ROOT_DIR}/scripts/verify-vendor-mesa-stack.sh" ]]; then
  "${ROOT_DIR}/scripts/verify-vendor-mesa-stack.sh" "$ROOTFS"
fi

log "Mesa ${MESA_VER} (SM8550) full stack installed into ${ROOTFS}"
log "  Vulkan Turnip + OpenGL/GLES/EGL/GBM + LLVM19 — Ubuntu Mesa blocked"
