#!/usr/bin/env bash
# Re-bake SteamOS-style Steam Deck client into a mounted rootfs (e.g. STORAGE).
# Requires network on the *builder* (downloads steamdeck_publicbeta + finishes updater).
# After this, handheld first boot can show Wi-Fi OOBE without CDN.
#
#   sudo ./scripts/bake-steam-deck-into-rootfs.sh /media/odin2/STORAGE
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-steam-arm-into-rootfs.sh" "$@"
