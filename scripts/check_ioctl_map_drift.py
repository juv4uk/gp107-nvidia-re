#!/usr/bin/env python3
"""The decoder and docs/ioctl-map.md must describe the same set of names.

They are two views of one fact: the decoder is what a trace is read with, the map
is what a person searches. Drift in either direction is silent and expensive:

  * a name the decoder knows but the map does not - the map stops being the index
    people actually consult;
  * a name the map documents but the decoder does not - the documented request
    shows up in a trace as `?` and lands in the UNPROVEN table, even though the
    project already knows what it is.

Both directions are errors here. There is no allowlist: a name that cannot be
given a number does not belong in either file yet.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import decode_ioctl as di  # noqa: E402

MAP = ROOT / "docs" / "ioctl-map.md"
NAME_RE = re.compile(r"\b(NV_ESC_[A-Z0-9_]+|UVM_[A-Z0-9_]+)\b")


def decoder_names() -> set[str]:
    return set(di.NV_LEGACY.values()) | set(di.NV_RM_ESCAPE.values()) | set(di.UVM.values())


def map_names(text: str) -> set[str]:
    return set(NAME_RE.findall(text))


def check(root: Path = ROOT) -> list[str]:
    text = (root / "docs" / "ioctl-map.md").read_text(encoding="utf-8")
    decoder = decoder_names()
    documented = map_names(text)
    problems = []
    for name in sorted(decoder - documented):
        problems.append(f"{name}: known to the decoder, absent from docs/ioctl-map.md")
    for name in sorted(documented - decoder):
        problems.append(f"{name}: documented in docs/ioctl-map.md, unknown to the decoder")
    return problems


def main() -> int:
    problems = check()
    if problems:
        for problem in problems:
            print(f"IOCTL-MAP-DRIFT: {problem}", file=sys.stderr)
        print("IOCTL-MAP-DRIFT-FAIL: the decoder and the map must name the same requests",
              file=sys.stderr)
        return 1
    print(f"IOCTL-MAP-DRIFT-PASS: {len(decoder_names())} names agree in decoder and docs/ioctl-map.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
