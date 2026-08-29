#!/usr/bin/env bash
# Install apt package lists for SteamOS-Ubuntu (Ubuntu Resolute)
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export UCF_FORCE_CONFFOLD=1

# Never block image bake on conffile prompts (greetd config.toml vs system_files)
install -d /etc/apt/apt.conf.d
if [[ ! -f /etc/apt/apt.conf.d/90steamos-noninteractive ]]; then
  cat >/etc/apt/apt.conf.d/90steamos-noninteractive <<'EOF'
Dpkg::Options {
    "--force-confdef";
    "--force-confold";
};
APT::Get::Assume-Yes "true";
EOF
fi

log() { printf '==> %s\n' "$*"; }

# Block snap before any package resolution (prefs also live in system_files)
install -d /etc/apt/preferences.d
if [[ ! -f /etc/apt/preferences.d/nosnap.pref ]]; then
  cat >/etc/apt/preferences.d/nosnap.pref <<'EOF'
Package: snapd
Pin: release a=*
Pin-Priority: -1
EOF
fi

# Block sudo-rs: incompatible with Steam's sudo -n usage (BMainLoop stall)
cat >/etc/apt/preferences.d/99-block-sudo-rs <<'EOF'
Package: sudo-rs
Pin: release *
Pin-Priority: -1
EOF

log "Refreshing apt (Ubuntu Resolute)"
apt-get update -y

if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  log "Building on ${PRETTY_NAME:-unknown} (${VERSION_CODENAME:-?})"
fi

# Never install these from packages/* (Brave comes from official repo later;
# snap / Ubuntu browsers / pad→mouse remappers are forbidden in the image).
BANNED_RE='^(snapd|snap-confine|ubuntu-core-launcher|firefox|firefox-esr|chromium|chromium-browser|epiphany-browser|brave-browser|antimicro|input-remapper|xserver-xorg-input-joystick|ubiquity|oem-config)($|-)'

collect_pkgs() {
  local f
  for f in /tmp/packages/*; do
    [[ -f "$f" ]] || continue
    grep -vE '^\s*(#|$)' "$f" || true
  done | awk 'NF' | grep -vE "$BANNED_RE" | sort -u
}

mapfile -t PKGS < <(collect_pkgs)
log "Installing ${#PKGS[@]} packages (batched)"

APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
FAILED=()
OK=()
CHUNK=80
for ((i = 0; i < ${#PKGS[@]}; i += CHUNK)); do
  chunk=("${PKGS[@]:i:CHUNK}")
  log "apt batch $((i / CHUNK + 1)): ${#chunk[@]} packages"
  if apt-get install "${APT_OPTS[@]}" --no-install-recommends "${chunk[@]}"; then
    OK+=("${chunk[@]}")
  else
    log "WARN: batch failed — falling back to per-package"
    dpkg --force-confdef --force-confold --configure -a || true
    for p in "${chunk[@]}"; do
      if apt-get install "${APT_OPTS[@]}" --no-install-recommends "$p"; then
        OK+=("$p")
      else
        log "WARN: could not install $p"
        FAILED+=("$p")
      fi
    done
  fi
done

if ((${#FAILED[@]})); then
  install -d /usr/share/sm8550-steamos
  printf '%s\n' "${FAILED[@]}" > /usr/share/sm8550-steamos/missing-packages.txt
  log "Missing packages listed in /usr/share/sm8550-steamos/missing-packages.txt"
fi

# Hard requirements for Gaming Mode — fail the image build if these are absent
CRITICAL=(xwayland xserver-common seatd greetd)
CRIT_FAIL=()
for p in "${CRITICAL[@]}"; do
  if ! dpkg -s "$p" >/dev/null 2>&1; then
    log "CRITICAL missing: $p — forcing install"
    apt-get install "${APT_OPTS[@]}" --no-install-recommends "$p" || CRIT_FAIL+=("$p")
  fi
done
if ((${#CRIT_FAIL[@]})); then
  printf '%s\n' "${CRIT_FAIL[@]}" > /usr/share/sm8550-steamos/critical-missing.txt
  echo "ERROR: critical packages missing: ${CRIT_FAIL[*]}" >&2
  exit 1
fi
if [[ ! -x /usr/bin/Xwayland ]]; then
  echo "ERROR: /usr/bin/Xwayland missing after installing xwayland package" >&2
  exit 1
fi

# Plasma Desktop Mode: ensure startplasma-wayland exists if plasma list was present
if [[ -f /tmp/packages/plasma ]]; then
  if ! command -v startplasma-wayland >/dev/null 2>&1; then
    log "Plasma list present but startplasma-wayland missing — forcing plasma-workspace"
    apt-get install "${APT_OPTS[@]}" --no-install-recommends plasma-workspace plasma-workspace-wayland kwin-wayland || true
  fi
fi

# Ensure pipewire replaces pulse when both pulled
apt-get install "${APT_OPTS[@]}" --no-install-recommends pipewire-pulse wireplumber || true

# Never leave snapd from recommends
apt-get purge "${APT_OPTS[@]}" snapd 2>/dev/null || true

# Finish any deferred configures without conffile prompts
dpkg --force-confdef --force-confold --configure -a || true

log "Package stage done (${#OK[@]} ok, ${#FAILED[@]} missing)"
