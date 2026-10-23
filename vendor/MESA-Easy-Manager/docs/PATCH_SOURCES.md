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
  silent/          always applied, not shown in the dialog
  SM8550/
    001-fix-freedreno-vulkan.patch
    0001-freedreno-ir3-vulkan-disable-bindless-ubo-const-lowering.patch
  SM8750/
    0001-add-a830-chip-id.patch
```

The optional set is `BUNDLED_PATCH_FILES` in `mesa_easy_manager/rocknix.py`.
The always-on set is `SILENT_PATCH_FILES`. Mesh shaders, wave 32, and the
other Mesa-main fixes are `MESA27_SILENT_PATCH_FILES`: devel and every
stable release from 27.0.0 onward. The 26.2 series does not receive them.

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

Adds the KGSL chip id `0x44050000` for Adreno 830, in front of the
existing `0x44050001` entry. Mesa 26.2.5 and Mesa main both already list
`0x44050001`. This machine reports `0x44050000`. The extra id does not
match Adreno 740. This patch stays in the optional set for stable
releases and for devel.

---

## Silent

These are not listed in the compile dialog. They apply after the source tree
is extracted and before the optional bundled set.

`0001` applies to every compile, stable or devel.

`0002`–`0007` track Mesa main. They apply to `devel` and to stable
releases from 27.0.0 onward, including a 27.0.1 point release. The 26.2
series (26.2.5, 26.2.8) does not receive them.

| File | What it does | Where it takes effect |
| --- | --- | --- |
| `silent/0001-turnip-skip-missing-vertex-shader-draw-state.patch` | Do not fault a graphics pipeline that has no vertex shader | All Adreno |
| `silent/0002-turnip-null-descriptor-set-layout.patch` | Tolerate a null descriptor set layout | All Adreno |
| `silent/0003-tu-emulate-mesh-shader-with-compute.patch` | `VK_EXT_mesh_shader` via compute into a ring, then a generated vertex shader. Mesh passes use sysmem | Adreno 8xx only (`chip >= 8`) |
| `silent/0004-tu-ir3-half-wave-subgroup-32.patch` | Minimum subgroup size 32; each half of a 64-wide wave is one subgroup | Adreno 8xx only |
| `silent/0005-ir3-sanitize-cube-map-directions-a8xx.patch` | Replace cube-map directions that hang A8xx (NaN, zero vector) | `cube_coord_hang_quirk` on `a8xx_base` |
| `silent/0006-tu-invalidate-bindless-descriptors-a8xx.patch` | Invalidate bindless descriptors through the A8xx registers | `CHIP >= A8XX` |
| `silent/0007-tu-kgsl-a8xx-command-streams.patch` | Fetch A8xx command streams through a virtual BO alias | KGSL only. The MSM build does not use this path |

Attribution: MaxsTechReview, series `0001`–`0005` in
[WinNative-Emu/Drivers](https://github.com/WinNative-Emu/Drivers), as shipped
under `patches/a8xx-winnative/` in
[The412Banner/Banners-Turnip](https://github.com/The412Banner/Banners-Turnip).
Written for FINAL FANTASY VII REBIRTH on Adreno 830. The copies here gate mesh
shaders and wave 32 to A8xx so the same library can still be installed on
Adreno 740.

---

## Not shipped

Local Turnip Wayland WSI / RPCS3 experiment patches (`0004`–`0007`) were removed.
They did not fix the issues and are not part of Rocknix/Batocera.
