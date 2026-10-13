# Changelog

## [1.1.0] - 2026-10-13

AYN Odin 3 (SM8750) uses the same image as the SM8550 handhelds. In ROCKNIX-ABL choose **Set the Device → AYN Odin 3**.

### Kernel 7.2.10 for cards already flashed

`uname -r` is `7.2.10-edge`. The apt package is `masi-kernel-edge-sm8550` version `7.2.10-edge-sm8550-1`, which replaces `7.2.2-edge-sm8550-3`.

Each image is formatted with its own ext4 UUID. The `KERNEL` file inside the package was built for one card and must not be copied onto another. On install, `apt-install.sh` reads the UUID of the root filesystem that is running and repacks `/boot/KERNEL` with that UUID. If that UUID cannot be read, the install stops instead of writing the bundle UUID.

```bash
sudo apt update && sudo apt upgrade
sudo reboot
uname -r   # 7.2.10-edge
```

ABL after reboot: Vol Down → Set the Device → your model → Linux → START.

### Odin 3

- Audio profiles: Off, HiFi quality Music (DisplayPort, Speaker), Pro Audio. HiFi is selected while a DisplayPort dock is connected, and Pro Audio when it is removed. The topology includes the HDMI PCM (`MultiMedia4`).
- Gaming Mode keeps a single Steam layout. The raw pad is not exposed next to `deck-uhid`, so the touch panel does not switch the glyphs to Xbox.
- Boot shows **SteamOS-Ubuntu / Starting** on the panel. An OLED no longer stays fully black for the whole wait. The first seconds, before the panel driver starts, can still be dark.

### Image

- Menu names: Emulators-Script, Graphic Drivers Manager (`mesa-easy-manager` 1.0.2).
- Decky Loader installs upstream Panel de Control and Colores. The in-tree SM8550-Power and SM8550-LED plugins are not installed.
- EmuDeck is not installed in the image.
- Desktop Gaming Mode on the desktop launches gamescope directly and is not in the Games menu. Return to Gaming Mode stays.
