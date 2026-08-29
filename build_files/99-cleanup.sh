#!/usr/bin/env bash
set -euo pipefail
apt-get autoremove -y || true
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/.cache || true

# Keep machine-id unset for image clones
truncate -s 0 /etc/machine-id 2>/dev/null || true
rm -f /var/lib/dbus/machine-id 2>/dev/null || true
echo "Cleanup done"
