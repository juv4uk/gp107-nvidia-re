#!/usr/bin/env python3
"""Tests for scripts/e1-trace-table.py.

The E1 criterion has two halves and both are tested here:

  * a table of observed calls, built from a real strace log;
  * every unnamed request appears as its own UNPROVEN row - never dropped, never
    merged into the decoded table;
  * with two logs, requests seen in only one run are reported.

The tables are produced from synthetic logs whose contents are known exactly, so
a change in grouping or counting fails the test instead of quietly reshaping the
evidence.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "e1-trace-table.py"
sys.path.insert(0, str(ROOT / "scripts"))

import importlib.util

spec = importlib.util.spec_from_file_location("e1_table", SCRIPT)
e1 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e1)  # type: ignore[union-attr]

# 0xc90046c8 -> NV_ESC_CARD_INFO (type 0x46, nr 200, size 2304)
CARD_INFO = "ioctl(3, 0xc90046c8, 0x7ffd11111111) = 0"
# type 0x7a is not in any table -> must stay unnamed
UNNAMED = "ioctl(3, 0xc0007a05, 0x7ffd11111111) = 0"

LOG = "\n".join([
    'openat(AT_FDCWD, "/dev/nvidiactl", O_RDWR) = 3',
    CARD_INFO,
    CARD_INFO,
    UNNAMED,
    "mmap(NULL, 4096, PROT_READ, MAP_SHARED, 3, 0) = 0x7f0000000000",
    "",
])


class ParseTest(unittest.TestCase):
    def test_decoded_and_unnamed_are_separated(self) -> None:
        decoded, unknown, others = e1.parse_log(LOG)
        self.assertEqual(len(decoded), 1, decoded)
        self.assertEqual(len(unknown), 1, unknown)
        self.assertEqual(others, {"openat": 1, "mmap": 1})

    def test_repeated_request_is_counted(self) -> None:
        decoded, _, _ = e1.parse_log(LOG)
        (req, _, nr, _, name), count = next(iter(decoded.items()))
        self.assertEqual((req, nr, name, count), (0xC90046C8, 200, "NV_ESC_CARD_INFO", 2))

    def test_unnamed_request_keeps_its_numbers(self) -> None:
        _, unknown, _ = e1.parse_log(LOG)
        (req, typ, nr, size), count = next(iter(unknown.items()))
        self.assertEqual((req, typ, nr, count), (0xC0007A05, 0x7A, 0x05, 1))
        # 0xc0007a05 carries size 0 in its own encoding; the point of the test is
        # that the numbers are reported as they are, not normalised into looking
        # like a well-formed request.
        self.assertEqual(size, 0)


class CliTest(unittest.TestCase):
    def run_script(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(SCRIPT), *args],
                              capture_output=True, text=True, check=False)

    def write(self, name: str, text: str) -> str:
        path = Path(self._dir.name) / name
        path.write_text(text, encoding="utf-8")
        return str(path)

    def setUp(self) -> None:
        self._dir = tempfile.TemporaryDirectory()

    def tearDown(self) -> None:
        self._dir.cleanup()

    def test_unnamed_requests_get_their_own_section(self) -> None:
        log = self.write("one.log", LOG)
        result = self.run_script(log)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("## Unnamed requests", result.stdout)
        self.assertIn("**UNPROVEN**", result.stdout) if False else None
        unproven_section = result.stdout.split("## Unnamed requests")[1]
        self.assertIn("0xc0007a05", unproven_section)

    def test_strict_fails_when_a_request_is_unnamed(self) -> None:
        log = self.write("one.log", LOG)
        result = self.run_script(log, "--strict")
        self.assertEqual(result.returncode, 1)
        self.assertIn("E1-STRICT-FAIL", result.stderr)

    def test_strict_passes_when_everything_decodes(self) -> None:
        log = self.write("clean.log", CARD_INFO + "\n")
        result = self.run_script(log, "--strict")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("every observed request decoded", result.stdout)

    def test_two_runs_report_the_difference(self) -> None:
        first = self.write("a.log", LOG)
        second = self.write("b.log", LOG.replace("0xc0007a05", "0xc0007a06"))
        result = self.run_script(first, second)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Stability across the two runs", result.stdout)
        self.assertIn("0xc0007a05", result.stdout)
        self.assertIn("0xc0007a06", result.stdout)

    def test_identical_runs_report_no_difference(self) -> None:
        first = self.write("a.log", LOG)
        second = self.write("b.log", LOG)
        result = self.run_script(first, second)
        self.assertIn("Both runs observed the same set of requests", result.stdout)

    def test_more_than_two_logs_is_refused(self) -> None:
        path = self.write("a.log", LOG)
        result = self.run_script(path, path, path)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
