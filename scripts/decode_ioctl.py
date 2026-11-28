#!/usr/bin/env python3
"""Decode NVIDIA ioctl request numbers and strace lines.

Examples:
    echo 0xc90046c8 | ./scripts/decode_ioctl.py
    ./scripts/decode_ioctl.py 0xc008462a 0x20803801
    strace -e ioctl ... 2>&1 | ./scripts/decode_ioctl.py
"""
from __future__ import annotations

import argparse
import re
import sys

# nv-ioctl-numbers.h (NV_IOCTL_BASE = 200)
NV_LEGACY = {
    200: "NV_ESC_CARD_INFO",
    201: "NV_ESC_REGISTER_FD",
    206: "NV_ESC_ALLOC_OS_EVENT",
    207: "NV_ESC_FREE_OS_EVENT",
    209: "NV_ESC_STATUS_CODE",
    210: "NV_ESC_CHECK_VERSION_STR",
    211: "NV_ESC_IOCTL_XFER_CMD",
    212: "NV_ESC_ATTACH_GPUS_TO_FD",
    213: "NV_ESC_QUERY_DEVICE_INTR",
    214: "NV_ESC_SYS_PARAMS",
    217: "NV_ESC_EXPORT_TO_DMABUF_FD",
    218: "NV_ESC_WAIT_OPEN_COMPLETE",
}

# nv_escape.h
NV_RM_ESCAPE = {
    0x27: "NV_ESC_RM_ALLOC_MEMORY", 0x28: "NV_ESC_RM_ALLOC_OBJECT",
    0x29: "NV_ESC_RM_FREE",         0x2A: "NV_ESC_RM_CONTROL",
    0x2B: "NV_ESC_RM_ALLOC",        0x32: "NV_ESC_RM_CONFIG_GET",
    0x33: "NV_ESC_RM_CONFIG_SET",   0x34: "NV_ESC_RM_DUP_OBJECT",
    0x35: "NV_ESC_RM_SHARE",        0x4A: "NV_ESC_RM_VID_HEAP_CONTROL",
    0x4D: "NV_ESC_RM_ACCESS_REGISTRY", 0x4E: "NV_ESC_RM_MAP_MEMORY",
    0x4F: "NV_ESC_RM_UNMAP_MEMORY", 0x5C: "NV_ESC_RM_EXPORT_OBJECT_TO_FD",
    0x5D: "NV_ESC_RM_IMPORT_OBJECT_FROM_FD",
}

# uvm_ioctl.h / uvm_linux_ioctl.h (type = 0)
UVM = {
    1: "UVM_INITIALIZE", 2: "UVM_RELEASE_VA", 3: "UVM_REGION_COMMIT",
    4: "UVM_REGION_DECOMMIT", 17: "UVM_EVENT_CTRL", 23: "UVM_CREATE_RANGE_GROUP",
    25: "UVM_REGISTER_GPU_VASPACE", 27: "UVM_REGISTER_CHANNEL",
    33: "UVM_MAP_EXTERNAL_ALLOCATION", 34: "UVM_FREE", 35: "UVM_MEM_MAP",
    37: "UVM_REGISTER_GPU", 38: "UVM_UNREGISTER_GPU", 39: "UVM_PAGEABLE_MEM_ACCESS",
    55: "UVM_DISABLE_SYSTEM_WIDE_ATOMICS", 73: "UVM_CREATE_EXTERNAL_RANGE",
    75: "UVM_MM_INITIALIZE",
}

# ctrl2080*.h: NVOS54_PARAMETERS.cmd values seen on GP107 during init
CTRL2080 = {
    0x20803801: "NV2080_CTRL_CMD_GRMGR_GET_GR_FS_INFO",
    0x20801346: "NV2080_CTRL_CMD_FB_GET_FS_INFO",
    0x00000101: "NV0000_CTRL_CMD_SYSTEM_GET_BUILD_VERSION",
}

