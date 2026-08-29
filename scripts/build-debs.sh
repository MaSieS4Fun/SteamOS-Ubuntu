#!/usr/bin/env bash
# Build arm64 .deb packages for SteamOS-Ubuntu vendor apps + kernel updater.
#
# Usage:
#   ./scripts/build-debs.sh
#   KERNEL_VER=7.2.2-edge-sm8550 ./scripts/build-debs.sh
#   BUILD_KERNEL_DEB=1 ./scripts/build-debs.sh   # embed vendor/kernel/output/*-kbase
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=packaging/apt/channel.conf
source "${ROOT_DIR}/packaging/apt/channel.conf"

OUT_DEBS="${OUT_DEBS:-${ROOT_DIR}/output/debs}"
WORK="${WORK:-${ROOT_DIR}/output/deb-work}"
BUILD_KERNEL_DEB="${BUILD_KERNEL_DEB:-0}"

log() { printf '==> [build-debs] %s\n' "$*" >&2; }
die() { printf 'ERROR: [build-debs] %s\n' "$*" >&2; exit 1; }

# shellcheck source=packaging/deb/common/mkdeb.sh
source "${ROOT_DIR}/packaging/deb/common/mkdeb.sh"

stage_empty() {
    local staging="$1"
    rm -rf "${staging}"
    mkdir -p "${staging}/DEBIAN"
}

write_control() {
    local staging="$1"
    cat > "${staging}/DEBIAN/control"
}

stage_mesa_easy_manager() {
    local staging="$1"
    local vendor="${ROOT_DIR}/vendor/MESA-Easy-Manager"
    local share="${staging}/usr/share/mesa-easy-manager"

    [[ -d "${vendor}/mesa_easy_manager" ]] || die "missing vendor/MESA-Easy-Manager"

    stage_empty "${staging}"
    mkdir -p "${share}/scripts" "${staging}/usr/bin" \
        "${staging}/usr/share/applications" \
        "${staging}/usr/share/icons/hicolor/scalable/apps"

    cp -a "${vendor}/mesa_easy_manager" "${share}/"
    cp -a "${vendor}/scripts/mesa_easy_privileged.py" "${share}/scripts/"
    chmod 0755 "${share}/scripts/mesa_easy_privileged.py"
    [[ -f "${vendor}/run.py" ]] && cp -a "${vendor}/run.py" "${share}/"
    find "${share}" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

    cat > "${staging}/usr/bin/mesa-easy-manager" <<'EOF'
#!/bin/bash
export MESA_EASY_MANAGER_ROOT=/usr/share/mesa-easy-manager
export PYTHONPATH="${MESA_EASY_MANAGER_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m mesa_easy_manager "$@"
EOF
    chmod 0755 "${staging}/usr/bin/mesa-easy-manager"

    [[ -f "${vendor}/packaging/mesa-easy-manager.svg" ]] && \
        install -m 0644 "${vendor}/packaging/mesa-easy-manager.svg" \
            "${staging}/usr/share/icons/hicolor/scalable/apps/mesa-easy-manager.svg"

    cat > "${staging}/usr/share/applications/mesa-easy-manager.desktop" <<'EOF'
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

    write_control "${staging}" <<EOF
Package: mesa-easy-manager
Version: ${PKG_MESA_EASY_MANAGER}
Architecture: arm64
Maintainer: SteamOS-Ubuntu <steamos-ubuntu@local>
Depends: python3, python3-gi, gir1.2-gtk-3.0, policykit-1, pkexec
Description: MESA Easy Manager — Freedreno/Turnip Vulkan switcher for Adreno SM8550
 Homepage: https://github.com/${STEAMOS_UBUNTU_GITHUB_REPO}
EOF
}

