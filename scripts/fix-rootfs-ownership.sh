#!/usr/bin/env bash
# Restore default Linux ownership on system trees (root:root).
#
# Host image bake runs as uid 1000; without this, /usr/bin and friends stay
# owned by 1000 — the same uid as user "steam" on the handheld — so steam can
# write system paths. That is insecure and masks bugs (OOBE "works" only because
# /usr is world-writable by steam).
#
# Steam client self-update writes under /home/steam/.local/share/Steam only.
# System launchers (/usr/bin/steam, .desktop, icons) are baked as root.
# OOBE timezone/branch helpers may sudo -n only those paths (see 99-steam-oobe-helpers).
#
# Usage:
#   sudo ./scripts/fix-rootfs-ownership.sh output/rootfs
#   sudo ./scripts/fix-rootfs-ownership.sh /media/odin2/STORAGE
# Live handheld only:
#   ALLOW_LIVE_ROOT=1 sudo ./scripts/fix-rootfs-ownership.sh /
set -euo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/rootfs-guard.sh
source "${_HERE}/lib/rootfs-guard.sh"
ROOTFS="${1:-}"
log() { printf '==> [ownership] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root"
[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs>"
require_rootfs "$ROOTFS"
[[ "$ROOTFS" == "/" ]] || ROOTFS="${ROOTFS%/}"


# ---------------------------------------------------------------------------
# Restore setuid/setgid after chown -R
#
# WHY: Linux clears setuid/setgid on chown(2). After we chown -R root:root
# system trees, binaries like dbus-daemon-launch-helper and pkexec lose the
# bits dpkg installed. Without them:
#   - system D-Bus cannot spawn User=root services (Kate KAuth helper fails
#     with "not allowed to own org.kde.ktexteditor6.katetextbuffer")
#   - pkexec prints "must be setuid root" and never shows a password dialog
# Use NUMERIC uids/gids from the TARGET rootfs /etc/{passwd,group} so a host
# bake with different GIDs (messagebus/polkitd) does not mis-own the image.
# ---------------------------------------------------------------------------
resolve_ugid() {
  local name="$1" kind="$2"  # kind: uid|gid
  local file id
  if [[ "$kind" == uid ]]; then
    file="${ROOTFS}/etc/passwd"
    id="$(awk -F: -v n="$name" '$1==n {print $3; exit}' "$file" 2>/dev/null || true)"
  else
    file="${ROOTFS}/etc/group"
    id="$(awk -F: -v n="$name" '$1==n {print $3; exit}' "$file" 2>/dev/null || true)"
  fi
  printf '%s' "${id:-}"
}

restore_one_mode() {
  local owner="$1" group="$2" mode="$3" relpath="$4"
  local path uid gid
  if [[ "$ROOTFS" == "/" ]]; then
    path="$relpath"
  else
    # relpath is absolute on target (/usr/...)
    path="${ROOTFS}${relpath}"
  fi
  [[ -e "$path" ]] || return 0
  uid="$(resolve_ugid "$owner" uid)"
  gid="$(resolve_ugid "$group" gid)"
  if [[ -n "$uid" && -n "$gid" ]]; then
    chown "${uid}:${gid}" "$path" || true
  else
    # Fall back to names only when live (/) and NSS works
    if [[ "$ROOTFS" == "/" ]]; then
      chown "${owner}:${group}" "$path" || true
    else
      log "WARN: skip chown ${owner}:${group} ${relpath} (missing in rootfs passwd/group)"
      return 0
    fi
  fi
  chmod "$mode" "$path" || true
  log "setuid restore ${mode} ${owner}:${group} ${relpath}"
}

restore_man_cache_ownership() {
  # man-db triggers (apt postinst / man-db.service) run mandb as user "man".
  # Ubuntu tmpfiles: "d /var/cache/man 0755 man man". After chown -R root:root on
  # var/cache, mandb cannot chmod/write → "Operation not permitted" noise on every
  # apt install. Match Debian/Ubuntu: man:man 0755 (not root:man 2755).
  local man_dir
  if [[ "$ROOTFS" == "/" ]]; then
    man_dir="/var/cache/man"
  else
    man_dir="${ROOTFS}/var/cache/man"
  fi
  [[ -d "$man_dir" ]] || return 0
  local man_uid man_gid
  man_uid="$(resolve_ugid man uid)"
  man_gid="$(resolve_ugid man gid)"
  if [[ -n "$man_uid" && -n "$man_gid" ]]; then
    chown -R "${man_uid}:${man_gid}" "$man_dir" || true
  elif [[ "$ROOTFS" == "/" ]]; then
    chown -R man:man "$man_dir" || true
  else
    log "WARN: skip /var/cache/man (missing man user/group in rootfs /etc/{passwd,group})"
    return 0
  fi
  find "$man_dir" -type d -exec chmod 0755 {} + 2>/dev/null || true
  find "$man_dir" -type f -exec chmod 0644 {} + 2>/dev/null || true
  # Ensure top-level exists with correct mode even if empty
  chmod 0755 "$man_dir" || true
  log "restored /var/cache/man → man:man 0755/0644 (tmpfiles.d/man-db.conf)"
}

restore_setuid_modes() {
  log "Restoring dpkg-statoverride + critical setuid helpers (Kate/pkexec)"
  local so_file="${ROOTFS}/var/lib/dpkg/statoverride"
  if [[ -f "$so_file" ]]; then
    # Format: owner group mode path (one entry per line)
    while read -r owner group mode path || [[ -n "${owner:-}" ]]; do
      [[ -z "${owner:-}" || "$owner" == \#* ]] && continue
      [[ -n "${path:-}" ]] || continue
      restore_one_mode "$owner" "$group" "$mode" "$path"
    done < "$so_file"
  elif [[ "$ROOTFS" == "/" ]] && command -v dpkg-statoverride >/dev/null 2>&1; then
    dpkg-statoverride --list | while read -r owner group mode path; do
      [[ -n "${path:-}" ]] || continue
      restore_one_mode "$owner" "$group" "$mode" "$path"
    done
  fi

  # Explicit critical restores (even if absent from statoverride — pkexec uses postinst chmod)
  restore_one_mode root messagebus 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper
  restore_one_mode root root 4755 /usr/bin/pkexec
  restore_one_mode root root 4755 /usr/lib/polkit-1/polkit-agent-helper-1
  for s in sudo sudo.ws; do
    [[ -e "${ROOTFS}/usr/bin/${s}" ]] || continue
    restore_one_mode root root 4755 "/usr/bin/${s}"
  done
  # AppImage / FUSE mounts (fuse3 postinst sets 4755; chown -R clears it)
  for f in /usr/bin/fusermount3 /usr/bin/fusermount; do
    [[ -e "${ROOTFS}${f}" ]] || continue
    restore_one_mode root root 4755 "$f"
  done
}


STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "${ROOTFS}/etc/passwd" 2>/dev/null || true)"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "${ROOTFS}/etc/passwd" 2>/dev/null || true)"

log "rootfs=${ROOTFS} steam=${STEAM_UID:-?}:${STEAM_GID:-?}"

chown root:root "${ROOTFS}"
chmod 0755 "${ROOTFS}"

# Recursive system trees → root:root (never /home)
SYS_TREES=(
  bin boot etc lib lib64 opt sbin srv usr
  var/cache var/lib var/log var/spool var/backups var/local var/opt
  var/mail var/crash
)
for rel in "${SYS_TREES[@]}"; do
  target="${ROOTFS}/${rel}"
  [[ "$ROOTFS" == "/" ]] && target="/${rel}"
  [[ -e "$target" ]] || continue
  log "chown -R root:root ${rel}"
  chown -R root:root "$target"
done

# Drop group/other write on system trees; keep owner bits + setuid/setgid
strip_gow() {
  local base="$1"
  [[ -d "$base" ]] || return 0
  find "$base" -type d -exec chmod u=rwx,g=rx,o=rx {} + 2>/dev/null || true
  find "$base" -type f \( ! -perm -4000 -a ! -perm -2000 \) -exec chmod go-w {} + 2>/dev/null || true
}

for rel in bin boot etc lib lib64 opt sbin srv usr \
  var/cache var/lib var/log var/spool var/backups var/local var/opt; do
  target="${ROOTFS}/${rel}"
  [[ "$ROOTFS" == "/" ]] && target="/${rel}"
  strip_gow "$target"
done

# Paths Linux expects with special modes
[[ -d "${ROOTFS}/tmp" ]] && chown root:root "${ROOTFS}/tmp" && chmod 1777 "${ROOTFS}/tmp"
[[ -d "${ROOTFS}/var/tmp" ]] && chown root:root "${ROOTFS}/var/tmp" && chmod 1777 "${ROOTFS}/var/tmp"
[[ -d "${ROOTFS}/run" ]] && chown root:root "${ROOTFS}/run" && chmod 0755 "${ROOTFS}/run"

# NetworkManager private connections dir (must not stay 755 from strip_gow)
if [[ -d "${ROOTFS}/etc/NetworkManager/system-connections" ]]; then
  chown root:root "${ROOTFS}/etc/NetworkManager/system-connections"
  chmod 0700 "${ROOTFS}/etc/NetworkManager/system-connections"
  find "${ROOTFS}/etc/NetworkManager/system-connections" -type f \
    -exec chmod 0600 {} + 2>/dev/null || true
fi

# sudoers — narrow OOBE-only NOPASSWD (never NOPASSWD:ALL — breaks Desktop sudo/kate)
install -d -m 0750 -o root -g root "${ROOTFS}/etc/sudoers.d"
if [[ -f "${ROOTFS}/etc/sudoers" ]]; then
  chown root:root "${ROOTFS}/etc/sudoers"
  chmod 0440 "${ROOTFS}/etc/sudoers"
fi
rm -f "${ROOTFS}/etc/sudoers.d/99-steam-user" 2>/dev/null || true
_SUDOERS_SRC="${_HERE}/../system_files/etc/sudoers.d/99-steam-oobe-helpers"
if [[ -f "$_SUDOERS_SRC" ]]; then
  install -D -m 0440 "$_SUDOERS_SRC" "${ROOTFS}/etc/sudoers.d/99-steam-oobe-helpers"
else
  cat >"${ROOTFS}/etc/sudoers.d/99-steam-oobe-helpers" <<'EOF'
Defaults:steam !requiretty
steam ALL=(root) NOPASSWD: /usr/bin/steamos-polkit-helpers/steamos-set-timezone, /usr/bin/steamos-polkit-helpers/steamos-select-branch, /usr/bin/timedatectl
EOF
  chmod 0440 "${ROOTFS}/etc/sudoers.d/99-steam-oobe-helpers"
fi
find "${ROOTFS}/etc/sudoers.d" -maxdepth 1 -type f -exec chown root:root {} + -exec chmod 0440 {} + 2>/dev/null || true
chmod 0750 "${ROOTFS}/etc/sudoers.d"
chown root:root "${ROOTFS}/etc/sudoers.d"

# setuid classic sudo (not sudo-rs)
for s in sudo sudo.ws; do
  f="${ROOTFS}/usr/bin/${s}"
  [[ -e "$f" ]] || continue
  chown root:root "$f"
  chmod 4755 "$f"
done
if [[ -e "${ROOTFS}/usr/bin/sudo.ws" ]]; then
  ln -sf /usr/bin/sudo.ws "${ROOTFS}/etc/alternatives/sudo" 2>/dev/null || true
fi

# Polkit helpers must be root + executable (pkexec)
if [[ -d "${ROOTFS}/usr/bin/steamos-polkit-helpers" ]]; then
  chown -R root:root "${ROOTFS}/usr/bin/steamos-polkit-helpers"
  chmod 755 "${ROOTFS}/usr/bin/steamos-polkit-helpers"
  find "${ROOTFS}/usr/bin/steamos-polkit-helpers" -type f -exec chmod 0755 {} +
fi

# Session scripts executable by steam (root-owned)
for f in \
  "${ROOTFS}/usr/bin/gamescope-session" \
  "${ROOTFS}/usr/bin/steamos-session-select" \
  "${ROOTFS}/usr/bin/steam" \
  "${ROOTFS}/usr/bin/steamos-update" \
  "${ROOTFS}/usr/local/bin/steamos-greetd-session" \
  "${ROOTFS}/usr/lib/steamos/steam-set-session" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/launch-steam" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/steamos-manager" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/ensure-decky-plugin-loader" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/volume-keys" \
  "${ROOTFS}/usr/libexec/steamos-ubuntu/expand-rootfs"
do
  [[ -e "$f" ]] || continue
  chown root:root "$f"
  [[ -f "$f" ]] && chmod 0755 "$f"
done
if [[ -d "${ROOTFS}/usr/libexec/steamos-ubuntu" ]]; then
  chown -R root:root "${ROOTFS}/usr/libexec/steamos-ubuntu"
  find "${ROOTFS}/usr/libexec/steamos-ubuntu" -type f -exec chmod 0755 {} + 2>/dev/null || true
fi

# Session log: steam must append (greetd has no convenient per-user /var/log)
install -d -m 0755 -o root -g root "${ROOTFS}/var/log"
touch "${ROOTFS}/var/log/steamos-session.log"
chown root:root "${ROOTFS}/var/log/steamos-session.log"
chmod 0666 "${ROOTFS}/var/log/steamos-session.log"

# --- Exceptions Steam / session need writable ---
if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
  if [[ -d "${ROOTFS}/home/steam" ]]; then
    log "preserve /home/steam → ${STEAM_UID}:${STEAM_GID} (client update lives here)"
    chown -R "${STEAM_UID}:${STEAM_GID}" "${ROOTFS}/home/steam"
    chmod 0755 "${ROOTFS}/home/steam"
  fi
  if [[ -d "${ROOTFS}/var/lib/steamos-ubuntu" ]]; then
    log "preserve /var/lib/steamos-ubuntu → ${STEAM_UID}:${STEAM_GID} (0775)"
    chown -R "${STEAM_UID}:${STEAM_GID}" "${ROOTFS}/var/lib/steamos-ubuntu"
    chmod 0775 "${ROOTFS}/var/lib/steamos-ubuntu"
    find "${ROOTFS}/var/lib/steamos-ubuntu" -type f -exec chmod 0664 {} + 2>/dev/null || true
  fi
fi

restore_setuid_modes
restore_man_cache_ownership

log "Done — system trees root:root; /home/steam + /var/lib/steamos-ubuntu for steam"
