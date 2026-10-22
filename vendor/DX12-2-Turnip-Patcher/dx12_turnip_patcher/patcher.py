"""Binary patch so vkd3d-proton can run DX12 games on Turnip.

VKD3D_FEATURE_LEVEL=12_2 stays on, and MeshShaderTier stays advertised.
Rebirth refuses to start without the feature level, and it refuses to load
its shader library if the tier is hidden. Turnip still has no
vkCmdDrawMeshTasks* and its subgroup size is 64. On the ARM64 DLL a NULL mesh
pointer is stored as an x86 ret (FEX enters that pointer as x86 code), and a
shader that requires wave size 32 is accepted so it runs at wave 64.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field

from .pe import Pe, PeError, align_up, decode_add_imm, decode_adrp

FEATURE_LEVEL_LOG = b"Overriding feature level: %#x.\n"
WAVE_SIZE_LOG = b"Required WaveSize range [%u, %u], but supported range is [%u, %u].\n"
MESH_FUNCS = (
    b"vkCmdDrawMeshTasksEXT",
    b"vkCmdDrawMeshTasksIndirectEXT",
    b"vkCmdDrawMeshTasksIndirectCountEXT",
)
BACKUP_SUFFIX = ".dx12turnip-bak"
STUB_SECTION = ".turnip"
# D3D12_MESH_SHADER_TIER_1 == 10. Sampler feedback floor is 100 (tier 1.0)
# or 90 (tier 0.9) depending on the vkd3d-proton version.
MESH_TIER = 10
FEEDBACK_TIERS = (100, 90)
# FEX executes the stored Vulkan pointer as x86. An ARM64 RET is an invalid
# entry. The island that runs at vkGetDeviceProcAddr time stays ARM64.
X86_RET = b"\xc3\x90\x90\x90"
ARM64_RET = 0xD65F03C0
ARM64_NOP = 0xD503201F


class PatchError(Exception):
    pass


@dataclass
class DllPatchResult:
    changed: bool
    already: bool
    tier: str
    stub: str
    notes: list[str] = field(default_factory=list)


def machine_name(machine: int) -> str:
    return {0xAA64: "ARM64", 0x8664: "x86_64", 0x14C: "i386"}.get(machine, hex(machine))


def is_vkd3d_dll(data: bytes) -> bool:
    return data[:2] == b"MZ" and FEATURE_LEVEL_LOG in data


def patch_dll(data: bytes) -> tuple[bytes, DllPatchResult]:
    try:
        pe = Pe(data)
    except PeError as exc:
        raise PatchError(str(exc)) from exc
    if pe.find_cstring(FEATURE_LEVEL_LOG) is None:
        raise PatchError("this d3d12core.dll is not vkd3d-proton")

    notes: list[str] = []
    buf = bytearray(data)
    tier_state, tier_note = _patch_mesh_tier(Pe(buf), buf)
    notes.append(tier_note)

    wave_state = "skipped"
    stub_state = "skipped"
    if pe.machine == 0xAA64:
        wave_state, wave_note = _patch_wave_arm64(Pe(buf), buf)
        notes.append(wave_note)
        stub_state, stub_note, buf = _patch_arm64_null_stub(Pe(bytes(buf)), buf)
        notes.append(stub_note)
        if wave_state == "missing":
            raise PatchError(wave_note)
        if stub_state not in {"patched", "already"}:
            raise PatchError(stub_note)
    elif pe.machine == 0x8664:
        wave_state, wave_note = _patch_wave_x64(Pe(buf), buf)
        notes.append(wave_note)
    else:
        raise PatchError(f"PE {machine_name(pe.machine)} is not patched")

    changed = any(state == "patched" for state in (tier_state, wave_state, stub_state))
    already = (
        not changed
        and tier_state in {"already", "missing"}
        and wave_state == "already"
        and (pe.machine != 0xAA64 or stub_state == "already")
    )
    return bytes(buf), DllPatchResult(
        changed=changed,
        already=already,
        tier=tier_state,
        stub=stub_state if pe.machine == 0xAA64 else wave_state,
        notes=notes,
    )


def _patch_mesh_tier(pe: Pe, buf: bytearray) -> tuple[str, str]:
    """Keep MeshShaderTier advertised. An older patch cleared it; put 10 back."""
    spans: list[tuple[int, int]] = []
    seen: set[int] = set()
    for log_rva in pe.find_all_cstrings(FEATURE_LEVEL_LOG):
        try:
            xrefs = _code_xrefs(pe, log_rva)
        except PeError:
            continue
        for xref in xrefs:
            try:
                start, end = pe.function_bounds(xref)
            except PeError:
                continue
            if start in seen:
                continue
            seen.add(start)
            spans.append((start, end))
    if not spans:
        return "missing", "no code reads the feature-level log string"

    applied = 0
    already = 0
    notes: list[str] = []
    for start, end in spans:
        if pe.machine == 0xAA64:
            state, note = _patch_tier_arm64(pe, buf, start, end)
        elif pe.machine == 0x8664:
            state, note = _patch_tier_x64(pe, buf, start, end)
        else:
            return "missing", f"PE {machine_name(pe.machine)} has no MeshShaderTier pattern"
        notes.append(note)
        if state == "patched":
            applied += 1
        elif state == "already":
            already += 1
    if applied:
        return "patched", f"MeshShaderTier is advertised again ({applied} copy(s))"
    if already:
        return "already", "MeshShaderTier stays advertised"
    return "missing", notes[0] if notes else "MeshShaderTier constant was not found"


def _patch_tier_arm64(pe: Pe, buf: bytearray, start: int, end: int) -> tuple[str, str]:
    loads = _arm64_d_loads(pe, start, end)
    forced = [addr for addr in loads if _pair_at(pe, addr) == "force"]
    cleared = [addr for addr in loads if _pair_at(pe, addr) == "cleared"]
    if cleared:
        for addr in cleared:
            _restore_mesh_floor(pe, buf, addr)
        return "patched", f"MeshShaderTier is advertised again ({len(cleared)} ARM64 constant(s))"
    if forced:
        return "already", "MeshShaderTier stays advertised (ARM64)"
    scalar = _patch_tier_arm64_scalar(pe, buf, start, end)
    if scalar:
        return scalar
    return "missing", "MeshShaderTier constant was not found in d3d12_device_caps_override"


def _patch_tier_arm64_scalar(pe: Pe, buf: bytearray, start: int, end: int) -> tuple[str, str] | None:
    text = pe.section(".text")
    if text is None:
        return None
    movs: list[tuple[int, int, int]] = []  # rva, imm, file off of insn
    rva = start
    while rva + 4 <= end:
        insn = pe.u32(rva)
        if (insn & 0xFF800000) == 0x52800000:
            imm = (insn >> 5) & 0xFFFF
            if imm in (0, MESH_TIER, *FEEDBACK_TIERS):
                movs.append((rva, imm, pe.rva_to_off(rva)))
        rva += 4
    tens = [m for m in movs if m[1] == MESH_TIER]
    feedbacks = [m for m in movs if m[1] in FEEDBACK_TIERS]
    zeros = [m for m in movs if m[1] == 0]
    if tens and feedbacks:
        near = min(abs(t[0] - f[0]) for t in tens for f in feedbacks)
        if near <= 40 * 4:
            return "already", "MeshShaderTier stays advertised (ARM64 MOV)"
    if zeros and feedbacks and not tens:
        target = min(zeros, key=lambda m: min(abs(m[0] - f[0]) for f in feedbacks))
        dist = min(abs(target[0] - f[0]) for f in feedbacks)
        if dist > 40 * 4:
            return None
        off = target[2]
        insn = struct.unpack_from("<I", buf, off)[0]
        insn = (insn & ~(0xFFFF << 5)) | (MESH_TIER << 5)
        struct.pack_into("<I", buf, off, insn)
        return "patched", "MeshShaderTier is advertised again (ARM64 immediate MOV)"
    return None


def _patch_tier_x64(pe: Pe, buf: bytearray, start: int, end: int) -> tuple[str, str]:
    text = pe.section(".text")
    if text is None:
        return "missing", "no .text section"
    blob = pe.data[text.rawptr : text.rawptr + text.rawsize]
    base = text.va
    refs: list[int] = []
    rel_lo = max(0, start - base)
    rel_hi = min(len(blob) - 8, end - base)
    for rel in range(rel_lo, rel_hi):
        rva = base + rel
        window = blob[rel : rel + 4]
        if window not in (b"\x66\x0f\x6f\x0d", b"\x66\x0f\x66\x0d", b"\x66\x0f\xdf\x0d", b"\x66\x0f\xef\x0d"):
            continue
        disp = struct.unpack_from("<i", blob, rel + 4)[0]
        target = rva + 8 + disp
        refs.append(target)

    forced = [addr for addr in refs if _pair_at(pe, addr) == "force" or _biased_at(pe, addr) == "force"]
    cleared = [addr for addr in refs if _pair_at(pe, addr) == "cleared" or _biased_at(pe, addr) == "cleared"]
    if not forced and not cleared:
        return "missing", "MeshShaderTier constant was not found in the x86_64 DLL"
    restored: set[int] = set()
    for addr in cleared:
        for delta in (0, -16, 16, -32, 32):
            neighbor = addr + delta
            if neighbor in restored:
                continue
            if _biased_at(pe, neighbor) == "cleared":
                _restore_biased_floor(pe, buf, neighbor)
                restored.add(neighbor)
            elif _pair_at(pe, neighbor) == "cleared":
                _restore_mesh_floor(pe, buf, neighbor)
                restored.add(neighbor)
    if restored:
        return "patched", f"MeshShaderTier is advertised again ({len(restored)} x86_64 constant(s))"
    if forced:
        return "already", "MeshShaderTier stays advertised (x86_64)"
    return "missing", "MeshShaderTier constant was not recognized"


def _pair_at(pe: Pe, rva: int) -> str:
    try:
        off = pe.rva_to_off(rva)
    except PeError:
        return ""
    if off + 8 > len(pe.data):
        return ""
    a, b = struct.unpack_from("<II", pe.data, off)
    if a == MESH_TIER and b in FEEDBACK_TIERS:
        return "force"
    if a == 0 and b in FEEDBACK_TIERS:
        return "cleared"
    return ""


def _biased_at(pe: Pe, rva: int) -> str:
    """SSE signed-max trick stores mesh|0x80000000 next to feedback|0x80000000."""
    try:
        off = pe.rva_to_off(rva)
    except PeError:
        return ""
    if off + 8 > len(pe.data):
        return ""
    a, b = struct.unpack_from("<II", pe.data, off)
    sign = 0x80000000
    if a == (MESH_TIER | sign) and (b & ~sign) in FEEDBACK_TIERS and (b & sign):
        return "force"
    if a == sign and (b & ~sign) in FEEDBACK_TIERS and (b & sign):
        return "cleared"
    return ""


def _restore_mesh_floor(pe: Pe, buf: bytearray, rva: int) -> None:
    off = pe.rva_to_off(rva)
    struct.pack_into("<I", buf, off, MESH_TIER)


def _restore_biased_floor(pe: Pe, buf: bytearray, rva: int) -> None:
    off = pe.rva_to_off(rva)
    struct.pack_into("<I", buf, off, MESH_TIER | 0x80000000)


def _arm64_d_loads(pe: Pe, start: int, end: int) -> list[int]:
    text = pe.section(".text")
    if text is None:
        return []
    addrs: list[int] = []
    rva = start
    pending: dict[int, int] = {}
    while rva + 4 <= end:
        insn = pe.u32(rva)
        if (insn & 0x9F000000) == 0x90000000:
            pending[insn & 31] = decode_adrp(insn, rva)
        elif (insn & 0xFF800000) == 0x91000000:
            rd = insn & 31
            rn = (insn >> 5) & 31
            if rn in pending and rd == rn:
                pending[rd] = pending[rn] + decode_add_imm(insn)
        elif (insn & 0xFFC00000) == 0xFD400000:
            rn = (insn >> 5) & 31
            if rn in pending:
                imm = ((insn >> 10) & 0xFFF) * 8
                addrs.append(pending[rn] + imm)
        elif (insn & 0xFFC00000) in (0xF9400000, 0xB9400000):
            # A GPR load from the same page base is not a SIMD floor, but it
            # consumes the ADRP. Drop the base if this instruction overwrites it.
            rd = insn & 31
            pending.pop(rd, None)
        else:
            rd = insn & 31
            # ADRP/ADD/LDR above already handled their dest. Other writes to
            # the low register field are common enough that keeping a stale
            # page would invent addresses. Only ADRP refreshes a base.
            if (insn & 0x9F000000) != 0x90000000:
                pending.pop(rd, None)
        rva += 4
    return addrs


def _code_xrefs(pe: Pe, target: int) -> list[int]:
    if pe.machine == 0xAA64:
        return _xrefs_arm64(pe, target)
    if pe.machine == 0x8664:
        return _xrefs_x64(pe, target)
    return []


def _xrefs_arm64(pe: Pe, target: int) -> list[int]:
    text = pe.section(".text")
    if text is None:
        return []
    blob = pe.data[text.rawptr : text.rawptr + text.rawsize]
    hits: list[int] = []
    for off in range(0, len(blob) - 8, 4):
        insn = struct.unpack_from("<I", blob, off)[0]
        if (insn & 0x9F000000) != 0x90000000:
            continue
        pc = text.va + off
        page = decode_adrp(insn, pc)
        insn2 = struct.unpack_from("<I", blob, off + 4)[0]
        if (insn2 & 0xFF800000) != 0x91000000:
            continue
        rn = (insn2 >> 5) & 31
        if rn != (insn & 31):
            continue
        if page + decode_add_imm(insn2) == target:
            hits.append(pc)
    return hits


def _xrefs_x64(pe: Pe, target: int) -> list[int]:
    text = pe.section(".text")
    if text is None:
        return []
    blob = pe.data[text.rawptr : text.rawptr + text.rawsize]
    hits: list[int] = []
    for off in range(0, len(blob) - 7):
        if blob[off + 1] != 0x8D or blob[off] not in (0x48, 0x4C):
            continue
        modrm = blob[off + 2]
        if (modrm & 0xC7) != 0x05:
            continue
        disp = struct.unpack_from("<i", blob, off + 3)[0]
        pc = text.va + off
        if pc + 7 + disp == target:
            hits.append(pc)
    return hits


def _patch_arm64_null_stub(pe: Pe, buf: bytearray) -> tuple[str, str, bytearray]:
    if pe.section(STUB_SECTION) is not None:
        return _repair_mesh_stub(pe, buf)
    sites: list[tuple[int, int]] = []
    missing: list[str] = []
    seen_stores: set[int] = set()
    for name in MESH_FUNCS:
        rvas = pe.find_all_cstrings(name)
        if not rvas:
            missing.append(name.decode())
            continue
        found = 0
        for rva in rvas:
            for xref in _xrefs_arm64(pe, rva):
                store = _mesh_store_after(pe, xref)
                if store is None:
                    continue
                store_rva, store_insn = store
                if store_rva in seen_stores or pe.reloc_overlaps(store_rva, 4):
                    continue
                seen_stores.add(store_rva)
                sites.append((store_rva, store_insn))
                found += 1
        if not found:
            missing.append(name.decode())
    if not sites:
        note = "vkCmdDrawMeshTasks* store was not found; the mesh-shader advertisement is still corrected"
        if missing:
            note += " (" + ", ".join(missing) + ")"
        return "skipped", note, buf

    stub, bl_targets = _build_stub(sites)
    try:
        patched = _append_section(pe, buf, STUB_SECTION, stub)
    except PeError as exc:
        return "skipped", f"could not add the mesh-shader return stub ({exc})", buf
    new_pe = Pe(patched)
    sec = new_pe.section(STUB_SECTION)
    if sec is None:
        return "skipped", "the return section was not added to the DLL", buf
    for (store_rva, _insn), target in zip(sites, bl_targets):
        off = new_pe.rva_to_off(store_rva)
        bl = _encode_bl(store_rva, sec.va + target)
        struct.pack_into("<I", patched, off, bl)
    names = ", ".join(n.decode().removeprefix("vkCmd") for n in MESH_FUNCS if n.decode() not in missing)
    return "patched", f"a NULL mesh call returns instead of closing the game ({len(sites)} site(s): {names})", patched


def _mesh_store_after(pe: Pe, adrp_rva: int) -> tuple[int, int] | None:
    """Return (rva, insn) of the STR X0 that saves vkGetDeviceProcAddr's result."""
    saw_blr = False
    for step in range(0, 12):
        rva = adrp_rva + step * 4
        try:
            insn = pe.u32(rva)
        except PeError:
            return None
        if (insn & 0xFFFFFC1F) == 0xD63F0000:
            saw_blr = True
            continue
        if saw_blr and (insn & 0xFFC00000) == 0xF9000000 and (insn & 31) == 0:
            return rva, insn
    return None