stage_easy_ufs_install() {
    local staging="$1"
    local vendor="${ROOT_DIR}/vendor/ufs-install"
    local share="${staging}/usr/share/easy-ufs-install"

    [[ -d "${vendor}" ]] || die "missing vendor/ufs-install"
    stage_empty "${staging}"
    mkdir -p "${share}" "${staging}/usr/bin" "${staging}/usr/share/applications" \
        "${staging}/usr/share/icons/hicolor/scalable/apps"

    for f in \
        install-masios-to-internal.sh ufs-bootimg.sh ufs-diagnose.sh \
        ufs-fix-internal-boot.sh ufs-probe-sizes.sh \
        easy-ufs-installer.py DISCLAIMER.md README.md
    do
        [[ -f "${vendor}/${f}" ]] && install -m 0644 "${vendor}/${f}" "${share}/${f}"
    done
    chmod 0755 "${share}/"*.sh "${share}/easy-ufs-installer.py" 2>/dev/null || true

    cat > "${staging}/usr/bin/easy-ufs-installer" <<'EOF'
#!/bin/bash
export EASY_UFS_INSTALL_ROOT=/usr/share/easy-ufs-install
exec python3 "${EASY_UFS_INSTALL_ROOT}/easy-ufs-installer.py" "$@"
EOF
    chmod 0755 "${staging}/usr/bin/easy-ufs-installer"

    for launcher in easy-ufs-installer install-to-internal-ufs ufs-diagnose; do
        case "${launcher}" in
        install-to-internal-ufs)
            cat > "${staging}/usr/bin/${launcher}" <<'EOF'
#!/bin/bash
exec bash /usr/share/easy-ufs-install/install-masios-to-internal.sh "$@"
EOF
            ;;
        ufs-diagnose)
            cat > "${staging}/usr/bin/${launcher}" <<'EOF'
#!/bin/bash
exec bash /usr/share/easy-ufs-install/ufs-diagnose.sh "$@"
EOF
            ;;
        esac
        [[ -f "${staging}/usr/bin/${launcher}" ]] && chmod 0755 "${staging}/usr/bin/${launcher}"
    done

    [[ -f "${vendor}/easy-ufs-installer.svg" ]] && \
        install -m 0644 "${vendor}/easy-ufs-installer.svg" \
            "${staging}/usr/share/icons/hicolor/scalable/apps/easy-ufs-installer.svg"

    cat > "${staging}/usr/share/applications/easy-ufs-installer.desktop" <<'EOF'
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

    write_control "${staging}" <<EOF
Package: easy-ufs-install
Version: ${PKG_EASY_UFS_INSTALL}
Architecture: arm64
Maintainer: SteamOS-Ubuntu <steamos-ubuntu@local>
Depends: python3, python3-gi, gir1.2-gtk-3.0, parted, dosfstools, e2fsprogs, rsync, util-linux, abootimg, polkitd, pkexec
Description: Easy UFS Installer — dual-boot Linux on internal UFS (AYN / SM8550)
 Homepage: https://github.com/${STEAMOS_UBUNTU_GITHUB_REPO}
EOF
}

