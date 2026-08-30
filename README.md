# <img width="1585" height="434" alt="logo" src="https://github.com/user-attachments/assets/38126449-3ab3-4e75-9cdf-00367ab11670" />


SteamOS-like Linux Gaming OS for ARM64 handhelds (SM8550 / Adreno 740), inspired by [Universal Blue](https://github.com/ublue-os) / Bazzite, built on **Ubuntu Resolute**.

---
### Join the community on [Discord](https://discord.gg/Mqegm7PvV9).
### You can Check a configuration and showcase [video](https://www.youtube.com/watch?v=2_gH20kpyiE).
---
> [!WARNING]
> - AI has been used in this project.
> - Before releasing a functional image to the public, it has been thoroughly tested.
> - All functionality tests have been carried out exclusively on the AYN ODIN2.
> - The devices listed below should be compatible with the system, but some features may not work or may not work properly.
> - The system starts with a black screen and no logos. The first boot may take up to 2–3 minutes! Please be patient.

SteamOS-Ubuntu is a multi-device system with EFI boot, designed to be compatible with the ROCKNIX ABL. If you already have the ABL configured, you simply need to flash the image onto the SD card and it should work.

# Supported devices

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

---
### System User

| user     | `steam` |
| password | `steam` |

# Decky Loader

- For Decky Loader to work, you need to install an x86_64-to-ARM instruction translation layer on the system.
- In the "ARM-Manager" application menu, you will find installation scripts for BOX64 or FEXEmu.
- The SM8550-LED and SM8550-Power plugins are based on [Hooandee's plugins.](https://github.com/Hooandee)

# Installation:
- First, install [ROCKNIX ABL](https://github.com/ROCKNIX/abl).
- You can use the ABL installation [scripts from Android]([rocknix_abl_Android_Scripts.zip](https://github.com/user-attachments/files/31609601/rocknix_abl_Android_Scripts.zip)
). You must place the `abl_signed-SM8550.elf` ABL file inside the folder.
- Once the ABL is installed, select your device. This will configure the device to boot Linux distributions.
- Use [balenaEtcher](https://etcher.balena.io/) or [Rufus](https://rufus.ie/es/) to flash the [SteamOS-Ubuntu](https://github.com/MaSieS4Fun/SteamOS-Ubuntu/releases) image onto the SD card.
- Once the SD card has been flashed, insert it into your device's SD card reader.

## Support the project

If this helps you and you want to support development, testing, and hosting:

**[Donate via PayPal](https://paypal.me/masies4fun)**

Thank you to everyone who uses, tests, reports issues, and contributes.

---

## License

Project glue: MIT. Vendor trees keep their own licenses. See [`CREDITS.md`](CREDITS.md) for full upstream attribution.