def _build_stub(sites: list[tuple[int, int]]) -> tuple[bytes, list[int]]:
    """One island per store: if X0 is null, point it at a shared x86 ret, then store.

    The island itself runs as ARM64 while vkGetDeviceProcAddr is resolving the
    pointer. The value stored for later draws is an x86 ret, because ARM64EC
    enters that pointer through FEX.

    Layout per site (16 bytes):
        cbnz x0, +8
        adr  x0, shared_ret
        <original str x0, [base, #off]>
        ret                 ; ARM64, back to the resolver
    shared_ret:
        ret; nop; nop; nop  ; x86, what the game actually calls
    """
    body = bytearray()
    targets: list[int] = []
    shared = 16 * len(sites)
    for _rva, store in sites:
        targets.append(len(body))
        adr_at = len(body) + 4
        delta = shared - adr_at
        body += struct.pack("<I", 0xB5000040)  # cbnz x0, #+8
        body += struct.pack("<I", _encode_adr(0, delta))
        body += struct.pack("<I", store)
        body += struct.pack("<I", ARM64_RET)
    body += X86_RET
    return bytes(body), targets


def _repair_mesh_stub(pe: Pe, buf: bytearray) -> tuple[str, str, bytearray]:
    sec = pe.section(STUB_SECTION)
    if sec is None:
        return "skipped", "the mesh return section is missing", buf
    content = pe.data[sec.rawptr : sec.rawptr + sec.vsize]
    shared = _stub_shared_off(content)
    if shared is None:
        return "skipped", "the mesh return section is not the expected stub", buf
    word = content[shared : shared + 4]
    if word == X86_RET:
        return "already", "NULL mesh calls already return through an x86 ret", buf
    if word == struct.pack("<I", ARM64_RET):
        buf[sec.rawptr + shared : sec.rawptr + shared + 4] = X86_RET
        return "patched", "NULL mesh calls now return through an x86 ret", buf
    return "skipped", "the shared mesh return is neither an x86 ret nor an ARM64 ret", buf


