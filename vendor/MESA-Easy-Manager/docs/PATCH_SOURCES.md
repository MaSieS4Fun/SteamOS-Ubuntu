# Patch sources and attribution

MESA Easy Manager optionally applies Mesa patches when compiling
`libvulkan_freedreno.so`. **All patches are bundled offline** under
`mesa_easy_manager/patches/` — nothing is downloaded from GitHub at compile
time (the original Batocera tree was removed upstream).

Compile offers one choice: apply the bundled set, or build stock Mesa.
The same patched library is intended for Odin 2 and Odin 3.

| Build | Devices | Bundled patches |
| --- | --- | --- |
| **With patches** | Odin 2, Thor, R-Pocket 6, Odin 3 | Batocera sync + ROCKNIX UBO + A830 chip-id |
| **Without patches** | Any | None (stock Mesa) |

The A830 chip-id patch only adds Adreno 830 device-table entries. It does
not change Adreno 740 behavior, so one build covers both SoCs.

---

## Bundled layout

```text
mesa_easy_manager/patches/
  SM8550/
    001-fix-freedreno-vulkan.patch
    0001-freedreno-ir3-vulkan-disable-bindless-ubo-const-lowering.patch
  SM8750/
    0001-add-a830-chip-id.patch
```

Apply order is fixed in `mesa_easy_manager/rocknix.py` (`BUNDLED_PATCH_FILES`).

---

## SM8550 (Odin 2 / Thor / R-Pocket 6)

### Sync fix (originally Batocera)

**Local:** `patches/SM8550/001-fix-freedreno-vulkan.patch`

**Attribution / mirror:**  
[MaSieS4Fun/Batocera-Custom-Qualcomm-Builds](https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds)
(`board/batocera/patches/mesa3d/`) — fork of the deleted upstream tree.

Soft Vulkan submit/sync fix for Adreno 7XX (`tu_knl_drm_msm.cc`).

### UBO fix (originally ROCKNIX)

**Local:** `patches/SM8550/0001-freedreno-ir3-vulkan-disable-bindless-ubo-const-lowering.patch`

**Attribution:**  
[ROCKNIX SM8550 patches](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/graphics/mesa/patches/SM8550)

IR3 bindless UBO const-lowering fix. It is a compiler change, so the same
patch is applied for Adreno 740 and Adreno 830.

---

## A830 chip-id (Odin 3, also applied on Odin 2 builds)

**Local:** `patches/SM8750/0001-add-a830-chip-id.patch`

Adds Adreno **a830** chip id support. Extra IDs do not match Adreno 740,
so the same patched driver still runs on SM8550.

---

## Not shipped

Local Turnip Wayland WSI / RPCS3 experiment patches (`0004`–`0007`) were removed.
They did not fix the issues and are not part of Rocknix/Batocera.
