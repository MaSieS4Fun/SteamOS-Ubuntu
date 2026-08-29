#!/usr/bin/env bash
# Assemble SteamOS-Ubuntu from OCI image + vendor (kernel/audio/gamescope/SteamARM)
# Produces GPT image: VFAT BOOT (KERNEL) + ext4 STORAGE (rootfs)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT_DIR}/output"
ROOTFS="${OUT}/rootfs"
IMAGE="${IMAGE:-localhost/steamos-ubuntu}"
TAG="${TAG:-resolute}"
RUNTIME="${CONTAINER_RUNTIME:-}"
WORKDIR="${OUT}/work"
SKIP_OCI_BUILD="${SKIP_OCI_BUILD:-0}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root (sudo ./create-image.sh)"

if [[ -z "$RUNTIME" ]]; then
  if command -v podman >/dev/null; then RUNTIME=podman
  elif command -v docker >/dev/null; then RUNTIME=docker
  else die "Need podman or docker"
  fi
fi

mkdir -p "$OUT" "$WORKDIR"
chmod +x "${ROOT_DIR}/scripts/"*.sh

if [[ "$SKIP_OCI_BUILD" != "1" ]]; then
  BUILD_ARGS=(build -t "${IMAGE}:${TAG}" -f Containerfile)
  if [[ "$RUNTIME" == "podman" || "$RUNTIME" == "docker" ]]; then
    BUILD_ARGS+=(--network=host)
  fi
  if [[ "$RUNTIME" == "podman" ]] && ! command -v nft >/dev/null 2>&1; then
    log "WARN: nft not found — using --network=host"
  fi

  log "Building OCI image ${IMAGE}:${TAG}"
  ( cd "$ROOT_DIR" && "$RUNTIME" "${BUILD_ARGS[@]}" . )
  log "OCI image ready: ${IMAGE}:${TAG}"

  log "Exporting container rootfs → ${ROOTFS}"
  log "(large rootfs — podman export + tar can take several minutes with little output)"
  rm -rf "$ROOTFS"
  mkdir -p "$ROOTFS"
  cid="$("$RUNTIME" create "${IMAGE}:${TAG}")"
  log "Created container ${cid} — exporting…"
  "$RUNTIME" export "$cid" | tar -C "$ROOTFS" -xf -
  "$RUNTIME" rm "$cid" >/dev/null
  log "Rootfs export done ($(du -sh "$ROOTFS" 2>/dev/null | awk '{print $1}'))"
else
  [[ -d "${ROOTFS}/usr" ]] || die "SKIP_OCI_BUILD=1 but ${ROOTFS} missing"
  log "Reusing existing rootfs ${ROOTFS}"
fi

log "Pipeline: kernel → audio → mesa/gamescope/mangohud/steam → finalize → disk image"

truncate -s 0 "${ROOTFS}/etc/machine-id" || true
install -d "${ROOTFS}/usr/share/sm8550-steamos"

# --- Kernel first (firmware + modules); replaces any Ubuntu firmware ---
# ensure-kernel auto-compiles via vendor/kernel/make.sh when output/ is empty
# KERNEL_VER exported by create-image.sh from packaging/apt/channel.conf (base series, e.g. 7.2.2)
export KERNEL_VER="${KERNEL_VER:-7.2.2}"
export UI="${UI:-plain}"
log "Ensuring / integrating SM8550 kernel (KERNEL_VER=${KERNEL_VER})"
KERN_BUILD="$("${ROOT_DIR}/scripts/ensure-kernel.sh")"
# Path only (ensure-kernel prints a single absolute line; take last non-empty just in case)
KERN_BUILD="$(printf '%s\n' "${KERN_BUILD}" | awk 'NF{p=$0} END{print p}')"
[[ -f "${KERN_BUILD}/boot/KERNEL" ]] || die "ensure-kernel returned invalid tree: ${KERN_BUILD}"
log "Kernel tree: ${KERN_BUILD}"
"${ROOT_DIR}/scripts/install-kernel-into-rootfs.sh" "$ROOTFS" "$KERN_BUILD"

# Audio vendor drop-in (UCM + ADSP). Set SKIP_AUDIO=1 only to skip.
if [[ "${SKIP_AUDIO:-0}" == "1" ]]; then
  log "SKIP_AUDIO=1 — not installing vendor/audio (PipeWire/UCM stock only)"
else
  log "Installing vendor audio (UCM + ADSP extras)"
  "${ROOT_DIR}/vendor/audio/scripts/install-into-rootfs.sh" "$ROOTFS"
fi

