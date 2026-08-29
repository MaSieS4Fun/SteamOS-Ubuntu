#!/usr/bin/env bash
# Fix networking so Wi-Fi uses DHCP for IP + DNS (no static public DNS).
#
#   sudo ./scripts/fix-wifi-dns.sh /              # live handheld
#   sudo ./scripts/fix-wifi-dns.sh /media/odin2/STORAGE
set -euo pipefail
ROOT="${1:-/}"

[[ "${EUID}" -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -d "${ROOT}/etc" ]] || { echo "Bad root: $ROOT"; exit 1; }

mkdir -p "${ROOT}/etc/NetworkManager/conf.d"
cat >"${ROOT}/etc/NetworkManager/conf.d/00-steamos-dns.conf" <<'EOF'
[main]
dns=default
rc-manager=symlink
EOF

# Remove static / resolved overrides from earlier experiments
rm -f "${ROOT}/etc/systemd/resolved.conf.d/steamos-dns.conf" 2>/dev/null || true

if [[ "$ROOT" == "/" ]]; then
  ln -sfn /run/NetworkManager/resolv.conf /etc/resolv.conf
else
  ln -sfn ../run/NetworkManager/resolv.conf "${ROOT}/etc/resolv.conf"
fi

if [[ "$ROOT" == "/" ]]; then
  systemctl reload NetworkManager.service 2>/dev/null \
    || systemctl restart NetworkManager.service 2>/dev/null || true

  # Ensure active Wi-Fi profiles accept DHCP DNS (and address)
  while IFS=: read -r name uuid type _; do
    [[ "$type" == "802-11-wireless" || "$type" == "wifi" ]] || continue
    nmcli connection modify "$uuid" \
      ipv4.method auto \
      ipv4.ignore-auto-dns no \
      ipv4.ignore-auto-routes no \
      ipv6.method auto \
      ipv6.ignore-auto-dns no 2>/dev/null || true
  done < <(nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null || true)

  CONN="$(nmcli -t -f NAME,TYPE,STATE connection show --active 2>/dev/null \
    | awk -F: '$2 ~ /wireless|wifi/ && $3 ~ /activated/ {print $1; exit}')"
  if [[ -n "${CONN:-}" ]]; then
    nmcli connection up "$CONN" 2>/dev/null || true
  fi

  echo "resolv.conf → $(readlink /etc/resolv.conf 2>/dev/null || echo '?')"
  echo "--- resolv.conf (from DHCP via NM) ---"
  cat /etc/resolv.conf 2>/dev/null || true
  echo "--- addressing ---"
  nmcli -f GENERAL,IP4 device show 2>/dev/null | head -40 || true
else
  echo "Installed into $ROOT (DHCP DNS via NetworkManager). Reboot after unmount."
fi
