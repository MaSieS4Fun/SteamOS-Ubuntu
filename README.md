# SteamOS-Ubuntu

Gaming OS for ARM64 handhelds (SM8550 / Adreno 740), inspired by [Universal Blue](https://github.com/ublue-os) / Bazzite, built on **Ubuntu Resolute**.

Steam Deck–style session: **gamescope** → **Steam Gamepad UI**, with a custom SM8550 kernel, board audio (UCM + firmware), and Steam ARM64 beta.

## Layout

```
SteamOS-Ubuntu/
  Containerfile          # OCI image (ublue-style layers)
  Justfile               # build recipes
  packages/              # apt package lists
  build_files/           # scripts run inside the image build
  system_files/          # overlay copied into the rootfs
  scripts/               # host-side build / flash helpers
  vendor/                # hardware-specific drops (do not invent)
    audio/               # SM8550 ALSA UCM + firmware + PipeWire
    kernel/              # SM8550 gaming kernel (make.sh / update.sh)
    gamescope/           # Adreno 740–adapted gamescope
    SteamARM/            # Steam ARM64 beta installer
    mesa/ MangoHud/      # optional extras
  output/                # build artifacts
```

## Requirements

- aarch64 host (or qemu-user + binfmt)
- `podman` or `docker`
- `just` (optional)
- root for image bake / flash

## Quick start

Mutable Ubuntu (like CachyOS): normal `apt`, no ostree. Steam/gamescope session aimed at Bazzite UX.

Disk image is **GPT**:
- **p1 VFAT** `PARTLABEL=BOOT` → `/boot/KERNEL` (ABL)
- **p2 ext4** `PARTLABEL=STORAGE` → rootfs  
Firmware comes **only** from `vendor/kernel` (Ubuntu `linux-firmware` is purged).

```bash
git clone <repo> SteamOS-Ubuntu && cd SteamOS-Ubuntu

# ONE command — installs host deps, builds rootfs, compiles kernel + mesa/gamescope/
# mangohud/steam, finalizes, writes GPT .img. No manual phases.
sudo ./create-image.sh
```

Optional shortcuts (not required for a normal bake):

```bash
# Keep existing output/rootfs; rebuild kernel + vendor stack + GPT image
sudo ./create-image.sh --reuse-rootfs

# Keep existing output/rootfs; ONLY apply latest finalize + pack GPT .img (minutes)
sudo ./create-image.sh --finalize-img

# Skip apt install of host deps (already set up)
SKIP_HOST_DEPS=1 sudo ./create-image.sh
```

Vendor userspace (required for Adreno 740):
- `vendor/mesa/patches/SM8550` → Mesa **26.1.6**
- `vendor/gamescope` → compile (stock gamescope will not work)
- `vendor/MangoHud` → compile
- `vendor/SteamARM` → download + **first Steam updater run**

Default desktop user created in the image:

| Field    | Value  |
|----------|--------|
| user     | `steam` |
| password | `steam` |
| groups   | `sudo,audio,video,render,input,plugdev,netdev,bluetooth,games` |

Steam client is **baked into the image** (`steamdeck_publicbeta` + `steamui.so`). First boot uses Deck Gamepad UI (`steam-mode=deck`: `-gamepadui -steamos3 -steampal -steamdeck`), with SystemDisplayManager on **wayland: modeset** and MangoHud at `~/.config/MangoHud/steam/`.

Clean rebuild (kernel is reused automatically if `vendor/kernel/output/*-kbase` exists):

```bash
# Optional: wipe userspace build caches for a truly clean Mesa/gamescope/Steam bake
#   sudo rm -rf output/rootfs output/src/mesa-*   # and gamescope meson dirs if any
sudo ./create-image.sh
```

`scripts/finalize-handheld-rootfs.sh` runs at the end of every image build (boot trim, steam-mode=deck, MangoHud steam configs, steamos-manager fix).

## Gaming Mode / Steam Deck (on Ubuntu)

Same idea as CachyOS handheld, on Ubuntu Resolute:

1. **Bake** (builder online): `install-steam-arm-into-rootfs.sh` seeds **`steamdeck_publicbeta`**, runs `steam -steamdeck -exitsteam` until `steamui.so` + `.installed` exist.
2. **Session**: `gamescope-session` → `launch-steam -gamepadui -steamos3 -steampal -steamdeck -noverifyfiles -noshaders` (`steam-mode=deck`).
3. **Display**: gamescope Wayland compositor + Xwayland for Steam/CEF; DisplayManager via `GAMESCOPE_WAYLAND_DISPLAY` → `wayland: modeset`.
4. **Overlay**: `~/.config/MangoHud/steam/{MangoHud.conf,presets.conf}` (+ system copy under `/usr/share/sm8550-steamos/MangoHud/steam/`).

Re-bake only Steam into a mounted rootfs:

```bash
sudo ./scripts/bake-steam-deck-into-rootfs.sh /media/odin2/STORAGE
sudo ./scripts/finalize-handheld-rootfs.sh /media/odin2/STORAGE
```

Full image: `sudo ./create-image.sh` (vendor stack includes the Steam bake; fails the build if steamui is missing).

### Desktop Mode (Plasma)

Deck-like session switch (CachyOS/SteamOS model, via **greetd** — not SDDM):

- Boot **always** → Gaming Mode (`steamos-force-gaming-boot` + oneshot).
- Steam **Switch to Desktop** → `steamos-session-select plasma` → Plasma Wayland.
- Plasma app **Return to Gaming Mode** → `steamos-session-select gamescope`.

```bash
# Apply session helpers to a mounted STORAGE without full rebuild:
sudo ./scripts/finalize-handheld-rootfs.sh /media/odin2/STORAGE
```

Or manually copy `system_files` overlay and reboot.

### Snap / browsers

- Snap is purged, pinned to priority `-1`, and masked.
- Image browser: **Brave only** (official Brave apt).
- `apt install firefox` uses Mozilla’s `.deb` repo (configured, not preinstalled) — never a snap stub.

### Controller (SDL2)

Built-in `AYN Odin2 Gamepad` (rsinput) is treated as an SDL2 gamecontroller (`/etc/sdl2/qcom-gamecontrollerdb.txt` + udev). Pad→mouse helpers (`antimicro`, `input-remapper`, `xserver-xorg-input-joystick`) are excluded.

## Audio

`vendor/audio/` is **enabled by default**. Set `SKIP_AUDIO=1` only to skip it.
Early-boot `aw88166` PLL/IIS retry spam on the panel is silenced by MaSi patch
`1033-sound-aw88166-quiet-early-iis-probe` (rebuild kernel + `vendor/kernel/update.sh`).
Audio still works; messages move to `dev_dbg` only.

Install into a mounted rootfs without rebuilding the image:

```bash
sudo ./vendor/audio/scripts/install-into-rootfs.sh /media/odin2/STORAGE
```

## License

Project glue: MIT. Vendor trees keep their own licenses. See [`CREDITS.md`](CREDITS.md) for full upstream attribution.
