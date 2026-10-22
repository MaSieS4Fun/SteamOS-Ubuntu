"""CLI: gui, list, patch, restore, selftest."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import __app_name__, __version__
from .discover import iter_protons, location_exclusion, selectable_protons
from .patcher import FEATURE_LEVEL_LOG, MESH_FUNCS, X86_RET, patch_dll
from .pe import Pe
from .service import apply_patch, restore_patch


def _cmd_list(_args: argparse.Namespace) -> int:
    rows = iter_protons()
    if not rows:
        print("No Proton found in compatibilitytools.d or steamapps/common.")
        return 0
    for proton in rows:
        state = proton.excluded or "selectable"
        mark = "patched" if proton.selectable and _patched_label(proton.root) else state
        print(f"{proton.display_name}\t{mark}\t{proton.root}")
    return 0


def _patched_label(root: Path) -> bool:
    from .service import is_patched

    return is_patched(root)


def _cmd_patch(args: argparse.Namespace) -> int:
    proton = _find(args.name)
    if proton is None:
        print(f"Not in the selectable list: {args.name}", file=sys.stderr)
        return 1
    outcome = apply_patch(proton, update_prefixes=not args.no_prefixes)
    print(outcome.summary)
    for item in outcome.files:
        print(f"  {item.status}: {item.detail}")
    return 0 if outcome.ok else 1


def _cmd_restore(args: argparse.Namespace) -> int:
    proton = _find(args.name, include_hidden=True)
    if proton is None:
        print(f"Proton not found: {args.name}", file=sys.stderr)
        return 1
    outcome = restore_patch(proton)
    print(outcome.summary)
    return 0 if outcome.ok else 1


def _find(name: str, include_hidden: bool = False):
    rows = iter_protons() if include_hidden else selectable_protons()
    folded = name.casefold()
    for proton in rows:
        if folded in {proton.name.casefold(), proton.display_name.casefold()}:
            return proton
    return None


def _cmd_selftest(args: argparse.Namespace) -> int:
    failures: list[str] = []

    def check(cond: bool, message: str) -> None:
        if not cond:
            failures.append(message)
            print("FAIL", message)
        else:
            print("ok  ", message)

    common = Path("/home/steam/.local/share/Steam/steamapps/common/Proton 11.0 (ARM64)")
    tools = Path.home() / ".local/share/Steam/compatibilitytools.d"
    check(location_exclusion(common) == "steamapps/common", "skips steamapps/common")
    check(location_exclusion(tools / "GE-Proton11-11-aarch64") is None, "includes GE-Proton 11")
    check(location_exclusion(tools / "GE-Proton10-25-aarch64") is None, "includes GE-Proton 10")
    check(location_exclusion(tools / "proton-cachyos-arm") is None, "includes CachyOS")
    check(location_exclusion(tools / "Proton Experimental ARM") is None, "includes every compatibility tool")

    dlls = []
    if args.dll:
        dlls.append(Path(args.dll))
    else:
        default = Path(
            "/home/steam/.local/share/Steam/compatibilitytools.d/"
            "GE-Proton11-11-aarch64/files/lib/wine/vkd3d-proton"
        )
        for arch in ("aarch64-windows", "x86_64-windows"):
            candidate = default / arch / "d3d12core.dll"
            if candidate.is_file():
                dlls.append(candidate)
    if not dlls:
        print("no vkd3d DLL available for the patch check (that part is skipped)")
    for dll in dlls:
        _exercise_dll(dll, check)

    if failures:
        print(f"{len(failures)} failure(s)")
        return 1
    print("selftest ok")
    return 0


def _exercise_dll(dll: Path, check) -> None:
    backup = Path(str(dll) + ".dx12turnip-bak")
    original = backup.read_bytes() if backup.is_file() else dll.read_bytes()
    label = dll.parent.name
    check(FEATURE_LEVEL_LOG in original, f"{label}: is vkd3d-proton")
    patched, result = patch_dll(original)
    check(result.changed, f"{label}: the patch changes the DLL ({result.tier}, {result.stub})")
    check(patched != original, f"{label}: the bytes change")
    check(FEATURE_LEVEL_LOG in patched, f"{label}: the feature-level string remains")
    again, again_result = patch_dll(patched)
    check(again_result.already and again == patched, f"{label}: the second pass does not rewrite")
    pe = Pe(patched)
    if pe.machine == 0xAA64:
        check(pe.section(".turnip") is not None, "ARM64: .turnip section is present")
        check(b"\x0a\x00\x00\x00\x64\x00\x00\x00\x02\x00\x00\x00\x03\x00\x00\x00" in patched,
              "ARM64: MeshShaderTier stays 10")
        sec = pe.section(".turnip")
        body = patched[sec.rawptr : sec.rawptr + sec.vsize]
        check(body.endswith(X86_RET) or X86_RET in body[: sec.vsize], "ARM64: the stored mesh pointer is an x86 ret")
        check(body[:4] == b"\x40\x00\x00\xb5", "ARM64: the resolver island still starts with cbnz")
        broken = bytearray(patched)
        shared = body.rfind(X86_RET)
        broken[sec.rawptr + shared : sec.rawptr + shared + 4] = b"\xc0\x03\x5f\xd6"
        fixed, fixed_result = patch_dll(bytes(broken))
        check(fixed_result.changed and fixed[sec.rawptr + shared : sec.rawptr + shared + 4] == X86_RET,
              "ARM64: an older ARM64 ret stub is rewritten to x86")
        for name in MESH_FUNCS:
            rva = pe.find_cstring(name)
            check(rva is not None, f"ARM64: string remains {name.decode()}")
    if pe.machine == 0x8664:
        check(b"\x0a\x00\x00\x00\x64\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" in patched,
              "x86_64: vector {10, 100} stays")
        check(b"\x0a\x00\x00\x80\x64\x00\x00\x80" in patched, "x86_64: the biased mesh floor stays 10")


def _cmd_gui(_args: argparse.Namespace) -> int:
    from .ui.window import run

    return run()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="dx12-turnip-patcher", description=__app_name__)
    parser.add_argument("--version", action="version", version=__version__)
    sub = parser.add_subparsers(dest="cmd")
    sub.add_parser("gui")
    sub.add_parser("list")
    patch = sub.add_parser("patch")
    patch.add_argument("name")
    patch.add_argument("--no-prefixes", action="store_true")
    restore = sub.add_parser("restore")
    restore.add_argument("name")
    test = sub.add_parser("selftest")
    test.add_argument("--dll", default="")
    args = parser.parse_args(argv)
    cmd = args.cmd or "gui"
    if cmd == "gui":
        return _cmd_gui(args)
    if cmd == "list":
        return _cmd_list(args)
    if cmd == "patch":
        return _cmd_patch(args)
    if cmd == "restore":
        return _cmd_restore(args)
    if cmd == "selftest":
        return _cmd_selftest(args)
    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())