stage_proton_arm_easy_manager() {
    local staging="$1"
    local vendor="${ROOT_DIR}/vendor/Proton-ARM-Easy-Manager"
    local share="${staging}/usr/share/proton-arm-easy-manager"

    [[ -d "${vendor}/proton_arm_easy_manager" ]] || die "missing Proton-ARM-Easy-Manager"
    stage_empty "${staging}"
    mkdir -p "${share}" "${staging}/usr/bin" "${staging}/usr/share/applications"

    cp -a "${vendor}/proton_arm_easy_manager" "${share}/"
    cp -a "${vendor}/data" "${share}/"
    [[ -f "${vendor}/run.py" ]] && cp -a "${vendor}/run.py" "${share}/"
    find "${share}" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

    cat > "${staging}/usr/bin/proton-arm-easy-manager" <<'EOF'
#!/bin/bash
export PROTON_ARM_EASY_MANAGER_ROOT=/usr/share/proton-arm-easy-manager
export PYTHONPATH="${PROTON_ARM_EASY_MANAGER_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m proton_arm_easy_manager "$@"
EOF
    chmod 0755 "${staging}/usr/bin/proton-arm-easy-manager"

    if [[ -f "${vendor}/data/icons/eparm.png" ]]; then
        for size in 16 24 32 48 64 128 256 512; do
            src="${vendor}/data/icons/eparm-${size}.png"
            [[ -f "$src" ]] || src="${vendor}/data/icons/eparm.png"
            install -d "${staging}/usr/share/icons/hicolor/${size}x${size}/apps"
            install -m 0644 "$src" \
                "${staging}/usr/share/icons/hicolor/${size}x${size}/apps/proton-arm-easy-manager.png"
        done
    fi

    cat > "${staging}/usr/share/applications/proton-arm-easy-manager.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Proton ARM Easy Manager
Comment=Install and manage ARM64 Proton builds for Steam, Lutris and Heroic
Exec=proton-arm-easy-manager gui
Icon=proton-arm-easy-manager
Terminal=false
Categories=Game;Utility;
Keywords=Proton;Steam;ARM;Wine;Lutris;Heroic;
StartupNotify=true
EOF

    write_control "${staging}" <<EOF
Package: proton-arm-easy-manager
Version: ${PKG_PROTON_ARM_EASY_MANAGER}
Architecture: arm64
Maintainer: SteamOS-Ubuntu <steamos-ubuntu@local>
Depends: python3, python3-gi, gir1.2-gtk-3.0
Description: Proton ARM Easy Manager — install Proton ARM builds for Steam/Lutris/Heroic
 Homepage: https://github.com/${STEAMOS_UBUNTU_GITHUB_REPO}
EOF
}

stage_no_steam_games() {
    local staging="$1"
    local vendor="${ROOT_DIR}/vendor/NO_Steam"
    local share="${staging}/usr/share/no-steam-games"

    [[ -d "${vendor}/no_steam_games" ]] || die "missing NO_Steam"
    stage_empty "${staging}"
    mkdir -p "${share}" "${staging}/usr/bin" "${staging}/usr/share/applications"

    cp -a "${vendor}/no_steam_games" "${share}/"
    [[ -f "${vendor}/run.py" ]] && cp -a "${vendor}/run.py" "${share}/"
    [[ -d "${vendor}/data" ]] && cp -a "${vendor}/data" "${share}/"
    find "${share}" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

    cat > "${staging}/usr/bin/no-steam-games" <<'EOF'
#!/bin/bash
export NO_STEAM_GAMES_ROOT=/usr/share/no-steam-games
export PYTHONPATH="${NO_STEAM_GAMES_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m no_steam_games "$@"
EOF
    chmod 0755 "${staging}/usr/bin/no-steam-games"

    if [[ -f "${vendor}/data/icons/no-steam-games.png" ]]; then
        install -d "${staging}/usr/share/icons/hicolor/256x256/apps"
        install -m 0644 "${vendor}/data/icons/no-steam-games.png" \
            "${staging}/usr/share/icons/hicolor/256x256/apps/no-steam-games.png"
    fi

    cat > "${staging}/usr/share/applications/no-steam-games.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=ARM Non-Steam Games
GenericName=Add DRM-free games to Steam
Comment=Add DRM-free games to Steam — assign Proton in Steam for .exe; native ARM binaries launch direct
Exec=no-steam-games gui
Icon=no-steam-games
Terminal=false
Categories=Game;Utility;
Keywords=Steam;Non-Steam;GOG;Proton;ARM;Shortcut;Lutris;Heroic;
StartupNotify=true
EOF

    write_control "${staging}" <<EOF
Package: no-steam-games
Version: ${PKG_NO_STEAM_GAMES}
Architecture: arm64
Maintainer: SteamOS-Ubuntu <steamos-ubuntu@local>
Depends: python3, python3-gi, gir1.2-gtk-3.0
Description: ARM Non-Steam Games — add DRM-free games to Steam on ARM64
 Homepage: https://github.com/${STEAMOS_UBUNTU_GITHUB_REPO}
EOF
}

