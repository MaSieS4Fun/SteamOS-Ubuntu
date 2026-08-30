# Credits and upstream sources

**SteamOS-Ubuntu** bundles software from many open-source projects and the ARM64 handheld community. This document lists **all known upstream sources** used in the repository, packaging, OS image, and apt channel.

Original licenses remain with their respective authors. Project glue (scripts, packaging, overlays) is **MIT** — see [`LICENSE`](LICENSE).

If a credit is missing or incorrect, please open an issue or pull request.

---

## Index

1. [Base system](#base-system)
2. [Kernel and firmware](#kernel-and-firmware)
3. [Graphics (Mesa, gamescope, overlays)](#graphics-mesa-gamescope-overlays)
4. [Gaming session (Steam, gamescope, MangoHud)](#gaming-session-steam-gamescope-mangohud)
5. [Audio (UCM, firmware, PipeWire)](#audio-ucm-firmware-pipewire)
6. [Decky Loader and bundled plugins](#decky-loader-and-bundled-plugins)
7. [Input, gyroscope, and InputPlumber](#input-gyroscope-and-inputplumber)
8. [Handheld gamepad (fixpad-sm8550)](#handheld-gamepad-fixpad-sm8550)
9. [x86 emulation (Box64, FEX)](#x86-emulation-box64-fex)
10. [Bundled applications and tools](#bundled-applications-and-tools)
11. [Internal UFS installation](#internal-ufs-installation)
12. [Apt channel and GitHub Pages](#apt-channel-and-github-pages)
13. [Build-time download scripts](#build-time-download-scripts)
14. [Design inspiration](#design-inspiration)
15. [Acknowledgements](#acknowledgements)

---

## Base system

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **Ubuntu (Resolute, ports)** | https://ports.ubuntu.com/ubuntu-ports | Base rootfs, Plasma, apt packages (`packages/base`, `packages/plasma`, etc.) | Ubuntu / Debian (various) |
| **Universal Blue / Bazzite** | https://github.com/ublue-os | OCI image pattern (`Containerfile`), mutable Ubuntu + gaming session | Upstream ublue-os |
| **Brave Browser** | https://brave.com · https://brave-browser-apt-release.s3.brave.com | Preinstalled browser | Brave ToS + upstream |
| **Mozilla Firefox (.deb)** | https://packages.mozilla.org/apt | Configured repo (not preinstalled) | Mozilla |
| **Flathub** | https://dl.flathub.org/repo/flathub.flatpakrepo | Flatpak remote for Discover | Per-app |
| **KDE Plasma / Plasma Mobile** | https://kde.org | Plasma Wayland desktop; helpers in `vendor/Plasma-Mobile/` | GPL (KDE) |
| **greetd** | Ubuntu packages | Session manager (gaming boot + Plasma switch) | Upstream greetd |

---

## Kernel and firmware

Extended detail: [`vendor/kernel/CREDITS.md`](vendor/kernel/CREDITS.md).

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **Linux kernel (kernel.org)** | https://cdn.kernel.org/pub/linux/kernel · https://www.kernel.org | Vanilla tarball built by `vendor/kernel/make.sh` | GPL-2.0 |
| **Armbian build** | https://github.com/armbian/build | SM8550 patch set (AYN Odin 2 / Mini / Portal / Thor DTS, rsinput, panels, audio, etc.) | GPL-2.0 |
| **Armbian firmware** | https://github.com/armbian/firmware | Device firmware in `vendor/kernel/output/.../firmware/` | Upstream |
| **ROCKNIX distribution** | https://github.com/ROCKNIX/distribution | ABL `KERNEL` model, UFS `ROCKNIX`+`STORAGE` layout, deep-suspend patches | GPL-2.0 / upstream |
| **ROCKNIX PR #2952** | https://github.com/ROCKNIX/distribution/pull/2952 | UFS hibern8/relink, IPCC wake, Thor tsens (`patches/masi/1006`–`1013`; **jaewun**) | Upstream |
| **ROCKNIX-ABL** | https://github.com/ROCKNIX/abl | Dual-boot Linux/Android model (ABL binary not redistributed) | Upstream |
| **Batocera.linux** | https://github.com/batocera-linux/batocera.linux · https://wiki.batocera.org/hardware:ayn | Sensor Core DT, AYN Odin 2 / Thor gyro conventions | GPL-2.0+ |
| **Batocera Custom Arm Builds (suckbluefrog)** | https://github.com/suckbluefrog/Batocera-Custom-Arm-Builds | FastRPC SensorsPD + legacy ioctl port (`1025`/`1026`) | Upstream |
| **Batocera Custom Qualcomm Builds (MaSieS4Fun)** | https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds | Haptics DT wiring, panel/LED references | Upstream |
| **LineageOS AYN kernel-ack** | Public tree `android_kernel_ayn_kernel-ack` | Retroid Pocket 6 DTS → `patches/masi/qcs8550-retroidpocket-rp6.dts` | AOSP/Lineage |
| **Teguh Sobirin** | Copyright in ROCKNIX DTS | AYANEO Pocket ACE / DMG / DS / EVO / S1 | Upstream |
| **Philippe Simons** | Panel patches in MaSi kernel | Pocket DMG (`1020`), DS secondary (`1021`) | Upstream |
| **thorch-os/thorch** | https://github.com/thorch-os/thorch | Thor touch payload, CH13726A/FT5452 kernel patches | Upstream |
| **MaSi-OS Kernel Updater** | https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater | `vendor/kernel/` SM8550 gaming kernel tree | Scripts MIT; kernel GPL-2.0 |
| **Qualcomm / Linaro** | Downstream drivers (`qcom-hv-haptics`, etc.) | Steam FF haptics, PMIC | GPL-2.0 |
| **giroscopio** (companion) | External project (kernel docs) | Full gyro userspace (not built by `./make.sh`) | See giroscopio repo |

---

## Graphics (Mesa, gamescope, overlays)

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **Mesa 3D** | https://archive.mesa3d.org · https://gitlab.freedesktop.org/mesa/mesa | Turnip / Freedreno Vulkan (`vendor/mesa/`, 26.1.6) | MIT (Mesa) |
| **Batocera Custom Qualcomm Builds** | https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds | Adreno 7XX Vulkan sync fix (`vendor/mesa/patches/SM8550/001-fix-freedreno-vulkan.patch`) | Upstream |
| **ROCKNIX Mesa SM8550** | https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/graphics/mesa/patches/SM8550 | IR3 bindless UBO patch | Upstream |
| **MESA Easy Manager** | https://github.com/MaSieS4Fun/MESA-Easy-Manager | GTK Turnip switcher; patches in [`vendor/MESA-Easy-Manager/docs/PATCH_SOURCES.md`](vendor/MESA-Easy-Manager/docs/PATCH_SOURCES.md) | See repo |
| **gamescope (Valve)** | https://github.com/ValveSoftware/gamescope | Gaming Mode compositor for Adreno 740 (`vendor/gamescope/`) | BSD-2-Clause |
| **gamescope submodules** | wlroots, libliftoff, vkroots, libdisplay-info, openvr, reshade, SPIRV-Headers | gamescope build deps | Upstream licenses |
| **MangoHud** | https://github.com/flightlessmango/MangoHud | Performance overlay + Steam presets | MIT |
| **lsfg-vk** | https://github.com/PancakeTAS/lsfg-vk | Vulkan frame generation layer | Upstream lsfg-vk |
| **system-fixes/MESA** | In-tree | Dummy `libgbm1`/`libgbm-dev` debs + apt hold | MIT (glue) |

---

## Gaming session (Steam, gamescope, MangoHud)

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **Valve Steam (ARM64 beta)** | https://client-update.steamstatic.com | `steamdeck_publicbeta`, `steamui.so` (`vendor/SteamARM/install-steam-arm`) | Valve Steam Subscriber Agreement |
| **Valve gamescope / SteamOS patterns** | https://github.com/ValveSoftware/gamescope | `gamescope-session`, Deck UI flags | BSD-2-Clause / Valve |
| **steamos-manager stub** | SteamOS pattern | DBus stub for manager integration | In-tree glue |
| **steamos-updatelevel dummy** | Valve Jupiter pattern | Dummy `.deb` for Steam Settings updates | In-tree glue |
| **ChimeraOS / CachyOS session model** | Script/README references | Gaming Mode ↔ Plasma via `steamos-session-select` | Conceptual |
| **SDL2 gamecontroller DB** | Community + rsinput | `/etc/sdl2/qcom-gamecontrollerdb.txt` | Upstream SDL |

---

## Audio (UCM, firmware, PipeWire)

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **Teguh Sobirin** | `<teguh@sobir.in>` (UCM authorship) | ALSA UCM AYN Odin 2 / Thor (`vendor/audio/ucm2/`) | Upstream UCM |
| **Kernel / vendor firmware tree** | `vendor/kernel/output/.../firmware/` | ADSP, WCD938x, AW88166/AW883xx, Q6 topology | GPL-2.0 / Qualcomm firmware |
| **alsa-ucm-conf (Ubuntu)** | Ubuntu packages | Base UCM + symlinks | Upstream ALSA |
| **PipeWire / WirePlumber** | Ubuntu packages | Desktop audio; optional tuning in `vendor/audio/pipewire/` | Upstream |

---

## Decky Loader and bundled plugins

### Decky PluginLoader (runtime)

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **SteamDeckHomebrew / decky-loader** | https://github.com/SteamDeckHomebrew/decky-loader | PluginLoader (x86_64 via Box64/FEX on aarch64) | Decky upstream |
| **SteamDeckHomebrew / decky-installer** | https://github.com/SteamDeckHomebrew/decky-installer | Install script in `scripts/install-decky.sh` | Decky upstream |
| **@decky/api, @decky/ui, @decky/rollup** | npm packages | Decky plugin SDK | Decky upstream |

Installation: `scripts/install-decky.sh`, `vendor/Decky/`, `system_files/usr/libexec/steamos-ubuntu/sync-decky-bundled-plugins.sh`.

### Plugin: SM8550 Power (`power-managment/`)

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **Hooandee / panel-de-control** | https://github.com/Hooandee/panel-de-control | **Primary design and feature reference** for the Decky power control panel (profiles, fan curves, battery/thermal UI, SM8550 handheld power management concepts). SteamOS-Ubuntu adapted and reimplemented this work for Qualcomm SM8550 sysfs, bundled image delivery, and plugin id **`SM8550-Power`**. | See upstream repo |
| **SteamDeckHomebrew / decky-loader** | https://github.com/SteamDeckHomebrew/decky-loader | Decky API (`decky` Python module, `@decky/*` npm) | Decky upstream |
| **Linux kernel / Armbian SM8550** | sysfs `devfreq`, `cpufreq`, thermal, runtime PM | CPU/GPU governors, fan control, UFS keepalive on QCM8550/QCS8550 | GPL-2.0 (kernel interfaces) |
| **ROCKNIX / SM8550 community** | Handheld Qualcomm patterns | Typical sysfs layout (Odin 2, Thor, Portal, Retroid Pocket 6) | Community |
| **SteamOS-Ubuntu (in-tree)** | `vendor/plug-ins-steamos-ubuntu/power-managment/` | Python backend `sm8550_power/*`, React/Rollup frontend | GPL-3.0-or-later (`package.json`) |

Features: Power Saver / Balanced / Performance / Gaming profiles, fan curves, thermal monitor, GPU clock cap via devfreq.

Build: `./vendor/plug-ins-steamos-ubuntu/power-managment/build.sh`

### Plugin: SM8550 LED (`color-leds/`)

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **Hooandee / decky-colores** | https://github.com/Hooandee/decky-colores | **Primary design and feature reference** for handheld RGB LED Decky control (zones, effects, brightness, color presets). SteamOS-Ubuntu adapted this work for AYN SM8550 `pwm-leds-multicolor` sysfs and plugin id **`SM8550-LED`**. | See upstream repo |
| **SteamDeckHomebrew / decky-loader** | https://github.com/SteamDeckHomebrew/decky-loader | Decky API | Decky upstream |
| **Batocera Custom Qualcomm / batoled** | https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds | sysfs RGB via `/sys/class/leds/*` (`multi_intensity`, `brightness`) | Upstream Batocera |
| **Linux LED class (pwm-leds-multicolor)** | Kernel sysfs | Zones: `left-joystick`, `left-side`, `right-joystick`, `right-side` | GPL-2.0 |
| **SteamOS-Ubuntu (in-tree)** | `vendor/plug-ins-steamos-ubuntu/color-leds/` | Python backend `sm8550_led/*` | GPL-3.0-or-later (`package.json`) |

Build: `./vendor/plug-ins-steamos-ubuntu/color-leds/build.sh`

### Plugin: decky-lsfg-vk + LSFG snapshot

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **PancakeTAS / lsfg-vk** | https://github.com/PancakeTAS/lsfg-vk | Vulkan frame generation (`vendor/lsfg-vk/`, `~/lsfg`, `~/.config/lsfg-vk/`) | Upstream lsfg-vk |
| **xXJSONDeruloXx / decky-lsfg-vk** | https://github.com/xXJSONDeruloXx/decky-lsfg-vk | Decky UI for LSFG | BSD-3-Clause (typical upstream) |
| **SteamDeckHomebrew / decky-loader** | SDK | PluginLoader integration | Decky upstream |
| **system-fixes/LSFG-VK/** | In-tree | `plugin_loader.service.d` drop-ins | MIT (glue) |

Staging: `scripts/stage-decky-lsfg-vk-home-into-rootfs.sh`.

### Desktop LEDs (Colorines) — shared LED backend

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **Hooandee / decky-colores** | https://github.com/Hooandee/decky-colores | UI/UX inspiration for multi-zone RGB control (Decky plugin lineage) | See upstream repo |
| **Batocera Custom Qualcomm / batoled** | sysfs RGB approach | CLI `colorines`, KDE plasmoid, Plasma Mobile tile | GPL-2.0-or-later |
| **KDE Plasma** | KDE Frameworks | Tray applet + quick setting | GPL (KDE) |

Path: `vendor/system-fixes/led-colors/` (related to Decky `color-leds`).

---

## Input, gyroscope, and InputPlumber

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **ShadowBlip / InputPlumber** | https://github.com/ShadowBlip/InputPlumber | Virtual Steam Deck pad + SM8550 composite YAML | Upstream |
| **linux-msm / hexagonrpc** | https://github.com/linux-msm/hexagonrpc | `hexagonrpcd` for FastRPC | Upstream |
| **DylanVanAssche / libssc** | https://codeberg.org/DylanVanAssche/libssc | Sensor Core library | Upstream |
| **Batocera qcom-motion** | Adapted in `vendor/masi-motion/` | IMU SSC → uinput / DSU | GPL-3.0+ |
| **gCemuhook v1993 / DSU protocol** | DSU spec | Emulator server `:26760` | Apache-2.0 |
| **masi-motion** | `vendor/masi-motion/` | systemd services, gamepad+IMU → `deck-uhid` | In-tree |
| **gyro-desktop** | `vendor/gyro-desktop/` | Gtk3 gyro UI, Plasma vs Gaming Mode routing | In-tree |
| **thorch-os/thorch** | https://github.com/thorch-os/thorch | Thor dual-touch fixes | Upstream |

---

## Handheld gamepad (fixpad-sm8550)

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **SteamOS-Ubuntu (in-tree)** | `vendor/fixpad-sm8550/` | AYN rsinput stick ABS range fix (±1408 → ±740) + Plasma idle wake while playing on Desktop | MIT (glue) + GPL-3.0 daemon |
| **KDE / freedesktop D-Bus** | `org.freedesktop.ScreenSaver`, `org.kde.Solid.PowerManagement` | Reset screen idle on gamepad activity (Desktop only) | Upstream |
| **Legacy reference** | `vendor/system-fixes/fixpad/` | Earlier manual Odin 2 fixpad prototype (superseded by `fixpad-sm8550` in image bake) | In-tree |

Baked via `vendor/fixpad-sm8550/install.sh` during `finalize-handheld-rootfs.sh`; Gaming Mode hook in `gamescope-session`.

---

## x86 emulation (Box64, FEX)

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **ptitSeb / box64** | https://github.com/ptitSeb/box64 | x86_64 emulation for Decky PluginLoader (`vendor/BOX64/update-box64`) | Upstream Box64 |
| **FEX-Emu / FEX** | https://github.com/FEX-Emu/FEX · https://rootfs.fex-emu.gg/RootFS_links.json | Alternative x86 emu (`scripts/install-fexemu.sh`) | Upstream FEX |

---

## Bundled applications and tools

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **Heroic Games Launcher** | https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher | arm64 build in `/opt/Heroic` | GPL-3.0 |
| **EmuDeck** | https://github.com/EmuDeck/emudeck-electron | arm64 AppImage | Upstream EmuDeck |
| **SteamGridDB / steam-rom-manager** | https://github.com/SteamGridDB/steam-rom-manager | arm64 `.deb` in `/opt/SteamROMManager` | Upstream SRM |
| **Proton ARM Easy Manager** | Inspired by https://github.com/Vysp3r/ProtonPlus | ARM Proton downloader GUI | GPL-3.0 |
| **GloriousEggroll / proton-ge-custom** | https://github.com/GloriousEggroll/proton-ge-custom | Proton-GE source in `data/sources.json` | Upstream |
| **CachyOS / proton-cachyos** | https://github.com/CachyOS/proton-cachyos | Proton-CachyOS ARM | Upstream |
| **NO Steam / Non-Steam Games** | `vendor/NO_Steam/` | ARM non-Steam menu app | In-tree |
| **MESA Easy Manager** | https://github.com/MaSieS4Fun/MESA-Easy-Manager | apt package / optional AppImage | See repo |
| **Easy UFS Install** | https://github.com/MaSieS4Fun/MaSi-OS-UFS-install | UFS install scripts in `vendor/ufs-install/` | GPL-2.0-or-later |

---

## Internal UFS installation

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **MaSi-OS-UFS-install** | https://github.com/MaSieS4Fun/MaSi-OS-UFS-install | `vendor/ufs-install/` — **ROCKNIX + STORAGE** layout only | GPL-2.0-or-later |
| **ROCKNIX ABL** | https://github.com/ROCKNIX/abl | Dual-boot partition model | Upstream |
| **ROCKNIX installtointernal** | https://github.com/ROCKNIX/distribution | Two-partition Linux design reference | Upstream |
| **abootimg** | Ubuntu packages | ABL `KERNEL` pack/repair | GPL |

---

## Apt channel and GitHub Pages

| Source | URL | What we use | License |
|--------|-----|-------------|---------|
| **GitHub Pages** | https://{owner}.github.io/{repo}/apt | Signed flat apt repo | N/A |
| **MaSi packages** | Built by `scripts/build-debs.sh` | `masi-kernel-edge-sm8550`, metapackage, apps | MIT (debian/) + embedded upstream |

Device config: `scripts/install-steamos-ubuntu-apt-source.sh`, `system_files/etc/apt/sources.list.d/steamos-ubuntu.list`.

---

## Build-time download scripts

| Script | URL(s) | Purpose |
|--------|--------|---------|
| `scripts/build-vendor-mesa.sh` | https://archive.mesa3d.org | Mesa tarball |
| `vendor/SteamARM/install-steam-arm` | https://client-update.steamstatic.com | Steam ARM64 client |
| `scripts/install-heroic-into-rootfs.sh` | github.com/Heroic-Games-Launcher/HeroicGamesLauncher | Heroic build |
| `scripts/install-emudeck-into-rootfs.sh` | GitHub releases EmuDeck | AppImage |
| `scripts/install-decky.sh` | GitHub releases decky-loader | PluginLoader |
| `scripts/install-fexemu.sh` | github.com/FEX-Emu/FEX | FEX build |
| `vendor/BOX64/update-box64` | github.com/ptitSeb/box64 | Box64 build |
| `scripts/install-inputplumber.sh` | GitHub releases InputPlumber | InputPlumber `.deb` |
| `vendor/masi-motion/scripts/build.sh` | hexagonrpc + libssc git | FastRPC stack |
| `vendor/kernel/scripts/fetch-rocknix-suspend-patches.*` | raw.githubusercontent.com/ROCKNIX/distribution | Suspend patches |

---

## Design inspiration

| Project | Relationship |
|---------|--------------|
| **Universal Blue / Bazzite** | Mutable image, OCI layers, gaming-first UX |
| **SteamOS / Jupiter (Valve)** | Gamepad UI, gamescope session, manager stubs |
| **ROCKNIX** | SM8550 kernel, ABL, UFS, Mesa patches |
| **Batocera** | Gyro, RGB LED sysfs, haptics, motion |
| **ChimeraOS / CachyOS** | Gaming Mode ↔ desktop session switch |
| **Armbian** | SM8550 kernel/firmware base |
| **ProtonPlus (Vysp3r)** | Proton manager UI → Proton ARM Easy Manager |
| **Hooandee / panel-de-control** | Power Decky plugin design reference |
| **Hooandee / decky-colores** | RGB LED Decky plugin design reference |

---

## Acknowledgements

Thanks to **Hooandee** ([panel-de-control](https://github.com/Hooandee/panel-de-control), [decky-colores](https://github.com/Hooandee/decky-colores)), and maintainers of **kernel.org**, **Armbian**, **ROCKNIX**, **Batocera**, **suckbluefrog**, **thorch-os**, **Valve**, **SteamDeckHomebrew**, **PancakeTAS**, **Flightless Mango**, **ShadowBlip**, **Heroic**, **EmuDeck**, **SteamGridDB**, **FEX-Emu**, **ptitSeb**, **Teguh Sobirin**, **Philippe Simons**, **jaewun**, **LineageOS** AYN work, and everyone who documented ABL/DTB slots and SM8550 handhelds.

---

*Last updated for SteamOS-Ubuntu public release preparation.*
