#!/usr/bin/env bash
# Inject working DNS into a rootfs for chroot builds (apt/curl/Steam bake).
# Never leave 127.0.0.53 or a dangling NetworkManager symlink — resolved/NM
# are not running inside the build chroot.
#
# Usage: inject-chroot-dns.sh <rootfs>
set -euo pipefail
ROOTFS="${1:-}"
[[ -n "$ROOTFS" && -d "${ROOTFS}/etc" ]] || { echo "Usage: $0 <rootfs>" >&2; exit 1; }

# Drop any symlink (NM/resolved stub) so we write a real file.
rm -f "${ROOTFS}/etc/resolv.conf"

write_dns() {
  local out="${ROOTFS}/etc/resolv.conf"
  {
    echo '# Temporary DNS for image bake chroot (replaced at finalize for device)'
    local n
    for n in "$@"; do
      [[ -n "$n" ]] || continue
      echo "nameserver $n"
    done
  } >"$out"
}

# 1) systemd-resolved's *upstream* list (not the stub)
if [[ -r /run/systemd/resolve/resolv.conf ]]; then
  # Prefer copying that file, but strip 127.0.0.53 if present
  if grep -qE '^nameserver[[:space:]]+[0-9a-fA-F:.]+' /run/systemd/resolve/resolv.conf; then
    grep -E '^(nameserver|search|options)[[:space:]]' /run/systemd/resolve/resolv.conf \
      | grep -v 'nameserver[[:space:]]*127\.0\.0\.53' \
      >"${ROOTFS}/etc/resolv.conf" || true
  fi
fi

# 2) resolvectl DNS= lines
if [[ ! -s "${ROOTFS}/etc/resolv.conf" ]] || ! grep -qE '^nameserver[[:space:]]+[1-9]' "${ROOTFS}/etc/resolv.conf" 2>/dev/null; then
  if command -v resolvectl >/dev/null 2>&1; then
    mapfile -t NS < <(resolvectl dns 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '!seen[$0]++')
    if ((${#NS[@]})); then
      write_dns "${NS[@]}"
    fi
  fi
fi

# 3) Host resolv.conf if it has non-stub nameservers
if [[ ! -s "${ROOTFS}/etc/resolv.conf" ]] || ! grep -qE '^nameserver[[:space:]]+[1-9]' "${ROOTFS}/etc/resolv.conf" 2>/dev/null; then
  if [[ -r /etc/resolv.conf ]]; then
    grep -E '^(nameserver|search|options)[[:space:]]' /etc/resolv.conf \
      | grep -v 'nameserver[[:space:]]*127\.0\.0\.53' \
      >"${ROOTFS}/etc/resolv.conf" || true
  fi
fi

# 4) Last resort: well-known public DNS (bake host only — device image gets DHCP via finalize)
if [[ ! -s "${ROOTFS}/etc/resolv.conf" ]] || ! grep -qE '^nameserver[[:space:]]+' "${ROOTFS}/etc/resolv.conf" 2>/dev/null; then
  write_dns 1.1.1.1 8.8.8.8
fi

echo "==> [dns] chroot resolv.conf:"
cat "${ROOTFS}/etc/resolv.conf"
