#!/usr/bin/env python3
"""Tests for scripts/check-ioctl-map-drift.py.

The gate exists because the two files drifted in both directions at once: the
decoder knew three requests the map never mentioned, and the map documented one
request the decoder could not name. Each direction is pinned here.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import check_ioctl_map_drift as drift  # noqa: E402

HEADER = "# map\n\n| 200 | `NV_ESC_CARD_INFO` | `0xc8` |\n"


class DriftTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "docs").mkdir(parents=True)
        self.map = self.root / "docs" / "ioctl-map.md"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write_map(self, text: str) -> None:
        self.map.write_text(text, encoding="utf-8")

    def test_repository_is_in_sync(self) -> None:
        self.assertEqual(drift.check(ROOT), [])

    def test_decoder_name_missing_from_map_is_reported(self) -> None:
        # Only one of the decoder's names is documented here.
        self.write_map(HEADER)
        problems = drift.check(self.root)
        self.assertTrue(problems)
        self.assertTrue(all("absent from docs/ioctl-map.md" in p for p in problems))
        self.assertFalse(any("unknown to the decoder" in p for p in problems))

    def test_documented_name_unknown_to_decoder_is_reported(self) -> None:
        names = "\n".join(f"| {i} | `{n}` | `0x{i:02x}` |" for i, n in enumerate(sorted(drift.decoder_names())))
        self.write_map(HEADER + names + "\n| 99 | `NV_ESC_NOT_A_REAL_NAME` | `0x63` |\n")
        problems = drift.check(self.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("NV_ESC_NOT_A_REAL_NAME", problems[0])
        self.assertIn("unknown to the decoder", problems[0])

    def test_full_documentation_passes(self) -> None:
        names = "\n".join(f"| {i} | `{n}` | `0x{i:02x}` |" for i, n in enumerate(sorted(drift.decoder_names())))
        self.write_map(HEADER + names + "\n")
        self.assertEqual(drift.check(self.root), [])


if __name__ == "__main__":
    unittest.main()
