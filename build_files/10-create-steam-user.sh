#!/usr/bin/env bash
# Create steam user (user=steam pass=steam) for Gaming Mode + Steam ARM install
set -euo pipefail

STEAM_USER="${STEAM_USER:-steam}"
STEAM_PASS="${STEAM_PASS:-steam}"
STEAM_UID="${STEAM_UID:-1000}"
STEAM_GID="${STEAM_GID:-${STEAM_UID}}"

log() { printf '==> %s\n' "$*"; }

if id -u "${STEAM_USER}" &>/dev/null; then
  log "User ${STEAM_USER} already exists"
else
  if id -u ubuntu &>/dev/null && [[ "$(id -u ubuntu)" == "${STEAM_UID}" ]]; then
    log "Reusing ubuntu as ${STEAM_USER} (uid ${STEAM_UID})"
    if getent group ubuntu >/dev/null 2>&1; then
      groupmod -n "${STEAM_USER}" ubuntu 2>/dev/null || true
    fi
    usermod -l "${STEAM_USER}" -d "/home/${STEAM_USER}" -m \
      -c "SteamOS Ubuntu" -s /bin/bash ubuntu
  else
    log "Creating user ${STEAM_USER} (uid ${STEAM_UID}, gid ${STEAM_GID})"
    if getent group "${STEAM_USER}" >/dev/null 2>&1; then
      :
    elif ! getent group "${STEAM_GID}" >/dev/null 2>&1; then
      groupadd -g "${STEAM_GID}" "${STEAM_USER}" 2>/dev/null || groupadd "${STEAM_USER}"
    else
      groupadd "${STEAM_USER}"
    fi
    useradd -m -u "${STEAM_UID}" -g "${STEAM_USER}" -s /bin/bash -c "SteamOS Ubuntu" "${STEAM_USER}" \
      || useradd -m -s /bin/bash -c "SteamOS Ubuntu" "${STEAM_USER}"
  fi
fi

echo "${STEAM_USER}:${STEAM_PASS}" | chpasswd

# Groups for DRM / audio / input / sudo
for g in sudo audio video render input plugdev games netdev bluetooth; do
  getent group "$g" >/dev/null 2>&1 || continue
  usermod -aG "$g" "${STEAM_USER}" || true
done

install -d -o "${STEAM_USER}" -g "${STEAM_USER}" -m 755 \
  "/home/${STEAM_USER}" \
  "/home/${STEAM_USER}/.config" \
  "/home/${STEAM_USER}/.local/share" \
  "/home/${STEAM_USER}/.steam" \
  "/home/${STEAM_USER}/.config/gamescope" \
  "/home/${STEAM_USER}/.config/MangoHud" \
  "/home/${STEAM_USER}/.config/steamos-ubuntu"

# Visible XDG dirs even without a Plasma session
if command -v xdg-user-dirs-update >/dev/null 2>&1; then
  runuser -u "${STEAM_USER}" -- env HOME="/home/${STEAM_USER}" xdg-user-dirs-update || true
else
  runuser -u "${STEAM_USER}" -- bash -lc 'mkdir -p "$HOME"/{Desktop,Downloads,Documents,Music,Pictures,Videos,Templates,Public}' || true
fi
chmod 755 "/home/${STEAM_USER}"

# Narrow passwordless sudo: OOBE helpers only (greetd has no TTY).
# NOPASSWD:ALL breaks Desktop (sudo never prompts; kate/pkexec UX fails).
install -d -o root -g root -m 0750 /etc/sudoers.d
rm -f /etc/sudoers.d/99-steam-user
cat >/etc/sudoers.d/99-steam-oobe-helpers <<EOF
Defaults:${STEAM_USER} !requiretty
${STEAM_USER} ALL=(root) NOPASSWD: /usr/bin/steamos-polkit-helpers/steamos-set-timezone, /usr/bin/steamos-polkit-helpers/steamos-select-branch, /usr/bin/timedatectl
EOF
chown root:root /etc/sudoers.d /etc/sudoers.d/99-steam-oobe-helpers
chmod 0750 /etc/sudoers.d
chmod 0440 /etc/sudoers.d/99-steam-oobe-helpers

# Steam ARM is baked into the image (install-steam-arm-into-rootfs.sh).
# Do NOT hook ~/.bashrc to run install-steam-arm on first terminal open.

chown -R "${STEAM_USER}:${STEAM_USER}" "/home/${STEAM_USER}"

# Ubuntu cloud image often leaves a useless 'ubuntu' user (uid 1000)
if id -u ubuntu &>/dev/null; then
  passwd -l ubuntu 2>/dev/null || true
  usermod -s /usr/sbin/nologin ubuntu 2>/dev/null || true
  log "Locked leftover user 'ubuntu'"
fi

log "User ${STEAM_USER} ready (password set)"
