# MaSi-OS-UFS-install

Install **MaSi-OS** (or compatible Armbian SM8550 images) on **internal UFS** alongside **Android**, using the **ROCKNIX ABL** dual-boot partition layout.

> **⚠️ RISK WARNING**
>
> This **repartitions internal storage** and **wipes Android userdata**. You can **lose all data** on internal UFS. **Android, Linux, or both** may fail to boot. **Use at your own risk.** See [DISCLAIMER.md](DISCLAIMER.md).

## Supported devices

- Qualcomm **SM8550** with **ROCKNIX ABL** installed  
- Tested targets: **AYN Odin 2**, Odin 2 Mini/Portal, **Thor**, **Retroid Pocket 6**, similar SM8550 handhelds  

**Not** for ARMADA three-partition layouts — use ARMADA tools instead.

## What you need before starting

| Requirement | Notes |
|-------------|--------|
| ROCKNIX ABL | Installed on the device |
| MaSi-OS on **microSD** | Run the installer from SD, not from UFS |
| `/boot/KERNEL` | Dual-boot image (`root=UUID=` + `masi.ufsroot=PARTLABEL=STORAGE`) from your kernel build |
| Root shell | `sudo` on the running Linux system |

This repository contains **install scripts only**. It does **not** build kernels. Build and install your kernel separately (MaSi-OS `make.sh` + `update.sh` or equivalent).

## Partition layout (after install)

```
userdata   →  Android (size you choose; all data erased)
ROCKNIX    →  2 GiB FAT32 — KERNEL + KERNEL.md5
STORAGE    →  ext4 — full Linux root filesystem
```

Same model as ROCKNIX `installtointernal` (two Linux partitions).

## Quick start

```bash
git clone https://github.com/MaSieS4Fun/MaSi-OS-UFS-install.git
cd MaSi-OS-UFS-install
chmod +x *.sh

# Read the disclaimer first
less DISCLAIMER.md

# Diagnose current UFS layout (optional)
sudo ./ufs-diagnose.sh

# Full install (interactive sizing)
sudo ./install-masios-to-internal.sh

# Or specify Android size in GB
sudo ./install-masios-to-internal.sh --android-gb 64
```

### After a failed install (partitions already exist)

```bash
sudo ./install-masios-to-internal.sh --deploy-only
```

### Repair KERNEL / fstab only

```bash
sudo ./ufs-fix-internal-boot.sh
```

## Scripts

| Script | Purpose |
|--------|---------|
| `install-masios-to-internal.sh` | Repartition UFS + install UFS-safe KERNEL + rootfs |
| `ufs-diagnose.sh` | Show UFS layout, SD vs ROCKNIX KERNEL cmdline |
| `ufs-fix-internal-boot.sh` | Rewrite ROCKNIX KERNEL to `root=PARTLABEL=STORAGE`; fix fstab |
| `ufs-bootimg.sh` | Shared helpers (pack UFS KERNEL from SD KERNEL) |

## How boot works (v1.8+)

| Location | KERNEL cmdline |
|----------|----------------|
| microSD `/boot/KERNEL` | `root=UUID=<SD>` (+ optional `masi.ufsroot=...`) |
| UFS `ROCKNIX/KERNEL` | **`root=PARTLABEL=STORAGE` only** (packed at install time) |

Internal Linux boot does **not** depend on the microSD being present or on initramfs dual-root races.

## Options (`install-masios-to-internal.sh`)

```
--android-gb N    Android userdata size (GB)
--dry-run         Simulate without writing
--resume          Use existing ROCKNIX/STORAGE (no repartition)
--deploy-only     Same as --resume
--force           Skip final confirmation (still shows risk banner)
-h, --help        Help
```

## Typical flow after install

1. **Remove microSD**, reboot → ABL Linux mode → MaSi-OS from UFS.  
2. Boot **Android recovery** → **Factory data reset** (userdata was wiped).  
3. Keep a working microSD as recovery until UFS Linux is verified.

### Already installed but black screen on UFS?

Boot from microSD and run:

```bash
sudo apt install abootimg   # if needed
sudo ./ufs-fix-internal-boot.sh
```

Then remove the SD and test UFS boot again.

## Recovery if something goes wrong

| Problem | Action |
|---------|--------|
| Linux black screen | `sudo ./ufs-diagnose.sh` then `sudo ./ufs-fix-internal-boot.sh` |
| Partial install | `sudo ./install-masios-to-internal.sh --deploy-only` |
| Remove internal Linux | ROCKNIX ABL → **Uninstall ROCKNIX** |
| Android broken | Recovery → factory reset; worst case reflash firmware |

## Legal

- [DISCLAIMER.md](DISCLAIMER.md) — **read before use**
- [LICENSE](LICENSE) — GPL-2.0-or-later

**You assume all risk.** Authors provide no warranty and no guarantee of support.

---

## Aviso en español

Esta herramienta **borra los datos de la partición Android `userdata`** en la memoria interna (UFS) y **reparticiona el disco**. Puedes **perder todos los datos** guardados en Android y en UFS. **Android, Linux o ambos sistemas pueden dejar de arrancar**.

**Haz copias de seguridad** antes de continuar. **Úsalo bajo tu cuenta y riesgo.** Lee [DISCLAIMER.md](DISCLAIMER.md).

```bash
sudo ./ufs-diagnose.sh              # diagnóstico
sudo ./install-masios-to-internal.sh   # instalación
```

Requisitos: ABL ROCKNIX instalado, MaSi-OS arrancando desde **microSD**, `/boot/KERNEL` dual-boot correcto.
