#!/usr/bin/env bash
set -euo pipefail
apt-get autoremove -y || true
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/.cache || true

# Ubuntu docker base ships docker-clean (Dir::Cache::pkgcache "") — breaks apt tab completion on device
rm -f /etc/apt/apt.conf.d/docker-clean

# Keep machine-id unset for image clones
truncate -s 0 /etc/machine-id 2>/dev/null || true
rm -f /var/lib/dbus/machine-id 2>/dev/null || true
echo "Cleanup done"
