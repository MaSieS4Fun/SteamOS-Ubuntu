#!/usr/bin/env bash
# Guard: never keep Ubuntu linux-firmware in the image.
# Kernel firmware is installed later from vendor/kernel by host scripts.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get purge -y linux-firmware firmware-sof-signed sof-firmware 'linux-firmware-*' 2>/dev/null || true
rm -rf /usr/lib/firmware /lib/firmware
mkdir -p /usr/lib/firmware
ln -sfn ../usr/lib/firmware /lib/firmware 2>/dev/null || true
echo "Distro firmware purged (placeholder until vendor/kernel firmware is copied)."