stage_gyro_desktop() {
    local staging="$1"

    stage_empty "${staging}"
    bash "${ROOT_DIR}/vendor/gyro-desktop/install.sh" "${staging}"

    write_control "${staging}" <<EOF
Package: gyro-desktop
Version: ${PKG_GYRO_DESKTOP}
Architecture: arm64
Maintainer: SteamOS-Ubuntu <steamos-ubuntu@local>
Depends: python3, python3-gi, gir1.2-gtk-3.0, inputplumber
Description: GYRO-FIX — gyroscope + pad routing for AYN SM8550 handhelds
 Homepage: https://github.com/${STEAMOS_UBUNTU_GITHUB_REPO}
EOF
}

stage_masi_kernel() {
    local staging="$1"
    local bundle_dir="" release=""
    local kroot="${staging}/usr/lib/masi/kernel"

    stage_empty "${staging}"
    mkdir -p "${kroot}/config" "${kroot}/lib" "${kroot}/scripts" \
        "${staging}/usr/bin" "${staging}/usr/share/masi/kernel-bundles"

    install -m 0755 "${ROOT_DIR}/vendor/kernel/update.sh" "${kroot}/update.sh"
    install -m 0644 "${ROOT_DIR}/vendor/kernel/config/defaults.conf" "${kroot}/config/defaults.conf"
    for f in install.sh cmdline.sh bootimg.sh; do
        install -m 0644 "${ROOT_DIR}/vendor/kernel/lib/${f}" "${kroot}/lib/${f}"
    done
    for f in preflight-device.sh setup-linuxloader-cfg.sh; do
        [[ -f "${ROOT_DIR}/vendor/kernel/scripts/${f}" ]] && \
            install -m 0755 "${ROOT_DIR}/vendor/kernel/scripts/${f}" "${kroot}/scripts/${f}"
    done

    cat > "${staging}/usr/bin/masi-kernel-update" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    exec sudo -- "$0" "$@"
fi
export ROOT=/usr/lib/masi/kernel
export OUTPUT_DIR=/var/lib/masi/kernel/output
mkdir -p "${OUTPUT_DIR}"
if [[ -z "${UPDATE_BUILD:-}" && -d /usr/share/masi/kernel-bundles/current ]]; then
    export UPDATE_BUILD=/usr/share/masi/kernel-bundles/current
fi
exec "${ROOT}/update.sh"
EOF
    chmod 0755 "${staging}/usr/bin/masi-kernel-update"

    if [[ "${BUILD_KERNEL_DEB}" == "1" ]]; then
        shopt -s nullglob
        for kbase in "${ROOT_DIR}/vendor/kernel/output/"*-"${OUTPUT_SUFFIX:-kbase}"/; do
            [[ -f "${kbase}/boot/KERNEL" ]] || continue
            bundle_dir="${kbase}"
            break
        done
        shopt -u nullglob
        [[ -n "${bundle_dir}" ]] || die "BUILD_KERNEL_DEB=1 but no vendor/kernel/output/*-kbase found"
        release="$(basename "${bundle_dir}")"
        install -d "${staging}/usr/share/masi/kernel-bundles/${release}"
        cp -a "${bundle_dir}/." "${staging}/usr/share/masi/kernel-bundles/${release}/"
        ln -sfn "${release}" "${staging}/usr/share/masi/kernel-bundles/current"
        log "Embedded kernel bundle: ${release}"
    fi

    cat > "${staging}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ] && [ -d /usr/share/masi/kernel-bundles/current ]; then
    if command -v masi-kernel-update >/dev/null 2>&1; then
        UPDATE_YES=1 masi-kernel-update || true
    fi
fi
EOF
    chmod 0755 "${staging}/DEBIAN/postinst"

    write_control "${staging}" <<EOF
Package: masi-kernel-edge-sm8550
Version: ${PKG_MASI_KERNEL_EDGE_SM8550}
Architecture: arm64
Maintainer: SteamOS-Ubuntu <steamos-ubuntu@local>
Depends: abootimg, rsync, coreutils, util-linux, findutils, grep, sed, gawk, mount
Description: MaSi SM8550 edge kernel updater (ABL bootimg + UUID repack)
 Installs masi-kernel-update. When the deb embeds a kbase bundle, postinst runs
 the local install. Otherwise download a release tarball and run masi-kernel-update.
 Homepage: https://github.com/${STEAMOS_UBUNTU_GITHUB_REPO}
EOF
}