def _stub_shared_off(content: bytes) -> int | None:
    off = 0
    shared: int | None = None
    while off + 16 <= len(content):
        words = struct.unpack_from("<IIII", content, off)
        if words[0] != 0xB5000040 or words[3] != ARM64_RET:
            break
        delta = _decode_adr_off(words[1])
        if delta is None:
            return None
        target = off + 4 + delta
        if shared is None:
            shared = target
        elif shared != target:
            return None
        off += 16
    if off == 0 or shared != off or off + 4 > len(content):
        return None
    return off


def _decode_adr_off(insn: int) -> int | None:
    if (insn & 0x9F000000) != 0x10000000:
        return None
    immlo = (insn >> 29) & 3
    immhi = (insn >> 5) & 0x7FFFF
    imm = (immhi << 2) | immlo
    if imm & (1 << 20):
        imm -= 1 << 21
    return imm


def _patch_wave_arm64(pe: Pe, buf: bytearray) -> tuple[str, str]:
    """Accept a wave-32 shader on a GPU whose smallest subgroup is larger than 32.

    vkd3d already has that path, gated on meta flag ALLOW_WAVE32 (bit 29).
    Rebirth's shader does not set the flag. Clearing the test takes the same
    path: the shader is kept and no required subgroup size of 32 is requested.
    """
    text = pe.section(".text")
    if text is None or pe.find_cstring(WAVE_SIZE_LOG) is None:
        return "missing", "the wave-size check was not found"
    opened = 0
    gated = 0
    for off in range(32, text.rawsize - 16, 4):
        file_off = text.rawptr + off
        ins = [struct.unpack_from("<I", buf, file_off + i * 4)[0] for i in range(-8, 5)]
        kind = _wave_gate_arm64(ins)
        if kind == "gate":
            struct.pack_into("<I", buf, file_off, ARM64_NOP)
            gated += 1
        elif kind == "open":
            opened += 1
    if gated:
        return "patched", f"wave size 32 is accepted on a wave-64 GPU ({gated} check(s))"
    if opened:
        return "already", "wave size 32 was already accepted"
    return "missing", "the wave-size check was not found"