# Дві форми, які реально трапляються в джерелах і логах:
#   _IOC(dir, type, nr, size)          - повна форма, напрямок явним аргументом
#   _IOWR(type, nr, size)              - форма з linux/ioctl.h, напрямок у суфіксі
# Друга довго не розпізнавалась зовсім, тому `_IOWR(0x46, 0xc8, 0x900)` з лога
# давав "no ioctl request found" замість декодування.
IOC_RE = re.compile(
    r"_IOC\(\s*(?P<dir>[^,]+),\s*(?P<type>0x[0-9a-fA-F]+),\s*"
    r"(?P<nr>0x[0-9a-fA-F]+),\s*(?P<size>0x[0-9a-fA-F]+)\s*\)"
)
IOC_SUFFIX_RE = re.compile(
    r"_IO(?P<dirs>[RW]*)\s*\(\s*(?P<type>0x[0-9a-fA-F]+)\s*,\s*"
    r"(?P<nr>0x[0-9a-fA-F]+)\s*,\s*(?P<size>0x[0-9a-fA-F]+)\s*\)"
)


def dir_bits_from_suffix(dirs: str) -> int:
    """`_IOWR` -> 3, `_IOW` -> 1, `_IOR` -> 2, `_IO` -> 0."""
    flags = set(dirs.upper())
    return (1 if "W" in flags else 0) | (2 if "R" in flags else 0)
HEX_RE = re.compile(r"0x[0-9a-fA-F]+")


def dir_bits(text: str) -> int:
    t = " ".join(text.replace("|", " ").split()).upper()
    if "READ" in t and "WRITE" in t:
        return 3
    if "READ" in t:
        return 2
    if "WRITE" in t:
        return 1
    return 0


def decode(req: int) -> tuple[str, str, int, int, int, str]:
    d = (req >> 30) & 3
    size = (req >> 16) & 0x1FFF
    typ = (req >> 8) & 0xFF
    nr = req & 0xFF
    if typ == 0x46:
        name = NV_LEGACY.get(nr) or NV_RM_ESCAPE.get(nr, "?")
        scope = "RM"
    elif typ == 0 and (0x30000000 <= req <= 0x300007FF or nr < 100):
        name = UVM.get(nr, "?")
        scope = "UVM"
    else:
        name = "?"
        scope = "other"
    dname = {0: "NONE", 1: "WRITE", 2: "READ", 3: "RD/WR"}[d]
    return scope, dname, typ, nr, size, name


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("values", nargs="*", help="hex ioctl requests or strace lines")
    args = ap.parse_args()

    lines = args.values or [ln.strip() for ln in sys.stdin if ln.strip()]
    found = False
    for line in lines:
        m = IOC_RE.search(line)
        if m:
            req = ((dir_bits(m.group("dir")) << 30)
                   | (int(m.group("size"), 16) << 16)
                   | (int(m.group("type"), 16) << 8)
                   | int(m.group("nr"), 16))
        elif (m := IOC_SUFFIX_RE.search(line)) is not None:
            req = ((dir_bits_from_suffix(m.group("dirs")) << 30)
                   | (int(m.group("size"), 16) << 16)
                   | (int(m.group("type"), 16) << 8)
                   | int(m.group("nr"), 16))
        else:
            cands = [int(x, 16) for x in HEX_RE.findall(line) if len(x) >= 8]
            if not cands:
                continue
            req = cands[0]

        if 0x10000000 <= req <= 0xFFFFFFFF and req not in CTRL2080:
            scope, dname, typ, nr, size, name = decode(req)
            print(f"{req:#010x}  {scope:4s} {dname:5s} magic={typ:#04x} "
                  f"nr={nr:#04x} size={size:5d}  {name}")
        elif req in CTRL2080:
            print(f"{req:#010x}  RMCTRL cmd             {CTRL2080[req]}")
        found = True

    if not found:
        print("no ioctl request found", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
