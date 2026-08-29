#!/usr/bin/env bash
# Safety helpers: never treat the live host as the image rootfs.
#
# Source from bake/install scripts:
#   # shellcheck source=lib/rootfs-guard.sh
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/rootfs-guard.sh"
#   require_rootfs "$ROOTFS"
#
# DESTDIR="" or ROOTFS=/ makes meson/cmake/dpkg write into the build machine.
# That is what wrecks the host (Mesa, fstab, ownership). These helpers refuse it.
#
# ALLOW_LIVE_ROOT=1 is only honoured on a running SteamOS-Ubuntu handheld
# (ID=steamos-ubuntu). A generic Ubuntu/Debian build host always aborts.

if [[ -n "${STEAMOS_ROOTFS_GUARD_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
STEAMOS_ROOTFS_GUARD_LOADED=1

_STEAMOS_GUARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEAMOS_PROJECT_ROOT="$(cd "${_STEAMOS_GUARD_DIR}/../.." && pwd)"

_steamos_guard_log() { printf '==> [rootfs-guard] %s\n' "$*"; }
_steamos_guard_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

_steamos_live_os_is_image() {
  grep -q '^ID=steamos-ubuntu' /etc/os-release 2>/dev/null
}

_steamos_allow_live_root() {
  [[ "${ALLOW_LIVE_ROOT:-0}" == "1" ]] || return 1
  _steamos_live_os_is_image || return 1
  _steamos_guard_log "ALLOW_LIVE_ROOT=1 on SteamOS-Ubuntu handheld — live / permitted"
  return 0
}

_steamos_stat_id() {
  stat -c '%d:%i' "$1" 2>/dev/null || true
}

# Canonicalize and export ROOTFS. Dies on empty, live /, or host /usr inode.
require_rootfs() {
  local raw="${1:-}"
  [[ -n "$raw" ]] || _steamos_guard_die \
    "ROOTFS path is empty — refusing (empty DESTDIR installs onto the live host)"

  [[ -d "$raw" ]] || _steamos_guard_die "ROOTFS does not exist: ${raw}"

  local canon
  canon="$(realpath -e "$raw")" || _steamos_guard_die "Cannot resolve ROOTFS: ${raw}"
  [[ "$canon" == "/" ]] || canon="${canon%/}"

  case "$canon" in
    /|/usr|/usr/local|/etc|/var|/boot|/bin|/sbin|/lib|/lib64|/opt|/root)
      if [[ "$canon" == "/" ]] && _steamos_allow_live_root; then
        ROOTFS="/"
        export ROOTFS
        return 0
      fi
      _steamos_guard_die \
        "Refusing ROOTFS=${canon} — that is the live system, not the generated image. Pass output/rootfs or a mounted STORAGE partition."
      ;;
  esac

  [[ -d "${canon}/usr" ]] || _steamos_guard_die "Not a rootfs (missing usr/): ${canon}"

  local host_usr rf_usr host_root rf_root
  host_usr="$(_steamos_stat_id /usr)"
  rf_usr="$(_steamos_stat_id "${canon}/usr")"
  if [[ -n "$host_usr" && -n "$rf_usr" && "$host_usr" == "$rf_usr" ]]; then
    if _steamos_allow_live_root; then
      ROOTFS="$canon"
      export ROOTFS
      return 0
    fi
    _steamos_guard_die \
      "ROOTFS/usr is the live host /usr (inode ${host_usr}). Aborting to protect this machine."
  fi

  host_root="$(_steamos_stat_id /)"
  rf_root="$(_steamos_stat_id "$canon")"
  if [[ -n "$host_root" && -n "$rf_root" && "$host_root" == "$rf_root" ]]; then
    if _steamos_allow_live_root; then
      ROOTFS="$canon"
      export ROOTFS
      return 0
    fi
    _steamos_guard_die \
      "ROOTFS is the live / filesystem root (inode ${host_root}). Aborting."
  fi

  ROOTFS="$canon"
  export ROOTFS
}

# Never pack or DESTDIR-install onto live /. Stricter than require_rootfs.
require_rootfs_for_pack() {
  require_rootfs "${1:-${ROOTFS:-}}"
  [[ "$ROOTFS" != "/" ]] || _steamos_guard_die \
    "Refusing to pack the live / — pass the generated rootfs (output/rootfs)."
  if [[ -f "${ROOTFS}/etc/os-release" ]] \
    && ! grep -q '^ID=steamos-ubuntu' "${ROOTFS}/etc/os-release" 2>/dev/null; then
    _steamos_guard_die \
      "Refusing to pack ${ROOTFS}: /etc/os-release is not ID=steamos-ubuntu (this is not the generated image)."
  fi
}

# Only output/rootfs may be rm -rf'd by bootstrap.
require_rootfs_wipe() {
  require_rootfs "${1:-${ROOTFS:-}}"
  local expected
  expected="$(realpath -m "${STEAMOS_PROJECT_ROOT}/output/rootfs")"
  [[ "$ROOTFS" == "$expected" ]] || _steamos_guard_die \
    "Refusing to delete ${ROOTFS} (only ${expected} may be wiped)."
  [[ "$ROOTFS" != "/" ]] || _steamos_guard_die "Refusing to wipe live /"
}

# Call immediately before meson/cmake DESTDIR install.
require_destdir() {
  require_rootfs "${ROOTFS:-}"
  [[ -n "$ROOTFS" ]] || _steamos_guard_die "DESTDIR would be empty — meson would install onto the host"
  if [[ "$ROOTFS" == "/" ]]; then
    _steamos_guard_die "DESTDIR=/ would overwrite the live host (Mesa/gamescope). Use output/rootfs."
  fi
}

rootfs_meson_install() {
  local build_dir="${1:-}"
  shift || true
  [[ -n "$build_dir" && -f "${build_dir}/build.ninja" ]] \
    || _steamos_guard_die "meson build dir missing: ${build_dir}"
  require_destdir
  _steamos_guard_log "meson install DESTDIR=${ROOTFS} (never the live host)"
  DESTDIR="$ROOTFS" meson install -C "$build_dir" --no-rebuild "$@"
}

rootfs_cmake_install() {
  require_destdir
  _steamos_guard_log "cmake --install DESTDIR=${ROOTFS} (never the live host)"
  DESTDIR="$ROOTFS" cmake --install "$@"
}

# Bind mounts for chroot apt. Caller should unmount (or unmount-rootfs-binds.sh).
rootfs_chroot_prep() {
  require_rootfs "${ROOTFS:-}"
  [[ "$ROOTFS" != "/" ]] || _steamos_guard_die "Refusing chroot prep on live /"
  mkdir -p "${ROOTFS}/dev/pts" "${ROOTFS}/proc" "${ROOTFS}/sys" "${ROOTFS}/run" "${ROOTFS}/tmp"
  mountpoint -q "${ROOTFS}/proc" || mount -t proc proc "${ROOTFS}/proc"
  mountpoint -q "${ROOTFS}/sys" || mount -t sysfs sysfs "${ROOTFS}/sys"
  mountpoint -q "${ROOTFS}/dev" || mount --bind /dev "${ROOTFS}/dev"
  mountpoint -q "${ROOTFS}/dev/pts" || mount -t devpts devpts "${ROOTFS}/dev/pts" 2>/dev/null || true
  if [[ -x "${STEAMOS_PROJECT_ROOT}/scripts/inject-chroot-dns.sh" ]]; then
    "${STEAMOS_PROJECT_ROOT}/scripts/inject-chroot-dns.sh" "$ROOTFS" 2>/dev/null || true
  fi
}

rootfs_chroot_cleanup() {
  [[ -n "${ROOTFS:-}" && "$ROOTFS" != "/" && -d "${ROOTFS}/usr" ]] || return 0
  if [[ -x "${STEAMOS_PROJECT_ROOT}/scripts/unmount-rootfs-binds.sh" ]]; then
    "${STEAMOS_PROJECT_ROOT}/scripts/unmount-rootfs-binds.sh" "$ROOTFS" 2>/dev/null || true
    return 0
  fi
  umount -l "${ROOTFS}/dev/pts" 2>/dev/null || true
  umount -l "${ROOTFS}/dev" 2>/dev/null || true
  umount -l "${ROOTFS}/proc" 2>/dev/null || true
  umount -l "${ROOTFS}/sys" 2>/dev/null || true
  umount -l "${ROOTFS}/run" 2>/dev/null || true
}

rootfs_apt_install() {
  local pkgs=("$@")
  ((${#pkgs[@]})) || return 0
  require_rootfs "${ROOTFS:-}"
  [[ "$ROOTFS" != "/" ]] || _steamos_guard_die "Refusing apt on live / — packages must go into the generated rootfs"
  rootfs_chroot_prep
  export DEBIAN_FRONTEND=noninteractive
  install -d "${ROOTFS}/etc/apt/apt.conf.d"
  cat >"${ROOTFS}/etc/apt/apt.conf.d/90steamos-force-confold" <<'EOF'
Dpkg::Options { "--force-confdef"; "--force-confold"; };
APT::Get::Assume-Yes "true";
EOF
  chroot "$ROOTFS" apt-get update -y >/dev/null || true
  _steamos_guard_log "chroot apt-get install: ${pkgs[*]}"
  chroot "$ROOTFS" env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y -o Dpkg::Options::="--force-confold" \
    --no-install-recommends "${pkgs[@]}" || true
}

# Refuse copying a path that lives on the live host (not under ROOTFS or the project tree).
assert_not_host_tree() {
  local src="${1:-}"
  [[ -n "$src" ]] || return 1
  local real
  real="$(realpath -e "$src" 2>/dev/null || realpath "$src" 2>/dev/null || echo "$src")"
  case "$real" in
    "${ROOTFS}"|"${ROOTFS}"/*|"${STEAMOS_PROJECT_ROOT}"|"${STEAMOS_PROJECT_ROOT}"/*)
      return 0
      ;;
    /usr|/usr/*|/lib|/lib/*|/lib64|/lib64/*|/etc|/etc/*|/bin|/sbin|/var|/var/*)
      _steamos_guard_die \
        "Refusing to copy live-host file into the image: ${real} (use the generated rootfs or project build tree)"
      ;;
  esac
  return 0
}
