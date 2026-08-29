#!/usr/bin/env bash
# Install Brave from Brave's official apt repo (only browser in the image).
# Also configure Mozilla apt so a later `apt install firefox` gets .deb, not snap.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export UCF_FORCE_CONFFOLD=1
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

log() { printf '==> [brave] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

ARCH="$(dpkg --print-architecture)"
[[ "$ARCH" == "arm64" || "$ARCH" == "amd64" ]] || die "Unsupported arch: $ARCH"

install -d /usr/share/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d

# --- Brave official repo ---
log "Adding Brave apt repository"
curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
  -o /usr/share/keyrings/brave-browser-archive-keyring.gpg
chmod 644 /usr/share/keyrings/brave-browser-archive-keyring.gpg

cat >/etc/apt/sources.list.d/brave-browser-release.list <<EOF
deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=${ARCH}] https://brave-browser-apt-release.s3.brave.com/ stable main
EOF

# Prefer Brave from Brave origin if names collide
cat >/etc/apt/preferences.d/brave-browser.pref <<'EOF'
Package: *
Pin: origin brave-browser-apt-release.s3.brave.com
Pin-Priority: 1001
EOF

# --- Mozilla repo (firefox .deb on demand; do NOT install in image) ---
log "Adding Mozilla apt repository (firefox available as .deb, not installed)"
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
  -o /usr/share/keyrings/packages.mozilla.org.asc
chmod 644 /usr/share/keyrings/packages.mozilla.org.asc

cat >/etc/apt/sources.list.d/mozilla.list <<EOF
deb [signed-by=/usr/share/keyrings/packages.mozilla.org.asc arch=${ARCH}] https://packages.mozilla.org/apt mozilla main
EOF

cat >/etc/apt/preferences.d/mozilla-firefox.pref <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1001
EOF

cat >/etc/apt/preferences.d/no-ubuntu-browsers.pref <<'EOF'
Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1

Package: firefox-esr
Pin: release o=Ubuntu
Pin-Priority: -1

Package: chromium-browser
Pin: release o=Ubuntu
Pin-Priority: -1

Package: chromium
Pin: release o=Ubuntu
Pin-Priority: -1

Package: epiphany-browser
Pin: release o=Ubuntu
Pin-Priority: -1
EOF

# Clear leftover half-configured packages (greetd conffile prompt kills OCI builds)
dpkg --force-confdef --force-confold --configure -a || true

apt-get update -y

# Remove any browsers that slipped in from desktop metas
log "Purging non-Brave browsers if present"
apt-get purge "${APT_OPTS[@]}" \
  firefox firefox-esr chromium chromium-browser epiphany-browser \
  2>/dev/null || true

log "Installing brave-browser"
# apt may return non-zero if an unrelated package (greetd) is still unhappy —
# succeed if the Brave binary is present.
set +e
apt-get install "${APT_OPTS[@]}" --no-install-recommends brave-browser
apt_rc=$?
set -e
dpkg --force-confdef --force-confold --configure -a || true

if command -v brave-browser >/dev/null 2>&1 || [[ -x /opt/brave.com/brave/brave ]]; then
  log "brave-browser present (apt_rc=${apt_rc})"
else
  die "brave-browser install failed (check Brave repo / network)"
fi

dpkg -l firefox chromium chromium-browser epiphany-browser 2>/dev/null | grep -E '^ii' \
  && die "Non-Brave browser still installed" || true

log "Brave-only browser stage done"
