#!/usr/bin/env bash
# Proton-CachyOS is no longer part of the default bake (Proton 11 ARM works stock).
# This helper remains for opt-in installs only.
echo "Proton-CachyOS is optional now. To install explicitly:"
echo "  INSTALL_PROTON_CACHYOS=1 sudo ./scripts/install-proton-cachyos-arm.sh <rootfs>"
echo "Or:"
echo "  sudo ./scripts/install-proton-cachyos-arm.sh /media/odin2/STORAGE"
exit 0
