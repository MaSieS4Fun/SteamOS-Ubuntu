# SteamOS-Ubuntu

SteamOS-like Linux Gaming OS for ARM64 handhelds (SM8550 / Adreno 740), inspired by [Universal Blue](https://github.com/ublue-os) / Bazzite, built on **Ubuntu Resolute**.

## Supported devices

boots on multiple AYN and compatible handhelds via an **ABL multidevice `boot/KERNEL`** (ROCKNIX ABL)[https://github.com/ROCKNIX/abl]:

| Device | Status |
|--------|--------|
| AYN Odin 2 | Supported |
| AYN Odin 2 Portal | Supported |
| AYN Odin 2 Mini | Supported |
| AYN Thor | Supported |
| Retroid Pocket 6 | Supported |
| AYANEO Pocket EVO | Supported |
| AYANEO Pocket ACE | Supported |
| AYANEO Pocket DS | Supported |
| AYANEO Pocket DMG | Supported |
| AYANEO Pocket S 2K | Supported |


Default desktop user created in the image:

| Field    | Value  |
|----------|--------|
| user     | `steam` |
| password | `steam` |

# Decky Loader
- For Decky Loader to work, you need to install an x86_64-to-ARM instruction translation layer on the system.
- In the "ARM-Manager" application menu, you will find installation scripts for BOX64 and FEXEmu.

# Installation:
- First, install [ROCKNIX ABL](https://github.com/ROCKNIX/abl).
- You can use the ABL installation [scripts from Android]([rocknix_abl_Android_Scripts.zip](https://github.com/user-attachments/files/31609601/rocknix_abl_Android_Scripts.zip)
). You must place the `abl_signed-SM8550.elf` ABL file inside the folder.
- Once the ABL is installed, select your device. This will configure the device to boot Linux distributions.
- Use [balenaEtcher](https://etcher.balena.io/) or [Rufus](https://rufus.ie/es/) to flash the [SteamOS-Ubuntu](https://github.com/MaSieS4Fun/SteamOS-Ubuntu/releases) image onto the SD card.
- Once the SD card has been flashed, insert it into your device's SD card reader.

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
