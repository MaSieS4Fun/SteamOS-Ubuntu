#!/usr/bin/env bash
# Purge and permanently disable snap. Ubuntu transitional browsers must not pull snap.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
log() { printf '==> [snap] %s\n' "$*"; }

# Prefs from system_files may not be overlaid yet during early image stages —
# write them here too so apt never resolves snapd.
install -d /etc/apt/preferences.d
cat >/etc/apt/preferences.d/nosnap.pref <<'EOF'
Package: snapd
Pin: release a=*
Pin-Priority: -1

Package: snapd-xdg-open
Pin: release a=*
Pin-Priority: -1

Package: ubuntu-core-launcher
Pin: release a=*
Pin-Priority: -1

Package: snap-confine
Pin: release a=*
Pin-Priority: -1
EOF

log "Purging snapd / snap tooling (ignore if absent)"
apt-get purge -y snapd gnome-software-plugin-snap 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd 2>/dev/null || true

for u in snapd.service snapd.socket snapd.seeded.service snapd.apparmor.service; do
  systemctl disable "$u" 2>/dev/null || true
  systemctl mask "$u" 2>/dev/null || true
  ln -sfn /dev/null "/etc/systemd/system/${u}" 2>/dev/null || true
done

# Hold so nothing reinstalls it
apt-mark hold snapd 2>/dev/null || true

log "Snap disabled"
