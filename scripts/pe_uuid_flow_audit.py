#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-Volnist
"""Static, read-only audit of the Windows UUID -> UVM IOCTL payload data flow.

Checks one shipped artifact only. No driver ioctl, no MMIO, no execution of
target code. pefile maps addresses; capstone decodes bounded instruction ranges.
The linear sweep in this PE drifts, so ranges start at known pdata entries.

Dependencies: python3 -m pip install --user pefile capstone
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

import capstone
import pefile
from capstone.x86 import X86_OP_IMM, X86_OP_MEM, X86_OP_REG, X86_REG_RIP, X86_REG_XMM2

DEFAULT_PATH = (
    r"C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_58519edca6172ba9"
    r"\nvcuda64.dll"
)
EXPECTED_SHA = "af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407"

TABLE_READ = 0x1803C5B41
PAYLOAD_STORE = 0x1803C5C04
IOCTL_CALL = 0x1803C5C09
HELPER = 0x1803396C0
CUUID_READ = 0x18004887D
IOCTL = 0x22E034
IN_SIZE = 0x28
COUNT_VA = 0x182002A48
TABLE_VA = 0x182002848
FLAG_VA = 0x182004BC8


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hx(value: int) -> str:
    return hex(value)


def text(insn: capstone.CsInsn) -> str:
    return insn.mnemonic + " " + insn.op_str


class Image:
    def __init__(self, path: Path) -> None:
        self.raw = path.read_bytes()
        self.pe = pefile.PE(str(path), fast_load=True)
        self.base = self.pe.OPTIONAL_HEADER.ImageBase
        self.sections = []
        for sec in self.pe.sections:
            name = sec.Name.rstrip(b"\0").decode("ascii", errors="replace")
            self.sections.append(
                {
                    "name": name,
                    "va": self.base + sec.VirtualAddress,
                    "rva": sec.VirtualAddress,
                    "vs": sec.Misc_VirtualSize,
                    "raw": sec.PointerToRawData,
                    "rs": sec.SizeOfRawData,
                }
            )

    def section(self, va: int) -> dict | None:
        for sec in self.sections:
            if sec["va"] <= va < sec["va"] + sec["vs"]:
                return sec
        return None

    def offset(self, va: int) -> int:
        sec = self.section(va)
        if sec is None:
            raise ValueError(f"VA {hx(va)} is outside every section")
        rva = va - sec["va"]
        if rva >= sec["rs"]:
            raise ValueError(f"VA {hx(va)} is in the zero-filled tail of {sec['name']}")
        return sec["raw"] + rva

    def va_of_offset(self, off: int) -> int | None:
        for sec in self.sections:
            if sec["raw"] <= off < sec["raw"] + sec["rs"]:
                return sec["va"] + off - sec["raw"]
        return None

    def disasm(self, start: int, end: int) -> list[capstone.CsInsn]:
        md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
        md.detail = True
        o = self.offset(start)
        return list(md.disasm(self.raw[o : o + (end - start)], start))


def pdata_entries(img: Image, va: int) -> list[dict]:
    sec = next((s for s in img.sections if s["name"] == ".pdata"), None)
    if sec is None:
        return []
    text_sec = next((s for s in img.sections if s["name"] == ".text"), None)
    found = []
    for o in range(sec["raw"], sec["raw"] + sec["rs"] - 11, 4):
        begin, end, unwind = struct.unpack_from("<III", img.raw, o)
        if not (begin and begin <= va - img.base < end):
            continue
        length = end - begin
        if text_sec is None or not (
            text_sec["rva"] <= begin < text_sec["rva"] + text_sec["rs"]
            and text_sec["rva"] <= end <= text_sec["rva"] + text_sec["rs"]
        ):
            continue
        if length > 0x10000 or img.section(img.base + unwind) is None:
            continue
        found.append(
            {
                "pdata_file_offset": hx(o),
                "begin": hx(img.base + begin),
                "end": hx(img.base + end),
                "length": hx(length),
                "unwind": hx(img.base + unwind),
            }
        )
    return sorted(found, key=lambda r: int(r["length"], 16))


def rip_target(insn: capstone.CsInsn) -> int | None:
    for op in insn.operands:
        if op.type == X86_OP_MEM and op.mem.base == X86_REG_RIP:
            return insn.address + insn.size + op.mem.disp
    return None


def describe_va(img: Image, va: int) -> dict:
    sec = img.section(va)
    rva = va - sec["va"] if sec else None
    in_raw = bool(sec and rva is not None and rva < sec["rs"])
    return {
        "va": hx(va),
        "section": sec["name"] if sec else None,
        "rva": hx(rva) if rva is not None else None,
        "file_backed": in_raw,
    }


def rdata_rva_refs(img: Image, rva: int) -> list[dict]:
    pat = struct.pack("<I", rva)
    hits = []
    p = 0
    while True:
        j = img.raw.find(pat, p)
        if j < 0:
            break
        p = j + 1
        va = img.va_of_offset(j)
        sec = img.section(va) if va is not None else None
        hits.append(
            {
                "file_offset": hx(j),
                "va": hx(va) if va else None,
                "section": sec["name"] if sec else None,
                "following_dwords": [hx(x) for x in struct.unpack_from("<III", img.raw, j + 4)],
            }
        )
    return hits


def audit(path: Path) -> dict:
    digest = sha256(path)
    if digest != EXPECTED_SHA:
        raise SystemExit(f"SHA-256 mismatch for {path}: {digest} != {EXPECTED_SHA}")
    img = Image(path)

    main = {
        i.address: i for i in img.disasm(0x1803C5B20, 0x1803C5C30)
    }
    cu = {i.address: i for i in img.disasm(0x180048870, 0x180048899)}
    required = [
        TABLE_READ,
        0x1803C5B2A,
        0x1803C5B36,
        0x1803C5B3D,
        0x1803C5BEA,
        0x1803C5BDF,
        PAYLOAD_STORE,
        IOCTL_CALL,
    ]
    if not all(a in main for a in required) or CUUID_READ not in cu:
        raise SystemExit("bounded disassembly did not reach every required address")

    insns = []
    for a in required + [CUUID_READ]:
        insn = (main if a != CUUID_READ else cu)[a]
        insns.append(
            {
                "va": hx(a),
                "bytes": insn.bytes.hex(),
                "instruction": text(insn),
                "size": insn.size,
            }
        )

    targets = []
    for a in (0x1803C5B2A, 0x1803C5B36):
        t = rip_target(main[a])
        if t is None:
            raise SystemExit(f"no RIP-relative operand at {hx(a)}")
        targets.append({**describe_va(img, t), "instruction_va": hx(a)})

    call_op = main[IOCTL_CALL].operands[0]
    call_target = None
    if call_op.type == X86_OP_IMM:
        call_target = call_op.imm

    # capstone 5.0.7 leaves implicit regs_read/regs_write empty for movups here,
    # so inspect explicit operands instead.
    def writes_xmm2(insn: capstone.CsInsn) -> bool:
        return X86_REG_XMM2 in insn.regs_write or (
            bool(insn.operands)
            and insn.operands[0].type == X86_OP_REG
            and insn.operands[0].reg == X86_REG_XMM2
        )

    def reads_xmm2(insn: capstone.CsInsn) -> bool:
        return X86_REG_XMM2 in insn.regs_read or any(
            op.type == X86_OP_REG and op.reg == X86_REG_XMM2 for op in insn.operands[1:]
        )

    writes_between = [
        hx(i.address)
        for i in main.values()
        if TABLE_READ < i.address < PAYLOAD_STORE and writes_xmm2(i)
    ]
    reads_store = reads_xmm2(main[PAYLOAD_STORE])

    checks = {
        "artifact_sha256": digest == EXPECTED_SHA,
        "table_read_opcode": main[TABLE_READ].bytes.hex() == "0f1091060c0000",
        "payload_store_opcode": main[PAYLOAD_STORE].bytes.hex() == "0f11542468",
        "count_rip_target": targets[0]["va"] == hx(COUNT_VA),
        "pointer_table_rip_target": targets[1]["va"] == hx(TABLE_VA),
        "no_xmm2_write_between": writes_between == [],
        "xmm2_read_at_payload_store": reads_store,
        "call_target_is_helper": call_target == HELPER,
        "ioctl_immediate": main[0x1803C5BEA].bytes.hex() == "ba34e02200",
        "in_size_40": main[0x1803C5BDF].bytes.hex() == "41b928000000",
        "bss_count_not_file_backed": targets[0]["file_backed"] is False,
        "bss_table_not_file_backed": targets[1]["file_backed"] is False,
        "flag_not_file_backed": describe_va(img, FLAG_VA)["file_backed"] is False,
        "cuuid_read_opcode": cu[CUUID_READ].bytes.hex() == "0f1080060c0000",
    }
    if not all(checks.values()):
        raise SystemExit(f"failed checks: {[k for k, v in checks.items() if not v]}")

    return {
        "artifact": {
            "path": str(path),
            "sha256": digest,
            "size": len(img.raw),
            "image_base": hx(img.base),
        },
        "tools": {
            "python": "3.12.10",
            "pefile": pefile.__version__,
            "capstone": capstone.__version__,
            "rizin_cross_check": "0.9.1 (separate REA Evidence, not required here)",
        },
        "method": (
            "pefile VA mapping + bounded capstone decode from pdata-aligned starts. "
            "No linear whole-section sweep, no target execution."
        ),
        "function_ranges": {
            "contains_table_read": pdata_entries(img, TABLE_READ),
            "contains_payload_store_and_call": pdata_entries(img, PAYLOAD_STORE),
            "contains_third_copy_call": pdata_entries(img, 0x1803E4CC0),
            "contains_cuuid_read": pdata_entries(img, CUUID_READ),
        },
        "instructions": insns,
        "rip_targets": targets,
        "global_flag": describe_va(img, FLAG_VA),
        "data_flow": {
            "source": "qword [0x182002848 + r10*8] -> [rcx+0xc06] (16 bytes)",
            "intermediate": "xmm2, no intervening write from 0x1803c5b41 to 0x1803c5c04",
            "destination": "0x22e034 input buffer +0x08..+0x17 at [rsp+0x68]",
            "call": {"va": hx(IOCTL_CALL), "target": hx(call_target)},
            "ioctl": hx(IOCTL),
            "input_size": hx(IN_SIZE),
            "output_size": hx(IN_SIZE),
            "index_source": "r9d sign-extended to r10 at 0x1803c5a99; bounds check vs [0x182002a48]",
        },
        "cuuid_field": {
            "read_va": hx(CUUID_READ),
            "bytes": cu[CUUID_READ].bytes.hex(),
            "instruction": text(cu[CUUID_READ]),
            "same_offset_and_width": True,
            "object_identity_proven": False,
        },
        "rdata_rva_refs": {
            "function_start_0x1803c5a70": rdata_rva_refs(img, 0x3C5A70),
            "function_start_0x1803e4c10": rdata_rva_refs(img, 0x3E4C10),
        },
        "checks": checks,
        "verdict": {
            "proven": "16 bytes at object+0xc06 are copied into 0x22e034 input+0x08",
            "unproven": [
                "the object at [0x182002848+r10*8] is a CUdevice",
                "0x22e034 equals Linux UVM_REGISTER_GPU (0x25)",
                "r10 is an RM gpu_id or CUDA ordinal",
                "runtime values of the BSS count, table and flag",
            ],
        },
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("artifact", nargs="?", default=DEFAULT_PATH)
    ap.add_argument("output", nargs="?", default="evidence/windows-20261128/uuid_to_ioctl_audit.json")
    args = ap.parse_args()
    result = audit(Path(args.artifact))
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    # write_bytes keeps LF on every host so the manifest digest is stable
    out.write_bytes(
        (json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
    )
    print(f"wrote {out} ({sum(result['checks'].values())}/{len(result['checks'])} checks OK)")


if __name__ == "__main__":
    main()