def _wave_gate_arm64(ins: list[int]) -> str | None:
    if (ins[0] & 0xFFFFFC00) != 0xB968B400:  # ldr w, [x, #10420] device max
        return None
    if (ins[1] & 0xFF20001F) != 0x6B00001F:  # cmp
        return None
    if (ins[2] & 0xFF00001F) != 0x54000003:  # b.cc
        return None
    if (ins[3] & 0xFFFFFC00) != 0x39406400:  # ldrb w, [x, #25] shader max
        return None
    if (ins[4] & 0xFFFFFC00) != 0xB968B000:  # ldr w, [x, #10416] device min
        return None
    if (ins[5] & 0xFF20001F) != 0x6B00001F:
        return None
    if (ins[6] & 0xFF00001F) != 0x54000009:  # b.ls
        return None
    if (ins[7] & 0xFFFFFC00) != 0xB968B000:
        return None
    if (ins[9] & 0xFFFFFC1F) != 0x7100801F:  # cmp w, #32
        return None
    if (ins[10] & 0xFF00001F) != 0x54000001:  # b.ne
        return None
    if (ins[11] & 0xFFFFFC1F) != 0x7100801F:
        return None
    if (ins[12] & 0xFF00001F) != 0x54000009:  # b.ls
        return None
    if (ins[8] & 0xFFF80000) == 0x36E80000:  # tbz w, #29
        return "gate"
    if ins[8] == ARM64_NOP:
        return "open"
    return None


