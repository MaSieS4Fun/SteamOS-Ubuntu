# Créditos y fuentes upstream

**SteamOS-Ubuntu** integra software de muchos proyectos de código abierto y de la comunidad handheld ARM64. Este documento lista **todas las fuentes conocidas** usadas en el repositorio, empaquetado, imagen y canal apt.

Las licencias originales de cada componente siguen siendo las de sus respectivos autores. El *glue* del proyecto (scripts, empaquetado, overlays) está bajo **MIT** — ver [`LICENSE`](LICENSE).

Si falta alguna atribución o está mal citada, abre un issue o PR en el repositorio.

---

## Índice

1. [Sistema base](#sistema-base)
2. [Kernel y firmware](#kernel-y-firmware)
3. [Gráficos (Mesa, gamescope, overlays)](#gráficos-mesa-gamescope-overlays)
4. [Sesión gaming (Steam, gamescope, MangoHud)](#sesión-gaming-steam-gamescope-mangohud)
5. [Audio (UCM, firmware, PipeWire)](#audio-ucm-firmware-pipewire)
6. [Decky Loader y plugins incluidos](#decky-loader-y-plugins-incluidos)
7. [Entrada, giroscopio e InputPlumber](#entrada-giroscopio-e-inputplumber)
8. [Emulación x86 (Box64, FEX)](#emulación-x86-box64-fex)
9. [Aplicaciones y herramientas empaquetadas](#aplicaciones-y-herramientas-empaquetadas)
10. [Instalación en UFS interna](#instalación-en-ufs-interna)
11. [Canal apt y GitHub Pages](#canal-apt-y-github-pages)
12. [Scripts de descarga en tiempo de build](#scripts-de-descarga-en-tiempo-de-build)
13. [Inspiración y patrones de diseño](#inspiración-y-patrones-de-diseño)
14. [Agradecimientos](#agradecimientos)

---

## Sistema base

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **Ubuntu (Resolute, ports)** | https://ports.ubuntu.com/ubuntu-ports | Rootfs base, Plasma, paquetes apt (`packages/base`, `packages/plasma`, `packages/gaming`, etc.) | Ubuntu / Debian (varias) |
| **Universal Blue / Bazzite** | https://github.com/ublue-os | Patrón de imagen OCI (`Containerfile`), enfoque “mutable Ubuntu + gaming session” | Upstream ublue-os |
| **Brave Browser** | https://brave.com · https://brave-browser-apt-release.s3.brave.com | Navegador preinstalado (`build_files/30-brave-and-mozilla-repos.sh`) | Brave ToS + upstream |
| **Mozilla Firefox (.deb)** | https://packages.mozilla.org/apt | Repositorio configurado (no preinstalado) | Mozilla |
| **Flathub** | https://dl.flathub.org/repo/flathub.flatpakrepo | Remote Flatpak para Discover (`build_files/40-desktop-polish.sh`) | Varía por app |
| **KDE Plasma / Plasma Mobile** | https://kde.org | Escritorio Plasma Wayland; helpers en `vendor/Plasma-Mobile/` | GPL (KDE) |
| **greetd** | Paquetes Ubuntu | Gestor de sesión (modelo SteamOS/CachyOS: gaming boot + switch a Plasma) | Upstream greetd |

---

## Kernel y firmware

Detalle ampliado en [`vendor/kernel/CREDITS.md`](vendor/kernel/CREDITS.md).

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **Linux kernel (kernel.org)** | https://cdn.kernel.org/pub/linux/kernel · https://www.kernel.org | Tarball vanilla compilado por `vendor/kernel/make.sh` | GPL-2.0 |
| **Armbian build** | https://github.com/armbian/build | Parches SM8550 (DTS AYN Odin 2 / Mini / Portal / Thor, rsinput, paneles, audio, etc.) | GPL-2.0 (parches/kernel) |
| **Armbian firmware** | https://github.com/armbian/firmware | Firmware de dispositivo en `vendor/kernel/output/.../firmware/` | Upstream |
| **ROCKNIX distribution** | https://github.com/ROCKNIX/distribution | Modelo ABL `KERNEL`, layout UFS `ROCKNIX`+`STORAGE`, parches deep-suspend | GPL-2.0 / upstream |
| **ROCKNIX PR #2952** | https://github.com/ROCKNIX/distribution/pull/2952 | Parches UFS hibern8/relink, IPCC wake, Thor tsens (`patches/masi/1006`–`1013`; autor **jaewun**) | Upstream |
| **ROCKNIX-ABL** | https://github.com/ROCKNIX/abl | Modelo dual-boot Linux/Android (no se redistribuye el binario ABL) | Upstream |
| **Batocera.linux** | https://github.com/batocera-linux/batocera.linux · https://wiki.batocera.org/hardware:ayn | DT Sensor Core, convenciones gyro AYN Odin 2 / Thor | GPL-2.0+ |
| **Batocera Custom Arm Builds (suckbluefrog)** | https://github.com/suckbluefrog/Batocera-Custom-Arm-Builds | FastRPC SensorsPD + puerto ioctl legacy (`1025`/`1026`) | Upstream |
| **Batocera Custom Qualcomm Builds (MaSieS4Fun)** | https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds | Cableado haptics DT, referencias panel/LED | Upstream |
| **LineageOS AYN kernel-ack** | Árbol público `android_kernel_ayn_kernel-ack` | DTS Retroid Pocket 6 → `patches/masi/qcs8550-retroidpocket-rp6.dts` | Upstream AOSP/Lineage |
| **Teguh Sobirin** | Copyright en DTS ROCKNIX | AYANEO Pocket ACE / DMG / DS / EVO / S1 | Upstream |
| **Philippe Simons** | Parches panel en kernel MaSi | Pocket DMG (`1020`), DS secundario (`1021`) | Upstream |
| **thorch-os/thorch** | https://github.com/thorch-os/thorch | Payload touch Thor (`payload/fix-thor-screen/`), parches kernel CH13726A/FT5452 | Upstream |
| **MaSi-OS Kernel Updater** | https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater | Árbol `vendor/kernel/` (origen del kernel gaming SM8550) | Scripts MIT; kernel GPL-2.0 |
| **Qualcomm / Linaro** | Drivers downstream (`qcom-hv-haptics`, etc.) | Haptics Steam FF, PMIC | GPL-2.0 |
| **giroscopio** (companion) | Proyecto externo citado en kernel docs | Userspace gyro completo (no incluido en `./make.sh`) | Ver repo giroscopio |

---

## Gráficos (Mesa, gamescope, overlays)

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **Mesa 3D** | https://archive.mesa3d.org · https://gitlab.freedesktop.org/mesa/mesa | Turnip / Freedreno Vulkan (`vendor/mesa/`, versión 26.1.6) | MIT (Mesa) |
| **Batocera Custom Qualcomm Builds** | https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds | Parche sync Vulkan Adreno 7XX (`vendor/mesa/patches/SM8550/001-fix-freedreno-vulkan.patch`) | Upstream |
| **ROCKNIX Mesa SM8550** | https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/graphics/mesa/patches/SM8550 | Parche UBO IR3 bindless (`0001-freedreno-ir3-vulkan-disable-bindless-ubo-const-lowering.patch`) | Upstream |
| **MESA Easy Manager** | https://github.com/MaSieS4Fun/MESA-Easy-Manager | App GTK para compilar/cambiar `libvulkan_freedreno.so`; parches documentados en [`vendor/MESA-Easy-Manager/docs/PATCH_SOURCES.md`](vendor/MESA-Easy-Manager/docs/PATCH_SOURCES.md) | Ver repo |
| **gamescope (Valve)** | https://github.com/ValveSoftware/gamescope | Compositor Gaming Mode adaptado Adreno 740 (`vendor/gamescope/`) | BSD-2-Clause |
| **gamescope submodules** | https://github.com/Joshua-Ashton/wlroots · https://gitlab.freedesktop.org/emersion/libliftoff · https://github.com/Joshua-Ashton/vkroots · https://gitlab.freedesktop.org/emersion/libdisplay-info · https://github.com/ValveSoftware/openvr · https://github.com/Joshua-Ashton/reshade · https://github.com/KhronosGroup/SPIRV-Headers | Dependencias de build gamescope | Licencias upstream |
| **MangoHud** | https://github.com/flightlessmango/MangoHud | Overlay rendimiento + presets Steam (`vendor/MangoHud/`, `~/.config/MangoHud/steam/`) | MIT |
| **lsfg-vk** | https://github.com/PancakeTAS/lsfg-vk | Capa Vulkan frame generation (`vendor/lsfg-vk/`, `liblsfg-vk.so`) | Upstream lsfg-vk |
| **system-fixes/MESA** | In-tree | `.deb` dummy `libgbm1`/`libgbm-dev` + apt hold (evitar Mesa Ubuntu) | MIT (glue) |

---

## Sesión gaming (Steam, gamescope, MangoHud)

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **Valve Steam (ARM64 beta)** | https://client-update.steamstatic.com | Cliente `steamdeck_publicbeta`, `steamui.so` (`vendor/SteamARM/install-steam-arm`) | Valve Steam Subscriber Agreement |
| **Valve gamescope / SteamOS patterns** | https://github.com/ValveSoftware/gamescope | `gamescope-session`, flags `-gamepadui -steamos3 -steampal -steamdeck` | BSD-2-Clause / Valve |
| **steamos-manager stub** | Patrón SteamOS | DBus stub para integración manager | In-tree glue |
| **steamos-updatelevel dummy** | Patrón Valve Jupiter | `.deb` dummy para “Check for updates” en Steam Settings (`vendor/system-fixes/steamos-updatelevel/`) | In-tree glue |
| **ChimeraOS / CachyOS session model** | Referencias en scripts/README | Switch Gaming Mode ↔ Plasma vía `steamos-session-select` | Conceptual |
| **SDL2 gamecontroller DB** | Comunidad + rsinput | `/etc/sdl2/qcom-gamecontrollerdb.txt` (AYN Odin2 Gamepad) | Upstream SDL |

---

## Audio (UCM, firmware, PipeWire)

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **Teguh Sobirin** | `<teguh@sobir.in>` (autoría UCM) | Perfiles ALSA UCM AYN Odin 2 / Thor (`vendor/audio/ucm2/`) | Upstream UCM |
| **Kernel / vendor firmware tree** | `vendor/kernel/output/.../firmware/` | ADSP, WCD938x, AW88166/AW883xx, topología Q6 (`vendor/audio/firmware/`) | GPL-2.0 / Qualcomm firmware |
| **alsa-ucm-conf (Ubuntu)** | Paquetes Ubuntu | Base UCM + symlinks `vendor/audio/ucm2/conf.d/sm8550/` | Upstream ALSA |
| **PipeWire / WirePlumber** | Paquetes Ubuntu | Audio de escritorio; tuning opcional `vendor/audio/pipewire/` | Upstream |

---

## Decky Loader y plugins incluidos

### Decky PluginLoader (runtime)

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **SteamDeckHomebrew / decky-loader** | https://github.com/SteamDeckHomebrew/decky-loader | PluginLoader (x86_64 vía Box64/FEX en aarch64); unit systemd | Upstream Decky |
| **SteamDeckHomebrew / decky-installer** | https://github.com/SteamDeckHomebrew/decky-installer | Script de instalación referenciado en `scripts/install-decky.sh` | Upstream Decky |
| **@decky/api, @decky/ui, @decky/rollup** | Paquetes npm Decky | SDK frontend plugins | Upstream Decky |

Instalación: `scripts/install-decky.sh`, menú `vendor/Decky/`, sync `system_files/usr/libexec/steamos-ubuntu/sync-decky-bundled-plugins.sh`.

### Plugin: SM8550 Power (`power-managment/`)

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **SteamDeckHomebrew / decky-loader** | https://github.com/SteamDeckHomebrew/decky-loader | API Decky (`decky` Python module, `@decky/*` npm) | Upstream Decky |
| **Linux kernel / Armbian SM8550** | sysfs `devfreq`, `cpufreq`, thermal, runtime PM | Perfiles CPU/GPU, ventilador, UFS keepalive para QCM8550/QCS8550 | GPL-2.0 (kernel interfaces) |
| **ROCKNIX / comunidad SM8550** | Patrones handheld Qualcomm | Layout sysfs típico Odin 2, Thor, Portal, Retroid Pocket 6 | Comunidad |
| **SteamOS-Ubuntu (in-tree)** | `vendor/plug-ins-steamos-ubuntu/power-managment/` | Backend Python `sm8550_power/*`, frontend React/Rollup, id Decky **`SM8550-Power`** | GPL-3.0-or-later (`package.json`) |

Funciones: perfiles Power Saver / Balanced / Performance / Gaming, curvas de ventilador, monitor térmico, tope GPU vía devfreq.

Build frontend: `./vendor/plug-ins-steamos-ubuntu/power-managment/build.sh`

### Plugin: SM8550 LED (`color-leds/`)

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **SteamDeckHomebrew / decky-loader** | https://github.com/SteamDeckHomebrew/decky-loader | API Decky | Upstream Decky |
| **Batocera Custom Qualcomm / batoled** | https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds · enfoque sysfs `pwm-leds-multicolor` | Control RGB vía `/sys/class/leds/*` (`multi_intensity`, `brightness`) | Upstream Batocera |
| **Linux LED class (pwm-leds-multicolor)** | Kernel sysfs | Zonas left/right joystick y side en SM8550 AYN | GPL-2.0 |
| **SteamOS-Ubuntu (in-tree)** | `vendor/plug-ins-steamos-ubuntu/color-leds/` | Backend `sm8550_led/*`, id Decky **`SM8550-LED`** | GPL-3.0-or-later (`package.json`) |

Zonas esperadas: `left-joystick`, `left-side`, `right-joystick`, `right-side`.

Build frontend: `./vendor/plug-ins-steamos-ubuntu/color-leds/build.sh`

### Plugin: decky-lsfg-vk + snapshot LSFG

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **PancakeTAS / lsfg-vk** | https://github.com/PancakeTAS/lsfg-vk | Biblioteca Vulkan frame generation (`vendor/lsfg-vk/`, `~/lsfg`, `~/.config/lsfg-vk/`) | Upstream lsfg-vk |
| **xXJSONDeruloXx / decky-lsfg-vk** | https://github.com/xXJSONDeruloXx/decky-lsfg-vk | UI Decky para LSFG (plugin en snapshot `vendor/plug-ins-steamos-ubuntu/decky-lsfg-vk/`) | BSD-3-Clause (típico upstream) |
| **xXJSONDeruloXx / lsfg-vk (noui)** | Referenciado en empaquetado plugin | Assets / zip sin UI | Upstream |
| **SteamDeckHomebrew / decky-loader** | SDK Decky | Integración PluginLoader | Upstream Decky |
| **system-fixes/LSFG-VK/** | In-tree | Drop-ins `plugin_loader.service.d` (`fast-stop.conf`, `fex-steam-rootfs.conf`) | MIT (glue) |

Staging: `scripts/stage-decky-lsfg-vk-home-into-rootfs.sh` + bundle en `/usr/share/steamos-ubuntu/decky-plugins/`.

### LED de escritorio (Colorines) — mismo backend que LEDs

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **Batocera Custom Qualcomm / batoled** | Mismo enfoque sysfs RGB | CLI `colorines`, plasmoid KDE `org.masi.colorines`, tile Plasma Mobile | GPL-2.0-or-later |
| **KDE Plasma** | Frameworks KDE | Applet bandeja + quick setting | GPL (KDE) |
| **Armbian leds.conf** | Patrón Armbian | Persistencia opcional `/etc/armbian-leds.conf` | Upstream Armbian |

Ruta: `vendor/system-fixes/led-colors/` (comparte lógica con plugin Decky `color-leds`).

---

## Entrada, giroscopio e InputPlumber

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **ShadowBlip / InputPlumber** | https://github.com/ShadowBlip/InputPlumber | Pad virtual Steam Deck + composite YAML SM8550 (`scripts/install-inputplumber.sh`) | Upstream |
| **linux-msm / hexagonrpc** | https://github.com/linux-msm/hexagonrpc | `hexagonrpcd` para FastRPC (`vendor/masi-motion/scripts/build.sh`) | Upstream |
| **DylanVanAssche / libssc** | https://codeberg.org/DylanVanAssche/libssc | Biblioteca Sensor Core | Upstream |
| **Batocera qcom-motion** | Adaptado en `vendor/masi-motion/src/qcom-motion/` | Puente IMU SSC → uinput / DSU | GPL-3.0+ (integración) |
| **gCemuhook v1993 / DSU protocol** | Protocolo DSU | Servidor `:26760` para emuladores (Apache-2.0 en headers fuente) | Apache-2.0 |
| **masi-motion** | `vendor/masi-motion/` | Servicios systemd, composite gamepad+IMU → `deck-uhid` | In-tree |
| **gyro-desktop** | `vendor/gyro-desktop/` | UI Gtk3 sensibilidad gyro, switch Plasma vs Gaming Mode | In-tree |
| **giroscopio-mal-aolicado** | Sync opcional desde `vendor/masi-motion/` | Fuentes hexagon/libssc si faltan | Ver repo companion |
| **thorch-os/thorch** | https://github.com/thorch-os/thorch | Fixes touch pantalla dual Thor (`vendor/system-fixes/Thor/`) | Upstream |
| **fixpad** | `vendor/system-fixes/fixpad/` | Rango sticks Odin 2 + wake gamepad (`gamepad-wake.py`) | In-tree |

---

## Emulación x86 (Box64, FEX)

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **ptitSeb / box64** | https://github.com/ptitSeb/box64 | Emulación x86_64 para Decky PluginLoader y apps x86 (`vendor/BOX64/update-box64`) | Upstream Box64 |
| **FEX-Emu / FEX** | https://github.com/FEX-Emu/FEX · https://rootfs.fex-emu.gg/RootFS_links.json | Emulación x86 alternativa (`scripts/install-fexemu.sh`) | Upstream FEX |

---

## Aplicaciones y herramientas empaquetadas

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **Heroic Games Launcher** | https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher | Build arm64 en `/opt/Heroic` (`scripts/install-heroic-into-rootfs.sh`) | GPL-3.0 |
| **EmuDeck** | https://github.com/EmuDeck/emudeck-electron | AppImage arm64 v2.6.1 (`scripts/install-emudeck-into-rootfs.sh`) | Upstream EmuDeck |
| **SteamGridDB / steam-rom-manager** | https://github.com/SteamGridDB/steam-rom-manager | `.deb` arm64 v2.5.44 en `/opt/SteamROMManager` (`scripts/fetch-steam-rom-manager.sh`) | Upstream SRM |
| **Proton ARM Easy Manager** | Inspirado en https://github.com/Vysp3r/ProtonPlus | GUI descarga Proton ARM (`vendor/Proton-ARM-Easy-Manager/`) | GPL-3.0 |
| **GloriousEggroll / proton-ge-custom** | https://github.com/GloriousEggroll/proton-ge-custom | Fuente Proton-GE en `data/sources.json` | Upstream |
| **CachyOS / proton-cachyos** | https://github.com/CachyOS/proton-cachyos | Fuente Proton-CachyOS ARM (`scripts/install-proton-cachyos-arm.sh`, `sources.json`) | Upstream |
| **SpookySkeletons / proton-ge-rtsp** | https://github.com/SpookySkeletons/proton-ge-rtsp | Fuente Proton-GE RTSP | Upstream |
| **Etaash-mathamsetty / Proton** | https://github.com/Etaash-mathamsetty/Proton | Fuente Proton-EM | Upstream |
| **Dawn Winery / dwproton** | https://dawn.wine/dawn-winery/dwproton | Fuente DW-Proton (API Forgejo) | Upstream |
| **NO Steam / Non-Steam Games** | `vendor/NO_Steam/` | App menú juegos ARM fuera de Steam + icono `no-steam-games.png` | In-tree |
| **MESA Easy Manager** | https://github.com/MaSieS4Fun/MESA-Easy-Manager | Paquete apt / AppImage opcional | Ver repo |
| **Easy UFS Install** | https://github.com/MaSieS4Fun/MaSi-OS-UFS-install | Scripts UFS en `vendor/ufs-install/` | GPL-2.0-or-later |

---

## Instalación en UFS interna

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **MaSi-OS-UFS-install** | https://github.com/MaSieS4Fun/MaSi-OS-UFS-install | `vendor/ufs-install/` — reparticionado UFS, layout **ROCKNIX + STORAGE** | GPL-2.0-or-later |
| **ROCKNIX ABL** | https://github.com/ROCKNIX/abl | Modelo particiones dual-boot (Android `userdata` + Linux) | Upstream |
| **ROCKNIX installtointernal** | https://github.com/ROCKNIX/distribution | Patrón dos particiones Linux (referencia de diseño) | Upstream |
| **abootimg** | Paquetes Ubuntu (`packages/ufs-tools`) | Empaquetado/reparación imagen `KERNEL` ABL | GPL |

Scripts: `install-masios-to-internal.sh`, `ufs-diagnose.sh`, `ufs-fix-internal-boot.sh`, `ufs-bootimg.sh`.

---

## Canal apt y GitHub Pages

| Fuente | URL | Qué usamos | Licencia |
|--------|-----|------------|----------|
| **GitHub Pages** | https://{owner}.github.io/{repo}/apt | Repositorio apt plano firmado (`scripts/generate-apt-repo.sh`, `gh-pages`) | N/A |
| **Paquetes MaSi** | Generados por `scripts/build-debs.sh` | `masi-kernel-edge-sm8550`, metapaquete, `mesa-easy-manager`, `easy-ufs-install`, `proton-arm-easy-manager`, `no-steam-games`, `gyro-desktop`, etc. | MIT (debian/) + upstream embebido |

Config dispositivo: `scripts/install-steamos-ubuntu-apt-source.sh`, `system_files/etc/apt/sources.list.d/steamos-ubuntu.list`.

---

## Scripts de descarga en tiempo de build

| Script | URL(s) | Propósito |
|--------|--------|-----------|
| `scripts/build-vendor-mesa.sh` | https://archive.mesa3d.org | Tarball Mesa |
| `vendor/SteamARM/install-steam-arm` | https://client-update.steamstatic.com | Cliente Steam ARM64 |
| `scripts/install-proton-cachyos-arm.sh` | GitHub API → CachyOS releases | Proton-CachyOS ARM (opt-in) |
| `scripts/install-heroic-into-rootfs.sh` | https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher.git | Build Heroic |
| `scripts/install-emudeck-into-rootfs.sh` | GitHub releases EmuDeck | AppImage arm64 |
| `scripts/fetch-steam-rom-manager.sh` | GitHub releases SRM | `.deb` arm64 |
| `scripts/install-decky.sh` | GitHub API + releases decky-loader; raw unit files | PluginLoader |
| `scripts/install-fexemu.sh` | github.com/FEX-Emu/FEX + rootfs.fex-emu.gg | Build FEX |
| `vendor/BOX64/update-box64` | github.com/ptitSeb/box64 | Build Box64 |
| `scripts/install-inputplumber.sh` | GitHub releases InputPlumber | `.deb` InputPlumber |
| `vendor/masi-motion/scripts/build.sh` | hexagonrpc + libssc git | FastRPC stack |
| `vendor/kernel/scripts/fetch-rocknix-suspend-patches.*` | raw.githubusercontent.com/ROCKNIX/distribution | Parches suspend |
| `build_files/30-brave-and-mozilla-repos.sh` | Brave S3 + packages.mozilla.org | Repos navegadores |
| `build_files/40-desktop-polish.sh` | dl.flathub.org | Flathub |
| `vendor/MESA-Easy-Manager/packaging/build-appimage.sh` | github.com/AppImage/appimagetool | AppImage tool |

---

## Inspiración y patrones de diseño

| Proyecto | Relación |
|----------|----------|
| **Universal Blue / Bazzite** | Imagen mutable, capas OCI, UX gaming-first |
| **SteamOS / Jupiter (Valve)** | Gamepad UI, gamescope session, stubs manager/updatelevel |
| **ROCKNIX** | Kernel SM8550, ABL, UFS, parches Mesa |
| **Batocera** | Gyro, LEDs RGB sysfs, haptics, motion |
| **ChimeraOS / CachyOS** | Switch sesión gaming ↔ escritorio |
| **Armbian** | Base kernel/firmware SM8550 |
| **ProtonPlus (Vysp3r)** | Modelo UI gestor Proton → Proton ARM Easy Manager |

---

## Agradecimientos

Gracias a los mantenedores y contribuidores de **kernel.org**, **Armbian**, **ROCKNIX**, **Batocera**, **suckbluefrog**, **thorch-os**, **Valve**, **SteamDeckHomebrew**, **PancakeTAS**, **Flightless Mango**, **ShadowBlip**, **Heroic**, **EmuDeck**, **SteamGridDB**, **FEX-Emu**, **ptitSeb**, **Teguh Sobirin**, **Philippe Simons**, **jaewun**, **LineageOS** AYN, y toda la comunidad que documentó ABL, DTB slots y handhelds SM8550.

---

*Última revisión: documento preparado para publicación del repositorio SteamOS-Ubuntu.*
