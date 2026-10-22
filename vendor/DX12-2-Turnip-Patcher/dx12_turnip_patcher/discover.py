"""Find Proton installs the user is allowed to patch."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

from .patcher import FEATURE_LEVEL_LOG


@dataclass(frozen=True)
class ProtonInstall:
    root: Path
    name: str
    display_name: str
    excluded: str | None
    dlls: tuple[Path, ...]

    @property
    def selectable(self) -> bool:
        return self.excluded is None and bool(self.dlls)


def steam_roots() -> list[Path]:
    override = os.environ.get("DX12_TURNIP_STEAM_ROOTS", "").strip()
    if override:
        return [Path(p) for p in override.split(os.pathsep) if p]
    home = Path.home()
    candidates = [
        home / ".local/share/Steam",
        home / ".steam/steam",
        home / ".steam/root",
        home / ".var/app/com.valvesoftware.Steam/data/Steam",
    ]
    found: list[Path] = []
    seen: set[Path] = set()
    for path in candidates:
        try:
            real = path.resolve()
        except OSError:
            continue
        if real in seen or not path.is_dir():
            continue
        seen.add(real)
        found.append(path)
    return found


def iter_protons(roots: list[Path] | None = None) -> list[ProtonInstall]:
    roots = steam_roots() if roots is None else roots
    found: list[ProtonInstall] = []
    seen: set[Path] = set()
    for steam in roots:
        for folder in (steam / "compatibilitytools.d", steam / "steamapps" / "common"):
            if not folder.is_dir():
                continue
            for child in sorted(folder.iterdir(), key=lambda p: p.name.lower()):
                if not child.is_dir():
                    continue
                try:
                    real = child.resolve()
                except OSError:
                    continue
                if real in seen:
                    continue
                if not ((child / "proton").is_file() or (child / "compatibilitytool.vdf").is_file()):
                    continue
                seen.add(real)
                dlls = tuple(_vkd3d_dlls(child))
                found.append(
                    ProtonInstall(
                        root=child,
                        name=child.name,
                        display_name=_display_name(child),
                        excluded=_exclude_reason(child, dlls),
                        dlls=dlls,
                    )
                )
    return found


def selectable_protons(roots: list[Path] | None = None) -> list[ProtonInstall]:
    return [p for p in iter_protons(roots) if p.selectable]


def _display_name(root: Path) -> str:
    vdf = root / "compatibilitytool.vdf"
    if vdf.is_file():
        try:
            text = vdf.read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
        match = re.search(r'"display_name"\s+"([^"]+)"', text)
        if match:
            return match.group(1)
    return root.name


def location_exclusion(root: Path) -> str | None:
    """Steam's own builds live in steamapps/common. compatibilitytools.d is all selectable."""
    parent = root.parent
    if parent.name == "common" and parent.parent.name == "steamapps":
        return "steamapps/common"
    return None


def _exclude_reason(root: Path, dlls: tuple[Path, ...]) -> str | None:
    placed = location_exclusion(root)
    if placed:
        return placed
    if not dlls:
        return "no vkd3d-proton DLL"
    return None


def _machine(path: Path) -> int | None:
    try:
        with path.open("rb") as fh:
            head = fh.read(0x40)
            if len(head) < 0x40 or head[:2] != b"MZ":
                return None
            e = int.from_bytes(head[0x3C:0x40], "little")
            fh.seek(e + 4)
            raw = fh.read(2)
    except OSError:
        return None
    if len(raw) < 2:
        return None
    return int.from_bytes(raw, "little")


def _vkd3d_dlls(root: Path) -> list[Path]:
    dlls: list[Path] = []
    seen: set[Path] = set()
    bases = [root / "files" / "lib", root / "dist" / "lib", root / "lib"]
    for base in bases:
        if not base.is_dir():
            continue
        for path in base.rglob("d3d12core.dll"):
            if any(part in {"default_pfx", "default_pfx_arm64", "pfx", "compatdata"} for part in path.parts):
                continue
            if not any(part in {"aarch64-windows", "x86_64-windows", "vkd3d-proton"} for part in path.parts):
                continue
            try:
                real = path.resolve()
            except OSError:
                continue
            if real in seen or not path.is_file():
                continue
            machine = _machine(path)
            if machine not in (0xAA64, 0x8664):
                continue
            try:
                with path.open("rb") as fh:
                    # The log string sits in .rdata, well inside the first 8 MiB.
                    blob = fh.read(8 * 1024 * 1024)
            except OSError:
                continue
            if FEATURE_LEVEL_LOG not in blob and FEATURE_LEVEL_LOG not in path.read_bytes():
                continue
            seen.add(real)
            dlls.append(path)
    dlls.sort(key=lambda p: (0 if _machine(p) == 0xAA64 else 1, str(p)))
    return dlls
