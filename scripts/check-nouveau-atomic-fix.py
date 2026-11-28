#!/usr/bin/env python3
"""Read-only check for the GP107 Nouveau atomic-modeset fix in a kernel tree.

The fix is public upstream Linux commit
ed7fb901fce31588bd12ab95adc36ebcb51bc8ea (Dave Airlie, 2026-11-11).
It is relevant to the GP107 regression described in docs/48 section 3.2.

This script never touches hardware, firmware, RM ioctls or proprietary
binaries.  It only reads a kernel source tree / git repository that the
caller explicitly points at.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

FIX_COMMIT = "ed7fb901fce31588bd12ab95adc36ebcb51bc8ea"
SOURCE_REL = Path("drivers/gpu/drm/nouveau/nouveau_display.c")
MARKERS = (
    "nouveau_mode_config_funcs_atomic",
    "drm_drv_uses_atomic_modeset(dev)",
)


def run_git(repo: Path, *args: str) -> tuple[int, str, str]:
    try:
        p = subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return 127, "", "git not found on PATH"
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def check_tree(kernel_dir: Path, commit: str) -> dict:
    result: dict = {
        "kernel_dir": str(kernel_dir),
        "fix_commit": commit,
        "source_file": str(SOURCE_REL),
        "git_repository": False,
        "head": None,
        "commit_is_ancestor": None,
        "markers_present": {},
        "status": "UNKNOWN",
        "next_step": None,
    }

    source = kernel_dir / SOURCE_REL
    if source.is_file():
        text = source.read_text(encoding="utf-8", errors="replace")
        for marker in MARKERS:
            result["markers_present"][marker] = marker in text
    else:
        result["next_step"] = f"source file not found: {source}"
        return result

    code, out, _err = run_git(kernel_dir, "rev-parse", "--is-inside-work-tree")
    if code == 0 and out == "true":
        result["git_repository"] = True
        _c, head, _e = run_git(kernel_dir, "rev-parse", "HEAD")
        result["head"] = head or None
        anc, _o, _e = run_git(kernel_dir, "merge-base", "--is-ancestor", commit, "HEAD")
        result["commit_is_ancestor"] = anc == 0

    all_markers = all(result["markers_present"].values())
    if result["commit_is_ancestor"] is True and all_markers:
        result["status"] = "FIX_PRESENT"
    elif result["commit_is_ancestor"] is False or not all_markers:
        result["status"] = "FIX_ABSENT_OR_PARTIAL"
        result["next_step"] = (
            "Check the distro kernel changelog or use a kernel that contains "
            f"{commit}. As a temporary mitigation only, nouveau.atomic=0 "
            "disables the atomic path; do not change boot configuration "
            "without the owner's explicit approval."
        )
    else:
        result["status"] = "SOURCE_MARKERS_ONLY"
        result["next_step"] = (
            "Markers found but git ancestry could not be verified; provide a "
            "git checkout or a kernel version string."
        )
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--kernel-dir", type=Path, default=None,
                    help="path to a Linux kernel source tree")
    ap.add_argument("--commit", default=FIX_COMMIT,
                    help="upstream fix commit to test as ancestor")
    args = ap.parse_args()

    if args.kernel_dir is None:
        print(json.dumps({
            "status": "NEED_INPUT",
            "fix_commit": args.commit,
            "next_step": (
                "Run 'uname -r' on the target Linux system and pass a kernel "
                "source tree with --kernel-dir, for example: "
                "python3 scripts/check-nouveau-atomic-fix.py "
                "--kernel-dir /usr/src/linux-headers-$(uname -r)"
            ),
        }, indent=2, ensure_ascii=False))
        return 2

    out = check_tree(args.kernel_dir, args.commit)
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0 if out["status"] in ("FIX_PRESENT", "FIX_ABSENT_OR_PARTIAL") else 1


if __name__ == "__main__":
    raise SystemExit(main())
