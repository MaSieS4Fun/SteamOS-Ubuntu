"""Apply and undo the vkd3d patch on one Proton tree and its prefixes."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
from dataclasses import dataclass, field
from pathlib import Path

from .discover import ProtonInstall, steam_roots
from .patcher import BACKUP_SUFFIX, PatchError, is_vkd3d_dll, machine_name, patch_dll
from .pe import Pe, PeError

STAMP_NAME = ".dx12-turnip-patch.json"


@dataclass
class FileOutcome:
    path: Path
    status: str
    detail: str


@dataclass
class PatchOutcome:
    ok: bool
    summary: str
    files: list[FileOutcome] = field(default_factory=list)


def stamp_path(proton: Path) -> Path:
    return proton / STAMP_NAME


def is_patched(proton: Path) -> bool:
    stamp = stamp_path(proton)
    if not stamp.is_file():
        return False
    try:
        payload = json.loads(stamp.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    files = payload.get("files") or []
    if not files:
        return False
    for rel in files:
        dll = proton / rel
        backup = Path(str(dll) + BACKUP_SUFFIX)
        if not dll.is_file() or not backup.is_file():
            return False
    return True


def apply_patch(proton: ProtonInstall, *, update_prefixes: bool = True) -> PatchOutcome:
    if proton.excluded:
        return PatchOutcome(False, f"{proton.display_name} is not patched ({proton.excluded}).")
    if not proton.dlls:
        return PatchOutcome(False, f"{proton.display_name} has no ARM64 vkd3d d3d12core.dll.")

    outcomes: list[FileOutcome] = []
    written: list[tuple[Path, Path]] = []
    try:
        for dll in proton.dlls:
            outcome, backup = _patch_file(dll)
            outcomes.append(outcome)
            if backup is not None:
                written.append((dll, backup))
    except OSError as exc:
        _rollback(written)
        return PatchOutcome(False, f"Could not write the patch: {exc}", outcomes)

    if not any(item.status == "patched" for item in outcomes):
        if any(item.status == "already" for item in outcomes) and not any(item.status == "error" for item in outcomes):
            _write_stamp(proton.root, outcomes)
            prefix_note = _update_prefixes(proton, outcomes) if update_prefixes else ""
            summary = f"{proton.display_name} was already patched."
            if prefix_note:
                summary += " " + prefix_note
            return PatchOutcome(True, summary, outcomes)
        _rollback(written)
        detail = "; ".join(item.detail for item in outcomes if item.status == "error") or "vkd3d-proton was not recognized"
        return PatchOutcome(False, f"Patch was not applied to {proton.display_name}: {detail}", outcomes)

    has_arm = any(_is_arm64(dll) for dll in proton.dlls)
    arm_done = any(_is_arm64(item.path) and item.status in {"patched", "already"} for item in outcomes)
    if has_arm and not arm_done:
        _rollback(written)
        return PatchOutcome(
            False,
            f"{proton.display_name} has an ARM64 DLL, but that copy was not patched.",
            outcomes,
        )

    _write_stamp(proton.root, outcomes)
    prefix_note = _update_prefixes(proton, outcomes) if update_prefixes else ""
    summary = f"Patch applied to {proton.display_name}."
    if prefix_note:
        summary += " " + prefix_note
    summary += " Assign this Proton to the game in Steam. Keep VKD3D_FEATURE_LEVEL=12_2."
    return PatchOutcome(True, summary, outcomes)


def restore_patch(proton: ProtonInstall) -> PatchOutcome:
    outcomes: list[FileOutcome] = []
    restored = 0
    patched_hashes: dict[str, Path] = {}
    for dll in _known_dlls(proton):
        backup = Path(str(dll) + BACKUP_SUFFIX)
        if dll.is_file() and backup.is_file():
            try:
                patched_hashes[_sha(dll)] = backup
            except OSError:
                pass
    for dll in _known_dlls(proton):
        backup = Path(str(dll) + BACKUP_SUFFIX)
        if not backup.is_file():
            if dll.is_file():
                outcomes.append(FileOutcome(dll, "missing", "no original copy"))
            continue
        try:
            _replace(dll, backup.read_bytes())
        except OSError as exc:
            outcomes.append(FileOutcome(dll, "error", str(exc)))
            continue
        restored += 1
        outcomes.append(FileOutcome(dll, "restored", "restored"))
    prefix_note = _restore_prefixes(patched_hashes)
    try:
        stamp_path(proton.root).unlink()
    except FileNotFoundError:
        pass
    except OSError as exc:
        return PatchOutcome(False, f"The DLL was restored, but the stamp could not be removed: {exc}", outcomes)
    if restored == 0 and not prefix_note:
        return PatchOutcome(False, f"{proton.display_name} has no saved original copy.", outcomes)
    summary = f"Restored {proton.display_name}."
    if prefix_note:
        summary += " " + prefix_note
    return PatchOutcome(True, summary, outcomes)


def _patch_file(dll: Path) -> tuple[FileOutcome, Path | None]:
    original = dll.read_bytes()
    if not is_vkd3d_dll(original):
        return FileOutcome(dll, "skip", "not vkd3d-proton"), None
    try:
        machine = machine_name(Pe(original).machine)
    except PeError:
        machine = "?"
    try:
        patched, result = patch_dll(original)
    except PatchError as exc:
        return FileOutcome(dll, "error", f"{machine}: {exc}"), None
    rel = _pretty(dll)
    notes = "; ".join(result.notes)
    if result.changed and patched != original:
        backup = Path(str(dll) + BACKUP_SUFFIX)
        if not backup.exists():
            backup.write_bytes(original)
        _replace(dll, patched)
        return FileOutcome(dll, "patched", f"{machine} {rel}: {notes}"), backup
    if result.already:
        return FileOutcome(dll, "already", f"{machine}: {notes}"), None
    return FileOutcome(dll, "skip", f"{machine}: {notes}"), None


def _known_dlls(proton: ProtonInstall) -> list[Path]:
    paths = list(proton.dlls)
    stamp = stamp_path(proton.root)
    if stamp.is_file():
        try:
            payload = json.loads(stamp.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            payload = {}
        for rel in payload.get("files") or []:
            candidate = proton.root / rel
            if candidate not in paths:
                paths.append(candidate)
    return paths


def _write_stamp(root: Path, outcomes: list[FileOutcome]) -> None:
    files = []
    for item in outcomes:
        if item.status not in {"patched", "already"}:
            continue
        try:
            rel = str(item.path.resolve().relative_to(root.resolve()))
        except ValueError:
            rel = str(item.path)
        files.append(rel)
    payload = {"version": 1, "files": files}
    stamp_path(root).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def _rollback(written: list[tuple[Path, Path]]) -> None:
    for dll, backup in written:
        if backup.is_file():
            try:
                _replace(dll, backup.read_bytes())
            except OSError:
                pass


def _replace(path: Path, data: bytes) -> None:
    tmp = path.with_name(path.name + ".dx12turnip-tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def _pretty(path: Path) -> str:
    parts = path.parts
    if "vkd3d-proton" in parts:
        idx = parts.index("vkd3d-proton")
        return str(Path(*parts[idx:]))
    return path.name


def _is_arm64(path: Path) -> bool:
    try:
        return Pe(path.read_bytes()).machine == 0xAA64
    except (OSError, PeError):
        return False


def _update_prefixes(proton: ProtonInstall, outcomes: list[FileOutcome]) -> str:
    patched = { _sha(item.path): item.path for item in outcomes if item.status in {"patched", "already"} and item.path.is_file() }
    originals = {}
    for item in outcomes:
        backup = Path(str(item.path) + BACKUP_SUFFIX)
        if backup.is_file():
            originals[_sha(backup)] = item.path
    if not patched:
        return ""
    updated = 0
    skipped = 0
    for prefix in _matching_prefixes(proton):
        for dll in _prefix_dlls(prefix):
            try:
                digest = _sha(dll)
            except OSError:
                continue
            if digest in patched:
                continue
            source = originals.get(digest)
            if source is None:
                skipped += 1
                continue
            try:
                target = patched[_sha(source)]
                _replace(dll, target.read_bytes())
            except (OSError, KeyError):
                skipped += 1
                continue
            updated += 1
    if updated == 0 and skipped == 0:
        return "New prefixes will copy it the next time the game starts."
    text = f"Prefixes updated: {updated}."
    if skipped:
        text += f" Left unchanged: {skipped} (d3d12core does not match this Proton)."
    return text


def _restore_prefixes(patched_hashes: dict[str, Path]) -> str:
    """Replace prefix copies whose bytes are still the patched DLL."""
    if not patched_hashes:
        return ""
    restored = 0
    for steam in steam_roots():
        compat = steam / "steamapps" / "compatdata"
        if not compat.is_dir():
            continue
        for app in compat.iterdir():
            if not app.is_dir():
                continue
            for dll in _prefix_dlls(app):
                try:
                    backup = patched_hashes.get(_sha(dll))
                except OSError:
                    continue
                if backup is None:
                    continue
                try:
                    _replace(dll, backup.read_bytes())
                except OSError:
                    continue
                restored += 1
    if restored == 0:
        return ""
    return f"Prefixes restored: {restored}."


def _matching_prefixes(proton: ProtonInstall) -> list[Path]:
    name = proton.root.name
    root_s = str(proton.root)
    found: list[Path] = []
    for steam in steam_roots():
        compat = steam / "steamapps" / "compatdata"
        if not compat.is_dir():
            continue
        for app in compat.iterdir():
            if not app.is_dir():
                continue
            cfg = app / "config_info"
            ver = app / "version"
            matched = False
            try:
                if cfg.is_file() and root_s in cfg.read_text(encoding="utf-8", errors="replace"):
                    matched = True
                elif ver.is_file():
                    text = ver.read_text(encoding="utf-8", errors="replace").strip()
                    matched = bool(text) and (text == name or name.startswith(text + "-") or name.startswith(text + "_"))
            except OSError:
                continue
            if matched:
                found.append(app)
    return found


def _prefix_dlls(prefix: Path) -> list[Path]:
    base = prefix / "pfx" / "drive_c" / "windows"
    paths = [base / "system32" / "d3d12core.dll", base / "syswow64" / "d3d12core.dll"]
    return [path for path in paths if path.is_file()]


def _sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
