#!/usr/bin/env bash
# Instala el menú ARM-Manager en un rootfs ya montado:
#   • MESA Easy Manager
#   • Update Box64 (script only — no binary in the image)
#   • FEXEmu (script only — no binary in the image)
#   • Plasma Mobile (optional install script)
#   • Easy UFS Installer
#
# No compila nada. Copia vendor → /usr/share, crea lanzadores y .desktop.
#
# Uso:
#   sudo ./scripts/install-vendor-arm-manager.sh [rootfs]
#   sudo ./scripts/install-vendor-arm-manager.sh /media/odin2/STORAGE
#
# Dependencias runtime (instálalas tú en el rootfs si faltan):
#   MESA:  python3-gi gir1.2-gtk-3.0 policykit-1 pkexec
#   UFS:   python3-gi gir1.2-gtk-3.0 parted dosfstools e2fsprogs rsync
#          util-linux abootimg polkitd pkexec
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-${ROOT_DIR}/output/rootfs}"
ROOTFS="$(cd "$ROOTFS" && pwd)"

VENDOR_MESA="${ROOT_DIR}/vendor/MESA-Easy-Manager"
VENDOR_BOX64="${ROOT_DIR}/vendor/BOX64"
VENDOR_UFS="${ROOT_DIR}/vendor/ufs-install"