stage_steamos_ubuntu_apps() {
    local staging="$1"

    stage_empty "${staging}"
    write_control "${staging}" <<EOF
Package: steamos-ubuntu-apps
Version: ${PKG_STEAMOS_UBUNTU_APPS}
Architecture: all
Maintainer: SteamOS-Ubuntu <steamos-ubuntu@local>
Depends: mesa-easy-manager (>= ${PKG_MESA_EASY_MANAGER}), easy-ufs-install (>= ${PKG_EASY_UFS_INSTALL}), proton-arm-easy-manager (>= ${PKG_PROTON_ARM_EASY_MANAGER}), no-steam-games (>= ${PKG_NO_STEAM_GAMES}), gyro-desktop (>= ${PKG_GYRO_DESKTOP}), masi-kernel-edge-sm8550 (>= ${PKG_MASI_KERNEL_EDGE_SM8550})
Description: SteamOS-Ubuntu gaming apps + kernel updater (metapackage)
 Pulls in ARM Manager apps and the MaSi kernel updater package.
 Homepage: https://github.com/${STEAMOS_UBUNTU_GITHUB_REPO}
EOF
}

build_one() {
    local name="$1" version="$2" arch="${3:-arm64}"
    local staging="${WORK}/${name}"
    local fn

    case "${name}" in
    mesa-easy-manager) fn=stage_mesa_easy_manager ;;
    easy-ufs-install) fn=stage_easy_ufs_install ;;
    proton-arm-easy-manager) fn=stage_proton_arm_easy_manager ;;
    no-steam-games) fn=stage_no_steam_games ;;
    gyro-desktop) fn=stage_gyro_desktop ;;
    masi-kernel-edge-sm8550) fn=stage_masi_kernel ;;
    steamos-ubuntu-apps) fn=stage_steamos_ubuntu_apps ;;
    *) die "unknown package: ${name}" ;;
    esac

    log "Staging ${name} ${version} (${arch})…"
    "${fn}" "${staging}"
    mkdeb "${staging}" "${OUT_DEBS}" "${name}" "${version}" "${arch}"
}

command -v dpkg-deb >/dev/null 2>&1 || die "install dpkg-deb (apt install dpkg-dev)"

mkdir -p "${OUT_DEBS}" "${WORK}"
rm -rf "${WORK:?}"/*
mkdir -p "${WORK}"

log "Building debs → ${OUT_DEBS}"
build_one mesa-easy-manager "${PKG_MESA_EASY_MANAGER}"
build_one easy-ufs-install "${PKG_EASY_UFS_INSTALL}"
build_one proton-arm-easy-manager "${PKG_PROTON_ARM_EASY_MANAGER}"
build_one no-steam-games "${PKG_NO_STEAM_GAMES}"
build_one gyro-desktop "${PKG_GYRO_DESKTOP}"
build_one masi-kernel-edge-sm8550 "${PKG_MASI_KERNEL_EDGE_SM8550}"
build_one steamos-ubuntu-apps "${PKG_STEAMOS_UBUNTU_APPS}" all

log "Done:"
ls -1 "${OUT_DEBS}"/*.deb 2>/dev/null || true
