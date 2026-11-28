#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-Volnist
"""Static, read-only PE audit of a shipped Windows CUDA DLL.

No driver ioctl, no MMIO, no execution of target code. Uses pefile + capstone.
Raw E8/E9 scans find call sites; capstone backtracks from each site to recover
the immediately preceding instruction stream (a linear sweep drifts in this PE).

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

DEFAULT_PATH = (
    r"C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_58519edca6172ba9"
    r"\nvcuda64.dll"
)
EXPECTED_SHA = "af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407"
HELPER = 0x1803396C0
UUID_IOCTL_FN = 0x18033A980
UUID_IOCTL = 0x22E034


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def text(insn: capstone.CsInsn) -> str:
    return insn.mnemonic + " " + insn.op_str


def contiguous(insns: list[capstone.CsInsn], start_va: int) -> bool:
    cur = start_va
    for insn in insns:
        if insn.address != cur:
            return False
        cur += insn.size
    return True


def backtrack(
    md: capstone.Cs,
    data: bytes,
    sec_va: int,
    end_off: int,
    expect_fn: int,
    max_back: int = 320,
) -> tuple[int, list[capstone.CsInsn], str, int] | None:
    """Find the longest contiguous instruction stream ending at end_off."""
    best = None
    for start in range(max(0, end_off - max_back), end_off):
        insns = list(md.disasm(data[start : end_off + 16], sec_va + start))
        if not insns:
            continue
        idx = next((n for n, i in enumerate(insns) if i.address == sec_va + end_off), None)
        if idx is None:
            continue
        call = insns[idx]
        if call.mnemonic not in ("call", "jmp") or not call.operands:
            continue
        op = call.operands[0]
        if op.type != capstone.x86.X86_OP_IMM or op.imm != expect_fn:
            continue
        if not contiguous(insns[: idx + 1], sec_va + start):
            continue
        if best is None or idx > best[0]:
            best = (idx, insns[:idx], text(call), start)
    return best


def backtrack_to_mov_edx(
    md: capstone.Cs, data: bytes, sec_va: int, mov_off: int, max_back: int = 96
) -> tuple[int, list[capstone.CsInsn], int] | None:
    best = None
    for start in range(max(0, mov_off - max_back), mov_off):
        insns = list(md.disasm(data[start : mov_off + 8], sec_va + start))
        if not insns:
            continue
        idx = next((n for n, i in enumerate(insns) if i.address == sec_va + mov_off), None)
        if idx is None or not contiguous(insns[: idx + 1], sec_va + start):
            continue
        if best is None or idx > best[0]:
            best = (idx, insns[: idx + 1], start)
    return best


def audit(path: Path, expected_sha: str) -> dict:
    digest = sha256(path)
    if digest != expected_sha:
        raise SystemExit(f"SHA-256 mismatch for {path}: {digest} != {expected_sha}")
    pe = pefile.PE(str(path), fast_load=True)
    pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_EXPORT"]]
    )
    base = pe.OPTIONAL_HEADER.ImageBase
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True

    exports = []
    if hasattr(pe, "DIRECTORY_ENTRY_EXPORT"):
        for exp in pe.DIRECTORY_ENTRY_EXPORT.symbols:
            va = base + exp.address
            if abs(va - UUID_IOCTL_FN) < 0x400 or abs(va - HELPER) < 0x400:
                exports.append(
                    {
                        "name": exp.name.decode(errors="replace") if exp.name else None,
                        "va": hex(va),
                        "delta_to_uuid_fn": va - UUID_IOCTL_FN,
                        "delta_to_helper": va - HELPER,
                    }
                )

    sections: list[dict] = []
    helper_calls: list[dict] = []
    uuid_fn_refs: list[dict] = []
    ioctl_34_context: list[dict] = []
    raw = path.read_bytes()
    mov34_pattern = b"\xBA" + struct.pack("<I", UUID_IOCTL)

    for sec in pe.sections:
        name = sec.Name.rstrip(b"\0").decode(errors="replace")
        sec_va = base + sec.VirtualAddress
        data = sec.get_data() or b""
        if not data:
            continue
        is_code = bool(sec.Characteristics & 0x20)  # IMAGE_SCN_CNT_CODE
        sections.append(
            {
                "name": name,
                "va": hex(sec_va),
                "size": len(data),
                "code": is_code,
                "raw_ptr": hex(sec.PointerToRawData),
            }
        )
        if not is_code:
            continue

        for off in range(0, len(data) - 5):
            if data[off] not in (0xE8, 0xE9):
                continue
            rel = struct.unpack_from("<i", data, off + 1)[0]
            dst = (sec_va + off + 5 + rel) & 0xFFFFFFFFFFFFFFFF
            if dst not in (HELPER, UUID_IOCTL_FN):
                continue
            got = backtrack(md, data, sec_va, off, dst)
            if not got:
                (helper_calls if dst == HELPER else uuid_fn_refs).append(
                    {"call_va": hex(sec_va + off), "status": "backtrack_failed"}
                )
                continue
            _, prev, calltxt, _ = got
            setup = []
            ioctl = None
            in_size = None
            for insn in prev:
                if insn.mnemonic != "mov" or len(insn.operands) != 2:
                    continue
                dst_op, src = insn.operands
                if (
                    dst_op.type != capstone.x86.X86_OP_REG
                    or src.type != capstone.x86.X86_OP_IMM
                ):
                    continue
                rn = insn.reg_name(dst_op.reg)
                rec = {"va": hex(insn.address), "text": text(insn)}
                if rn == "edx":
                    ioctl = src.imm
                    setup.append(rec)
                elif rn in ("r8d", "r9d"):
                    if rn == "r9d":
                        in_size = src.imm
                    setup.append(rec)
            entry = {
                "call_va": hex(sec_va + off),
                "call": calltxt,
                "target": hex(dst),
                "ioctl": hex(ioctl) if ioctl is not None else None,
                "in_size_r9d": hex(in_size) if in_size is not None else None,
                "setup": setup,
                "preceding_tail": [
                    {"va": hex(i.address), "bytes": i.bytes.hex(), "text": text(i)}
                    for i in prev[-12:]
                ],
            }
            if dst == HELPER:
                helper_calls.append(entry)
            else:
                uuid_fn_refs.append(entry)

        pos = 0
        while True:
            i = data.find(mov34_pattern, pos)
            if i < 0:
                break
            pos = i + 1
            got = backtrack_to_mov_edx(md, data, sec_va, i)
            if not got:
                ioctl_34_context.append(
                    {"va": hex(sec_va + i), "status": "backtrack_failed"}
                )
                continue
            _, insns, _ = got
            ioctl_34_context.append(
                {
                    "va": hex(sec_va + i),
                    "before": [
                        {"va": hex(x.address), "bytes": x.bytes.hex(), "text": text(x)}
                        for x in insns[-16:]
                    ],
                    "section": name,
                }
            )

    ptrs = []
    for pattern, label in (
        (struct.pack("<Q", UUID_IOCTL_FN), "va64"),
        (struct.pack("<I", UUID_IOCTL_FN - base), "rva32"),
    ):
        start = 0
        while True:
            i = raw.find(pattern, start)
            if i < 0:
                break
            containing = next(
                (
                    s.Name.rstrip(b"\0").decode(errors="replace")
                    for s in pe.sections
                    if s.PointerToRawData <= i < s.PointerToRawData + s.SizeOfRawData
                ),
                None,
            )
            ptrs.append({"file_offset": hex(i), "kind": label, "section": containing})
            start = i + 1

    return {
        "artifact": str(path),
        "sha256": digest,
        "tool": "pefile 2024.8.26 / capstone 5.0.7",
        "image_base": hex(base),
        "sections": sections,
        "exports_near_targets": exports,
        "helper": hex(HELPER),
        "helper_calls_count": len(helper_calls),
        "helper_calls": helper_calls,
        "distinct_ioctls": sorted(
            {c["ioctl"] for c in helper_calls if c.get("ioctl")},
            key=lambda x: int(x, 16),
        ),
        "uuid_ioctl_fn": hex(UUID_IOCTL_FN),
        "uuid_fn_refs": uuid_fn_refs,
        "uuid_ioctl_0x22e034_setups": ioctl_34_context,
        "raw_pointers_to_uuid_fn": ptrs,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("path", nargs="?", default=DEFAULT_PATH)
    ap.add_argument("output", nargs="?", default="pe_ioctl_audit.json")
    ap.add_argument("--expected-sha", default=EXPECTED_SHA)
    args = ap.parse_args()
    result = audit(Path(args.path), args.expected_sha)
    out = Path(args.output)
    out.write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
        newline="\n",  # deterministic LF hash on Windows too
    )
    summary = {
        k: result[k]
        for k in (
            "sha256",
            "helper_calls_count",
            "distinct_ioctls",
            "exports_near_targets",
            "uuid_fn_refs",
            "raw_pointers_to_uuid_fn",
        )
    }
    print(json.dumps(summary, indent=2))
    print("written:", out)


if __name__ == "__main__":
    main()
