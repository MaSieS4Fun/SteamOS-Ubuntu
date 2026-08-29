# Mesa packages Discover/apt must not replace (vendor Turnip/Freedreno).
# Source of truth: vendor/system-fixes/MESA/hold pakages.txt
MESA_HOLD_PKGS=(
  libegl-mesa0
  libegl1-mesa-dev
  libgl1-mesa-dri
  libgl1-mesa-glx
  libgles2-mesa-dev
  libglx-mesa0
  mesa-libgallium
  mesa-va-drivers
  mesa-vdpau-drivers
  mesa-vulkan-drivers
)