log() { printf '==> [arm-manager] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "${ROOTFS}/usr" ]] || die "Rootfs no encontrado: ${ROOTFS}"
[[ "${EUID}" -eq 0 ]] || die "Ejecuta como root (sudo)"
[[ -d "$VENDOR_MESA" ]] || die "Falta vendor/MESA-Easy-Manager"
[[ -d "$VENDOR_BOX64" ]] || die "Falta vendor/BOX64"
[[ -f "${ROOT_DIR}/scripts/install-fexemu.sh" ]] || die "Falta scripts/install-fexemu.sh"
[[ -f "${ROOT_DIR}/scripts/install-plasma-mobile.sh" ]] || die "Falta scripts/install-plasma-mobile.sh"
[[ -d "$VENDOR_UFS" ]] || die "Falta vendor/ufs-install"

share_mesa="${ROOTFS}/usr/share/mesa-easy-manager"
bin="${ROOTFS}/usr/bin"
apps="${ROOTFS}/usr/share/applications"
icons="${ROOTFS}/usr/share/icons/hicolor/scalable/apps"
dirs="${ROOTFS}/usr/share/desktop-directories"
menus="${ROOTFS}/etc/xdg/menus/applications-merged"

mkdir -p "${share_mesa}/scripts" "${bin}" "${apps}" "${icons}" "${dirs}" "${menus}"

# ── MESA Easy Manager ─────────────────────────────────────────────────────────
log "MESA Easy Manager → /usr/share/mesa-easy-manager"
rm -rf "${share_mesa}"
mkdir -p "${share_mesa}/scripts"
cp -a "${VENDOR_MESA}/mesa_easy_manager" "${share_mesa}/"
cp -a "${VENDOR_MESA}/scripts/mesa_easy_privileged.py" "${share_mesa}/scripts/"
chmod 0755 "${share_mesa}/scripts/mesa_easy_privileged.py"
[[ -f "${VENDOR_MESA}/run.py" ]] && cp -a "${VENDOR_MESA}/run.py" "${share_mesa}/"
find "${share_mesa}" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

cat > "${bin}/mesa-easy-manager" <<'EOF'
#!/bin/bash
export MESA_EASY_MANAGER_ROOT=/usr/share/mesa-easy-manager
export PYTHONPATH="${MESA_EASY_MANAGER_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m mesa_easy_manager "$@"
EOF
chmod 0755 "${bin}/mesa-easy-manager"

[[ -f "${VENDOR_MESA}/packaging/mesa-easy-manager.svg" ]] && \
  install -m 0644 "${VENDOR_MESA}/packaging/mesa-easy-manager.svg" \
    "${icons}/mesa-easy-manager.svg"

cat > "${apps}/mesa-easy-manager.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MESA Easy Manager
GenericName=Mesa Freedreno Vulkan Manager
Comment=Switch Freedreno Vulkan (libvulkan_freedreno.so) on Adreno GPUs
Exec=mesa-easy-manager
Icon=mesa-easy-manager
Terminal=false
Categories=System;Settings;X-ARM-Manager;
Keywords=mesa;vulkan;freedreno;adreno;turnip;driver;
StartupNotify=true
EOF

# ── Update Box64 (menú; binario aparte) ───────────────────────────────────────
log "Update Box64 → /usr/bin/update-box64"
install -m 0755 "${VENDOR_BOX64}/update-box64" "${bin}/update-box64"

if [[ -f "${VENDOR_BOX64}/install_manifest.txt" ]]; then
  install -d "${ROOTFS}/usr/local/share/box64"
  grep -v 'box64-configurator\.desktop' "${VENDOR_BOX64}/install_manifest.txt" \
    >"${ROOTFS}/usr/local/share/box64/install_manifest.txt"
fi

cat > "${apps}/update-box64.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Box64
Comment=Install/update or uninstall box64 (SD8G2) — use uninstall before switching to FEX
Exec=konsole -e bash -c '/usr/bin/update-box64; echo; read -r -p "Press Enter to close..."'
Icon=utilities-terminal
Terminal=false
Categories=System;Utility;X-ARM-Manager;
Keywords=box64;x86;emulation;wine;arm;fex;uninstall;
StartupNotify=true
EOF
if [[ -f "${VENDOR_BOX64}/update-box64.desktop" ]]; then
  install -m 0644 "${VENDOR_BOX64}/update-box64.desktop" "${apps}/update-box64.desktop"
fi

# ── FEXEmu (menú; binario se construye en el dispositivo) ────────────────────
log "FEXEmu → /usr/bin/install-fexemu"
install -m 0755 "${ROOT_DIR}/scripts/install-fexemu.sh" "${bin}/install-fexemu"
cat > "${apps}/install-fexemu.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=FEXEmu
Comment=Install/update or uninstall FEX-Emu (x86_64 on ARM)
Exec=konsole -e bash -c 'sudo /usr/bin/install-fexemu; echo; read -r -p "Press Enter to close..."'
Icon=utilities-terminal
Terminal=false
Categories=System;Utility;X-ARM-Manager;
Keywords=fex;fexemu;x86;emulation;wine;arm;box64;
StartupNotify=true
EOF

# ── Plasma Mobile (opcional; apt + launchers de sesión) ─────────────────────
log "Plasma Mobile → /usr/bin/install-plasma-mobile"
install -m 0755 "${ROOT_DIR}/scripts/install-plasma-mobile.sh" "${bin}/install-plasma-mobile"
if [[ -d "${ROOT_DIR}/vendor/Plasma-Mobile" ]]; then
  install -d "${ROOTFS}/usr/share/plasma-mobile-steamos/packaged"
  cp -a "${ROOT_DIR}/vendor/Plasma-Mobile/." "${ROOTFS}/usr/share/plasma-mobile-steamos/packaged/"
  sys="${ROOTFS}/usr/share/plasma-mobile-steamos/packaged/system"
  install -d "${sys}/usr/local/bin" "${sys}/usr/bin" "${sys}/usr/lib/steamos" \
    "${sys}/usr/libexec/steamos-ubuntu" "${sys}/usr/lib/systemd/user"
  for rel in \
    usr/local/bin/steamos-greetd-session \
    usr/bin/gamescope-session \
    usr/bin/steamos-session-select \
    usr/lib/steamos/steam-set-session \
    usr/libexec/steamos-ubuntu/steamos-schedule-gaming-next-login.sh \
    usr/lib/systemd/user/steamos-gamescope-autologin.service
  do
    [[ -f "${ROOT_DIR}/system_files/${rel}" ]] && \
      install -m 0755 "${ROOT_DIR}/system_files/${rel}" "${sys}/${rel}" 2>/dev/null || \
      install -m 0644 "${ROOT_DIR}/system_files/${rel}" "${sys}/${rel}" 2>/dev/null || true
  done
  chmod 0644 "${sys}/usr/lib/systemd/user/steamos-gamescope-autologin.service" 2>/dev/null || true
fi
cat > "${apps}/install-plasma-mobile.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Plasma Mobile
GenericName=Install Plasma Mobile shell
Comment=Optional touch-first Plasma Mobile (Desktop↔Mobile switch; boot stays Gaming Mode)
Exec=konsole -e bash -c 'sudo /usr/bin/install-plasma-mobile; echo; read -r -p "Press Enter to close..."'
Icon=phone
Terminal=false
Categories=System;Settings;X-ARM-Manager;
Keywords=plasma;mobile;phone;touch;session;kde;
StartupNotify=true
EOF

# ── Decky PluginLoader (menú; requiere Box64 o FEX en el dispositivo) ───────
log "Decky → /usr/bin/install-decky"
if [[ -f "${ROOT_DIR}/scripts/install-decky.sh" ]]; then
  install -m 0755 "${ROOT_DIR}/scripts/install-decky.sh" "${bin}/install-decky"
  if [[ -f "${ROOT_DIR}/vendor/Deky/decky_installer.desktop" ]]; then
    install -m 0644 "${ROOT_DIR}/vendor/Deky/decky_installer.desktop" \
      "${apps}/install-decky.desktop"
  else
    cat > "${apps}/install-decky.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Decky Loader
Comment=Install Decky PluginLoader (requires Box64 or FEXEmu)
Exec=konsole -e bash -c 'sudo /usr/bin/install-decky; echo; read -r -p "Press Enter to close..."'
Icon=steamdeck-gaming-return
Terminal=false
Categories=System;Utility;X-ARM-Manager;
Keywords=decky;plugin;loader;steam;box64;fex;
StartupNotify=true
EOF
  fi
  _LSFG_DIR="${ROOT_DIR}/vendor/system-fixes/LSFG-VK/plugin_loader.service.d"
  for _drop in fast-stop.conf fex-steam-rootfs.conf; do
    [[ -f "${_LSFG_DIR}/${_drop}" ]] || continue
    install -D -m 0644 "${_LSFG_DIR}/${_drop}" \
      "${ROOTFS}/etc/systemd/system/plugin_loader.service.d/${_drop}"
  done
fi

# ── Easy UFS Installer ────────────────────────────────────────────────────────
log "Easy UFS Installer → /usr/share/easy-ufs-install"
share_ufs="${ROOTFS}/usr/share/easy-ufs-install"
rm -rf "${share_ufs}"
mkdir -p "${share_ufs}"

for f in \
  install-masios-to-internal.sh ufs-bootimg.sh ufs-diagnose.sh \
  ufs-fix-internal-boot.sh ufs-probe-sizes.sh \
  easy-ufs-installer.py DISCLAIMER.md README.md
do
  [[ -f "${VENDOR_UFS}/${f}" ]] && install -m 0644 "${VENDOR_UFS}/${f}" "${share_ufs}/${f}"
done
chmod 0755 "${share_ufs}/"*.sh "${share_ufs}/easy-ufs-installer.py" 2>/dev/null || true

cat > "${bin}/easy-ufs-installer" <<'EOF'
#!/bin/bash
export EASY_UFS_INSTALL_ROOT=/usr/share/easy-ufs-install
exec python3 "${EASY_UFS_INSTALL_ROOT}/easy-ufs-installer.py" "$@"
EOF
chmod 0755 "${bin}/easy-ufs-installer"

cat > "${bin}/install-to-internal-ufs" <<'EOF'
#!/bin/bash
exec bash /usr/share/easy-ufs-install/install-masios-to-internal.sh "$@"
EOF
chmod 0755 "${bin}/install-to-internal-ufs"

cat > "${bin}/ufs-diagnose" <<'EOF'
#!/bin/bash
exec bash /usr/share/easy-ufs-install/ufs-diagnose.sh "$@"
EOF
chmod 0755 "${bin}/ufs-diagnose"

[[ -f "${VENDOR_UFS}/easy-ufs-installer.svg" ]] && \
  install -m 0644 "${VENDOR_UFS}/easy-ufs-installer.svg" "${icons}/easy-ufs-installer.svg"

cat > "${apps}/easy-ufs-installer.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Easy UFS Installer
GenericName=Install Linux to internal UFS
Comment=Repartition internal UFS and install Linux alongside Android (destructive)
Exec=easy-ufs-installer
Icon=easy-ufs-installer
Terminal=false
Categories=System;Settings;X-ARM-Manager;
Keywords=ufs;internal;android;storage;install;dual-boot;
StartupNotify=true
EOF

# ── Menú ARM-Manager (KDE / XDG) ─────────────────────────────────────────────
cat > "${dirs}/arm-manager.directory" <<'EOF'
[Desktop Entry]
Name=ARM-Manager
Comment=ARM handheld tools (Mesa, Box64, FEXEmu, Plasma Mobile, Decky, UFS)
Icon=preferences-system
Type=Directory
X-KDE-Weight=50
EOF

mkdir -p "${ROOTFS}/etc/xdg/menus/applications-merged"
cat > "${menus}/arm-manager.menu" <<'EOF'
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
  "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
  <Name>Applications</Name>
  <Menu>
    <Name>ARM-Manager</Name>
    <Directory>arm-manager.directory</Directory>
    <Include>
      <Category>X-ARM-Manager</Category>
    </Include>
  </Menu>
</Menu>
EOF

log "Listo. Entradas en ${apps}/ (categoría X-ARM-Manager)"
