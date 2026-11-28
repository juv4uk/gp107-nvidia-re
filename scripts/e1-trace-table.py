#!/usr/bin/env python3
"""Turn raw strace output into the E1 table (docs/07, docs/46).

E1 asks for "a table of observed calls from two independent runs, and a negative:
every unknown request must appear as its own UNPROVEN row". This script is that
step, so nobody has to build the table by hand and quietly drop what did not
decode.

Input is `strace -f -yy -e trace=ioctl,mmap,openat` output, one or two files.
Output is Markdown on stdout:

  * a table of decoded ioctl requests, with counts;
  * a separate table of requests the decoder could not name - never merged into
    the first one, never dropped;
  * when two runs are given, a stability section listing requests present in
    only one of them.

Exit status: 0 always, unless `--strict` is passed, in which case an unnamed
request fails the run - that is the negative half of the E1 criterion.

Read-only: the script only reads the logs it is given.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import decode_ioctl as di  # noqa: E402

IOCTL_LINE = re.compile(r"ioctl\(\s*(?P<fd>[^,]+),\s*(?P<req>0x[0-9a-fA-F]+)")
SYSCALL = re.compile(r"\b(?P<name>ioctl|mmap|openat)\(")
REQ_HEX = re.compile(r"0x[0-9a-fA-F]{8,}")


def parse_log(text: str) -> tuple[Counter, Counter, Counter]:
    """Return (decoded requests, unknown requests, other syscalls)."""
    decoded: Counter = Counter()
    unknown: Counter = Counter()
    others: Counter = Counter()

    for line in text.splitlines():
        m = IOCTL_LINE.search(line)
        if m is not None:
            req = int(m.group("req"), 16)
            _, _, typ, nr, size, name = di.decode(req)
            if name == "?":
                unknown[(req, typ, nr, size)] += 1
            else:
                decoded[(req, typ, nr, size, name)] += 1
            continue
        s = SYSCALL.search(line)
        if s is not None and s.group("name") != "ioctl":
            others[s.group("name")] += 1
        elif s is None:
            # A line with a bare request number still belongs in the table: the
            # decoder may have been fed a fragment rather than a full call.
            for hexval in REQ_HEX.findall(line):
                req = int(hexval, 16)
                if not 0x10000000 <= req <= 0xFFFFFFFF:
                    continue
                _, _, typ, nr, size, name = di.decode(req)
                if name == "?":
                    unknown[(req, typ, nr, size)] += 1
                else:
                    decoded[(req, typ, nr, size, name)] += 1
    return decoded, unknown, others


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("logs", nargs="+", help="strace log file(s); one or two")
    ap.add_argument("--strict", action="store_true",
                    help="fail if any request could not be named (E1 negative)")
    args = ap.parse_args()

    if len(args.logs) > 2:
        print("E1: give one log, or two for the stability comparison", file=sys.stderr)
        return 2

    parsed = []
    for path in args.logs:
        text = Path(path).read_text(encoding="utf-8", errors="replace")
        parsed.append(parse_log(text))

    decoded, unknown, others = parsed[0]

    print("## E1 — observed calls\n")
    if others:
        print("| syscall | count |")
        print("| --- | --- |")
        for name, count in others.most_common():
            print(f"| `{name}` | {count} |")
        print()

    print("## Decoded ioctl requests\n")
    rows = [(req, typ, nr, size, name, n) for (req, typ, nr, size, name), n in decoded.most_common()]
    print("| request | name | dir | magic | nr | size | count |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    for req, typ, nr, size, name, n in rows:
        _, dname, _, _, _, _ = di.decode(req)
        print(f"| `{req:#010x}` | {name} | {dname} | {typ:#04x} | {nr:#04x} | {size} | {n} |")
    print()

    print("## Unnamed requests — UNPROVEN\n")
    if unknown:
        print("These requests were observed but the decoder has no name for them.")
        print("They are listed separately on purpose: an unnamed request is not an")
        print("absent one.\n")
        print("| request | dir | magic | nr | size | count |")
        print("| --- | --- | --- | --- | --- | --- |")
        for (req, typ, nr, size), n in unknown.most_common():
            dname = {0: "NONE", 1: "WRITE", 2: "READ", 3: "RD/WR"}[(req >> 30) & 3]
            print(f"| `{req:#010x}` | {dname} | {typ:#04x} | {nr:#04x} | {size} | {n} |")
    else:
        print("None: every observed request decoded.")
    print()

    if len(parsed) == 2:
        first = {row[:-1] for row in decoded} | set(unknown)
        second = {row[:-1] for row in parsed[1][0]} | set(parsed[1][1])
        only_first = first - second
        only_second = second - first
        print("## Stability across the two runs\n")
        if not only_first and not only_second:
            print("Both runs observed the same set of requests.")
        else:
            for label, items in (("only in run 1", only_first), ("only in run 2", only_second)):
                for item in sorted(items):
                    req = item[0]
                    print(f"- `{req:#010x}` {label}")
        print()

    if args.strict and unknown:
        print(f"E1-STRICT-FAIL: {len(unknown)} unnamed request(s) — see UNPROVEN table", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