# Mesa / gamescope / MangoHud / Steam ARM — ALWAYS from vendor/ (never host stock gamescope)
log "Building vendor userspace stack (mesa → gamescope → mangohud → steam)"
"${ROOT_DIR}/scripts/build-vendor-stack.sh" "$ROOTFS"

log "Building vendor apps (custom)"
"${ROOT_DIR}/scripts/install-vendor-apps.sh" "$ROOTFS"

log "Ensuring Xwayland (gamescope → Steam)"
"${ROOT_DIR}/scripts/ensure-xwayland-into-rootfs.sh" "$ROOTFS"

# Refresh SteamOS-style session wrappers after overlays / vendor installs
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam"
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/bin/gamescope-session" \
  "${ROOTFS}/usr/bin/gamescope-session"
install -D -m 0755 \
  "${ROOT_DIR}/system_files/usr/local/bin/steamos-greetd-session" \
  "${ROOTFS}/usr/local/bin/steamos-greetd-session"

chmod +x \
  "${ROOTFS}/usr/bin/gamescope-session" \
  "${ROOTFS}/usr/bin/steamos-session-select" \
  "${ROOTFS}/usr/bin/steamos-desktop-to-gamescope" \
  "${ROOTFS}/usr/bin/steamos-desktop-gamescope" \
  "${ROOTFS}/usr/local/bin/steamos-greetd-session" 2>/dev/null || true

install -d "${ROOTFS}/var/lib/steamos-ubuntu"
echo gamescope-session > "${ROOTFS}/var/lib/steamos-ubuntu/session"

if ! grep -q '^steam:' "${ROOTFS}/etc/passwd" 2>/dev/null; then
  log "Creating steam user inside rootfs"
  STEAM_USER=steam STEAM_PASS=steam \
    chroot "$ROOTFS" bash -c 'useradd -m -s /bin/bash steam; echo steam:steam | chpasswd' || true
fi

echo steamos-ubuntu > "${ROOTFS}/etc/hostname"
# Debian/Ubuntu: /etc/os-release → ../usr/lib/os-release
# BUILD_ID for Steam sOSBuildId; never VARIANT_ID=steamdeck (login update nag).
install -d "${ROOTFS}/usr/lib"
cat >"${ROOTFS}/usr/lib/os-release" <<'EOF'
PRETTY_NAME="SteamOS-Ubuntu Resolute"
NAME="SteamOS-Ubuntu"
VERSION_ID="26.04"
VERSION="26.04 (Resolute)"
VERSION_CODENAME=resolute
ID=steamos-ubuntu
ID_LIKE="ubuntu debian"
HOME_URL="https://github.com/local/SteamOS-Ubuntu"
UBUNTU_CODENAME=resolute
BUILD_ID=20260825.1
EOF
ln -sfn ../usr/lib/os-release "${ROOTFS}/etc/os-release"

log "Finalize handheld defaults (Deck mode, MangoHud steam, boot trim)"
"${ROOT_DIR}/scripts/finalize-handheld-rootfs.sh" "$ROOTFS"

log "Packing rootfs tarball"
tar -C "$ROOTFS" -cf - . | gzip -1 > "${OUT}/steamos-ubuntu-resolute-arm64.tar.gz"

if [[ "${SKIP_IMG:-0}" == "1" ]]; then
  log "SKIP_IMG=1 — not creating partitioned disk image"
else
  log "Creating GPT disk image (VFAT BOOT + ext4 STORAGE)"
  "${ROOT_DIR}/scripts/make-disk-image.sh" "$ROOTFS" "$KERN_BUILD"
fi

FW_SIZE="$(du -sh "${ROOTFS}/usr/lib/firmware" 2>/dev/null | awk '{print $1}')"
cat <<EOF

========================================================================
  SteamOS-Ubuntu image ready
------------------------------------------------------------------------
  Rootfs   : ${ROOTFS}
  Firmware : ${FW_SIZE} (kernel vendor tree — not Ubuntu linux-firmware)
  Tarball  : ${OUT}/steamos-ubuntu-resolute-arm64.tar.gz
  Disk IMG : ${OUT}/steamos-ubuntu-resolute-arm64.img
             p1 VFAT BOOT=/boot/KERNEL | p2 ext4 STORAGE=rootfs
  Kernel   : ${KERN_BUILD}

  User: steam / steam
  First boot: steam-mode=deck (flags: -gamepadui -steamos3 -steampal -steamdeck)
  DisplayManager target: wayland: modeset (GAMESCOPE_WAYLAND_DISPLAY)
  MangoHud: ~/.config/MangoHud/steam/{MangoHud.conf,presets.conf}
  Finalize : ${ROOTFS}/usr/share/sm8550-steamos/finalize-ok.txt
========================================================================
EOF