# shr r10d, 29; cmp r8d, #32; sete r11b; and r11b, r10b; mov r10d, [rcx+0x28B0]; cmp r10d, #33; setae bl; test; je
_WAVE_X64_GATE = bytes.fromhex("41c1ea1d4183f820410f94c34520d3448b91b02800004183fa210f93c34184db74")
_WAVE_X64_OPEN = bytes.fromhex("41c1ea1d4183f820410f94c3909090448b91b02800004183fa210f93c34184db74")
_WAVE_X64_AND = 12


def _patch_wave_x64(pe: Pe, buf: bytearray) -> tuple[str, str]:
    text = pe.section(".text")
    if text is None or pe.find_cstring(WAVE_SIZE_LOG) is None:
        return "missing", "the wave-size check was not found"
    blob = buf[text.rawptr : text.rawptr + text.rawsize]
    gated = 0
    opened = 0
    start = 0
    while True:
        gate = blob.find(_WAVE_X64_GATE, start)
        opened_at = blob.find(_WAVE_X64_OPEN, start)
        if gate < 0 and opened_at < 0:
            break
        if gate >= 0 and (opened_at < 0 or gate <= opened_at):
            at = text.rawptr + gate + _WAVE_X64_AND
            buf[at : at + 3] = b"\x90\x90\x90"
            blob = buf[text.rawptr : text.rawptr + text.rawsize]
            gated += 1
            start = gate + len(_WAVE_X64_GATE)
        else:
            opened += 1
            start = opened_at + len(_WAVE_X64_OPEN)
    if gated:
        return "patched", f"wave size 32 is accepted on a wave-64 GPU ({gated} check(s))"
    if opened:
        return "already", "wave size 32 was already accepted"
    return "missing", "the wave-size check was not found"


