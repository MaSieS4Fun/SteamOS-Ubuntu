"""Minimal PE32+ reader/writer for the vkd3d-proton DLLs shipped in Proton."""

from __future__ import annotations

import struct
from dataclasses import dataclass


class PeError(Exception):
    pass


@dataclass
class Section:
    name: str
    vsize: int
    va: int
    rawsize: int
    rawptr: int
    characteristics: int
    header_off: int


class Pe:
    def __init__(self, data: bytes):
        if len(data) < 0x100 or data[:2] != b"MZ":
            raise PeError("not a PE executable")
        self.data = data
        self.e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
        if data[self.e_lfanew : self.e_lfanew + 4] != b"PE\0\0":
            raise PeError("PE header is missing")
        coff = self.e_lfanew + 4
        (
            self.machine,
            self.nsec,
            _tstamp,
            _sym,
            _nsym,
            self.optsize,
            self.characteristics,
        ) = struct.unpack_from("<HHIIIHH", data, coff)
        self.opt = coff + 20
        self.magic = struct.unpack_from("<H", data, self.opt)[0]
        if self.magic != 0x20B:
            raise PeError("PE32+ (64-bit) is required")
        self.image_base = struct.unpack_from("<Q", data, self.opt + 24)[0]
        self.section_align = struct.unpack_from("<I", data, self.opt + 32)[0]
        self.file_align = struct.unpack_from("<I", data, self.opt + 36)[0]
        self.size_of_image = struct.unpack_from("<I", data, self.opt + 56)[0]
        self.size_of_headers = struct.unpack_from("<I", data, self.opt + 60)[0]
        self.sec_off = self.opt + self.optsize
        self.sections: list[Section] = []
        for i in range(self.nsec):
            off = self.sec_off + i * 40
            name = data[off : off + 8].split(b"\0", 1)[0].decode("ascii", "replace")
            vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, off + 8)
            chars = struct.unpack_from("<I", data, off + 36)[0]
            self.sections.append(Section(name, vsize, va, rawsize, rawptr, chars, off))

    def section(self, name: str) -> Section | None:
        for sec in self.sections:
            if sec.name == name:
                return sec
        return None

    def rva_to_off(self, rva: int) -> int:
        for sec in self.sections:
            span = max(sec.vsize, sec.rawsize)
            if sec.va <= rva < sec.va + span:
                return sec.rawptr + (rva - sec.va)
        raise PeError(f"RVA {rva:#x} is outside the sections")

    def off_to_rva(self, off: int) -> int:
        for sec in self.sections:
            if sec.rawptr <= off < sec.rawptr + sec.rawsize:
                return sec.va + (off - sec.rawptr)
        raise PeError(f"offset {off:#x} is outside the sections")

    def find_cstring(self, text: bytes) -> int | None:
        found = self.find_all_cstrings(text)
        return found[0] if found else None

    def find_all_cstrings(self, text: bytes) -> list[int]:
        needle = text + b"\x00"
        start = 0
        blob = self.data
        found: list[int] = []
        while True:
            i = blob.find(needle, start)
            if i < 0:
                return found
            if i == 0 or blob[i - 1] == 0:
                try:
                    found.append(self.off_to_rva(i))
                except PeError:
                    pass
            start = i + 1

    def u32(self, rva: int) -> int:
        return struct.unpack_from("<I", self.data, self.rva_to_off(rva))[0]

    def function_bounds(self, rva: int) -> tuple[int, int]:
        pdata = self.section(".pdata")
        if pdata is None:
            raise PeError("the DLL has no .pdata")
        blob = self.data[pdata.rawptr : pdata.rawptr + pdata.rawsize]
        if self.machine == 0xAA64:
            return self._bounds_arm64(blob, rva)
        if self.machine == 0x8664:
            return _bounds_x64(blob, rva)
        raise PeError(f"unsupported PE architecture ({self.machine:#x})")

    def _bounds_arm64(self, blob: bytes, rva: int) -> tuple[int, int]:
        count = len(blob) // 8
        owner: tuple[int, int] | None = None
        following: int | None = None
        for i in range(count):
            begin, unwind = struct.unpack_from("<II", blob, i * 8)
            if begin <= rva:
                owner = (begin, unwind)
            elif owner is not None:
                following = begin
                break
        if owner is None:
            raise PeError(f"no .pdata function covers {rva:#x}")
        begin, unwind = owner
        end: int | None = None
        if (unwind & 3) == 0 and unwind:
            try:
                info = self.u32(unwind)
            except PeError:
                info = 0
            units = info & 0x3FFFF
            if units:
                end = begin + units * 4
        if end is None or not (begin <= rva < end):
            if following is None or following <= begin:
                raise PeError(f"could not measure the function at {rva:#x}")
            end = following
        if following is not None and following > begin:
            end = min(end, following)
        if not (begin <= rva < end):
            raise PeError(f"no .pdata function covers {rva:#x}")
        return begin, end

    def reloc_overlaps(self, rva: int, size: int = 4) -> bool:
        sec = self.section(".reloc")
        if sec is None:
            return False
        blob = self.data[sec.rawptr : sec.rawptr + sec.rawsize]
        o = 0
        while o + 8 <= len(blob):
            page, block = struct.unpack_from("<II", blob, o)
            if block < 8 or o + block > len(blob):
                break
            count = (block - 8) // 2
            for i in range(count):
                ent = struct.unpack_from("<H", blob, o + 8 + 2 * i)[0]
                typ = ent >> 12
                if typ == 0:
                    continue
                loc = page + (ent & 0xFFF)
                width = 8 if typ == 10 else 4
                if loc < rva + size and rva < loc + width:
                    return True
            o += block
        return False


def _bounds_x64(blob: bytes, rva: int) -> tuple[int, int]:
    count = len(blob) // 12
    lo, hi = 0, count
    while lo < hi:
        mid = (lo + hi) // 2
        begin = struct.unpack_from("<I", blob, mid * 12)[0]
        if begin <= rva:
            lo = mid + 1
        else:
            hi = mid
    if lo == 0:
        raise PeError(f"no .pdata function covers {rva:#x}")
    begin, end, _unwind = struct.unpack_from("<III", blob, (lo - 1) * 12)
    if not (begin <= rva < end):
        raise PeError(f"no .pdata function covers {rva:#x}")
    return begin, end


def align_up(value: int, align: int) -> int:
    if align <= 1:
        return value
    return (value + align - 1) & ~(align - 1)


def decode_adrp(insn: int, pc: int) -> int:
    immlo = (insn >> 29) & 3
    immhi = (insn >> 5) & 0x7FFFF
    imm = (immhi << 2) | immlo
    if imm & (1 << 20):
        imm -= 1 << 21
    return (pc & ~0xFFF) + (imm << 12)


def decode_add_imm(insn: int) -> int:
    imm12 = (insn >> 10) & 0xFFF
    if (insn >> 22) & 1:
        imm12 <<= 12
    return imm12
