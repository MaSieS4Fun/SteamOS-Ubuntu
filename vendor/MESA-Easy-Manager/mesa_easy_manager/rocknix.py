"""Load bundled Mesa patches (no network at compile time).

One patch set is used for SM8550 (Odin 2 / Adreno 740) and SM8750
(Odin 3 / Adreno 830). The sync and UBO fixes are chip-agnostic. The
A830 chip-id patch only adds device-table entries and does not change
Adreno 740 behavior. Mesh shaders and wave 32 are a separate silent
set, applied on Mesa devel and on stable releases from 27.0.0 onward.

All patches ship under mesa_easy_manager/patches/. Upstream attribution
URLs are documentation-only; the original Batocera repo was removed and
preserved at https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path

PATCHES_ROOT = Path(__file__).resolve().parent / "patches"

# Attribution / docs only (not fetched at runtime).
BATOCERA_FORK = "https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds"
ROCKNIX_TREE = (
    "https://github.com/ROCKNIX/distribution/tree/next/"
    "projects/ROCKNIX/packages/graphics/mesa/patches"
)
BATOCERA_PATCHES_ROOT = "board/batocera/patches/mesa3d"

# Apply order. Paths stay under their original SoC directories.
BUNDLED_PATCH_FILES: tuple[str, ...] = (
    "SM8550/001-fix-freedreno-vulkan.patch",
    "SM8550/0001-freedreno-ir3-vulkan-disable-bindless-ubo-const-lowering.patch",
    "SM8750/0001-add-a830-chip-id.patch",
)

# Always applied, never listed in the compile dialog.
SILENT_PATCH_FILES: tuple[str, ...] = (
    "silent/0001-turnip-skip-missing-vertex-shader-draw-state.patch",
)

# Mesa main / 27.x. Also applied to the rolling devel tip.
# The 26.2 series is an older tree and does not receive these.
# 0003–0007 are the A8xx DX12 Ultimate set (mesh shaders, wave 32, and the
# Rebirth hang fixes). Mesh and wave 32 stay off on A7xx inside the patches.
MESA27_SILENT_PATCH_FILES: tuple[str, ...] = (
    "silent/0002-turnip-null-descriptor-set-layout.patch",
    "silent/0003-tu-emulate-mesh-shader-with-compute.patch",
    "silent/0004-tu-ir3-half-wave-subgroup-32.patch",
    "silent/0005-ir3-sanitize-cube-map-directions-a8xx.patch",
    "silent/0006-tu-invalidate-bindless-descriptors-a8xx.patch",
    "silent/0007-tu-kgsl-a8xx-command-streams.patch",
)

DEVICES = (
    "Odin 2, Thor, R-Pocket 6 (SM8550 / Adreno 740) and "
    "Odin 3 (SM8750 / Adreno 830)"
)

ROCKNIX_PATCHES_URL = ROCKNIX_TREE
BATOCERA_PATCHES_URL = f"{BATOCERA_FORK}/tree/main/{BATOCERA_PATCHES_ROOT}"
PATCH_SOURCES_SUMMARY = (
    f"Local bundle: mesa_easy_manager/patches/\n"
    f"Attribution Batocera fork: {BATOCERA_FORK}\n"
    f"Attribution ROCKNIX tree:  {ROCKNIX_TREE}"
)


def patch_sources_summary() -> str:
    return (
        f"Local:    Bundled under mesa_easy_manager/patches/ "
        f"({len(BUNDLED_PATCH_FILES)} files, offline)\n"
        f"Attrib.:  Batocera fork {BATOCERA_FORK}\n"
        f"          ROCKNIX {ROCKNIX_TREE}"
    )


@dataclass(frozen=True)
class MesaPatch:
    """A bundled Mesa `.patch` file."""

    name: str
    path: str
    download_url: str
    sha: str
    size: int
    source: str  # "local"
    content_sha256: str = ""
    local_path: str = ""

    @property
    def html_url(self) -> str:
        return f"bundled:{self.path}"

    @property
    def label(self) -> str:
        return f"[local] {self.name}"


RocknixPatch = MesaPatch


class PatchFetchError(RuntimeError):
    pass


RocknixError = PatchFetchError


def _load_bundled_file(rel: str) -> MesaPatch:
    path = PATCHES_ROOT / rel
    if not path.is_file():
        raise PatchFetchError(f"Bundled patch missing: {path}")
    blob = path.read_bytes()
    digest = hashlib.sha256(blob).hexdigest()
    return MesaPatch(
        name=path.name,
        path=rel,
        download_url="",
        sha=digest[:12],
        size=len(blob),
        source="local",
        content_sha256=digest,
        local_path=str(path),
    )


def fetch_patches() -> list[MesaPatch]:
    """
    Return the bundled patch set for Odin 2 and Odin 3.

    No network access — files must exist under mesa_easy_manager/patches/.
    """
    patches = [_load_bundled_file(rel) for rel in BUNDLED_PATCH_FILES]
    # Deduplicate by content (defensive).
    unique: list[MesaPatch] = []
    seen: set[str] = set()
    for patch in patches:
        if patch.content_sha256 in seen:
            continue
        seen.add(patch.content_sha256)
        unique.append(patch)
    if not unique:
        raise PatchFetchError("No bundled patches")
    return unique


def download_patches(
    patches: list[MesaPatch],
    destination: Path,
) -> list[Path]:
    """Copy bundled patches into the build work directory (apply order)."""
    destination.mkdir(parents=True, exist_ok=True)
    saved: list[Path] = []
    for index, patch in enumerate(patches, start=1):
        target = destination / f"{index:02d}-{patch.source}-{patch.name}"
        target.write_bytes(Path(patch.local_path).read_bytes())
        saved.append(target)
    return saved


def summarize_patches(patches: list[MesaPatch]) -> str:
    if not patches:
        return "(none)"
    lines = ["  Local (bundled):"]
    for patch in patches:
        lines.append(f"    • {patch.name}")
    return "\n".join(lines)


# Stubs kept so older imports do not break; always empty / error offline.
def fetch_rocknix_patches() -> list[MesaPatch]:
    return []


def fetch_batocera_patches() -> list[MesaPatch]:
    return []


def fetch_local_wsi_patches() -> list[MesaPatch]:
    """Deprecated — local WSI/RPCS3 experiment patches were removed."""
    return []