def _encode_adr(rd: int, byte_off: int) -> int:
    if byte_off < -(1 << 20) or byte_off >= (1 << 20):
        raise PeError("ADR out of range")
    imm = byte_off & 0x1FFFFF
    immlo = imm & 3
    immhi = (imm >> 2) & 0x7FFFF
    return 0x10000000 | (immlo << 29) | (immhi << 5) | (rd & 31)


def _encode_bl(pc: int, target: int) -> int:
    delta = target - pc
    if delta % 4:
        raise PeError("BL is not aligned")
    imm = delta >> 2
    if imm < -(1 << 25) or imm >= (1 << 25):
        raise PeError("BL out of range")
    return 0x94000000 | (imm & 0x03FFFFFF)


def _append_section(pe: Pe, buf: bytearray, name: str, content: bytes) -> bytearray:
    if pe.nsec >= 96:
        raise PeError("too many sections")
    header_off = pe.sec_off + pe.nsec * 40
    if header_off + 40 > pe.size_of_headers:
        raise PeError("no room for another section in the header")
    last_va = 0
    last_raw_end = 0
    for sec in pe.sections:
        last_va = max(last_va, sec.va + sec.vsize)
        last_raw_end = max(last_raw_end, sec.rawptr + sec.rawsize)
    va = align_up(last_va, pe.section_align or 0x1000)
    raw_off = align_up(max(last_raw_end, len(buf)), pe.file_align or 0x200)
    raw_size = align_up(len(content), pe.file_align or 0x200)
    if len(buf) < raw_off:
        buf = bytearray(buf) + bytearray(raw_off - len(buf))
    else:
        buf = bytearray(buf)
    payload = content + bytes(raw_size - len(content))
    if len(buf) < raw_off:
        buf += bytearray(raw_off - len(buf))
    buf[raw_off : raw_off + raw_size] = payload
    raw_name = name.encode("ascii")[:8]
    raw_name = raw_name + bytes(8 - len(raw_name))
    struct.pack_into("<8sIIIIIIHHI", buf, header_off,
                     raw_name, len(content), va, raw_size, raw_off,
                     0, 0, 0, 0, 0x60000020)
    struct.pack_into("<H", buf, pe.e_lfanew + 6, pe.nsec + 1)
    size_of_image = align_up(va + len(content), pe.section_align or 0x1000)
    struct.pack_into("<I", buf, pe.opt + 56, size_of_image)
    return buf
