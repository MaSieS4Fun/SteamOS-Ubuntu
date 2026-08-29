# Kernel 7.2.2 migration (semi-final phase)

Target: **linux-7.2.2** from [kernel.org](https://kernel.org/) (stable latest as of 2026-08-28).

Production today: **7.0.14-edge-sm8550**. Do not flip `defaults.conf` until 7.2.2 builds and boots on hardware.

## How the build already works

| Layer | Source |
|-------|--------|
| **Upstream tree** | `cdn.kernel.org` / `releases.json` — `lib/kernel-org.sh` |
| **Board patches** | Armbian `sm8550-7.2` (bootstrap: copy of 7.0 manifest until Armbian publishes 7.2) |
| **MaSi overlays** | `patches/masi/*.patch` (1033 aw88166 quiet, suspend, Thor, AYANEO, …) |
| **Config** | `config/golden.config` |
| **Output** | One multi-device `boot/KERNEL` (ABL DTB selector) + modules + firmware |

## Start a 7.2.2 build

```bash
cd vendor/kernel
cp config/local.conf.example config/local.conf   # includes PREFLIGHT_SKIP_ROOT_UUID=1 for PC builds
./make.sh
```

On a **PC without `/boot/KERNEL`**, use `PREFLIGHT_SKIP_ROOT_UUID=1` in `config/local.conf` (or `ROOT_UUID=…` if you have one). The microSD root UUID is embedded later by `make-disk-image.sh` or `sudo ./update.sh` on the handheld.

First run downloads `linux-7.2.2.tar.xz` and applies `sm8550-7.2` + MaSi patches. Expect failures — fix iteratively.

## Expected work (in order)

1. **Armbian sm8550-7.2** — refresh manifest when published; until then bootstrap from 7.0 and fix rejections patch-by-patch.
2. **MaSi patches** — rebase hunks for 7.2 API (DRM, input, rsinput, suspend stack, aw88166 1033, …).
3. **golden.config** — merge new/removed Kconfig symbols (`make olddefconfig` in tree after patches).
4. **Compile errors** — driver API drift (msm drm, snd-soc, mmc, …).
5. **Boot test** — one device per family (Odin2, Thor, RP6, AYANEO Pocket), then full DTB chain.
6. **Flip default** — `KERNEL_VER=7.2.2` in `defaults.conf` when stable.

## What stays the same

- Unified KERNEL + ABL DTB chain (all listed handhelds).
- `vendor/kernel/update.sh` per SD (UUID repack only).
- Mesa vendor build separate from kernel.
- Patch 1033 (aw88166 panel spam) ships with 7.2 MaSi stack.

## Final phase (later — not now)

Goal: `sudo apt update && sudo apt upgrade` from a GitHub-hosted apt repo for:

- Kernel (`steamos-kernel-sm8550` metapackage → new `boot/KERNEL` + modules)
- MESA Easy Manager
- Easy UFS installer
- ARM non-steam games
- Gyro-fix
- Proton ARM Easy Manager

Sketch: GitHub Releases or Pages + `deb`/`apt` repository (e.g. `reprepro` / `aptly`), signing key, `sources.list.d/steamos-ubuntu.list`, versioned packages per app.

---

**Status:** bootstrap manifest `sm8550-7.2.txt` added; production pin remains 7.0.14 until 7.2.2 green.
