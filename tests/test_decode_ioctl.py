#!/usr/bin/env python3
"""Tests for scripts/decode_ioctl.py.

The decoder is the tool a local agent uses to read `strace -e ioctl` output, so a
wrong mapping does not crash - it quietly mislabels a request and the trace is
read wrongly. These tests pin the Linux `_IOC` bit layout and the handful of
names that the GP107 init path is known to hit.

Ground truth for the layout comes from the kernel macros, not from the decoder:

    _IOC_NRBITS 8, _IOC_TYPEBITS 8, _IOC_SIZEBITS 14, _IOC_DIRBITS 2
    _IOC(dir,type,nr,size) = (dir << 30) | (type << 8) | (nr) | (size << 16)
    _IOC_READ = 2, _IOC_WRITE = 1

So the expected values below are computed here, independently, and compared with
what the decoder reports.
"""
from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import decode_ioctl as di  # noqa: E402

IOC_READ = 2
IOC_WRITE = 1
NV_IOCTL_TYPE = 0x46  # 'F'
UVM_IOCTL_TYPE = 0x00


def ioc(direction: int, type_: int, nr: int, size: int) -> int:
    """Independent implementation of the kernel's _IOC macro."""
    return ((direction & 0x3) << 30) | ((type_ & 0xFF) << 8) | (nr & 0xFF) | ((size & 0x3FFF) << 16)


class UpstreamPinTest(unittest.TestCase):
    """Names must match NVIDIA's published headers, not what a filename suggests.

    0x00000101 was labelled NV0000_CTRL_CMD_CLIENT_GET_CAPABILITIES because the
    map cited ctrl0000client.h. Upstream, 0x101 is
    NV0000_CTRL_CMD_SYSTEM_GET_BUILD_VERSION (ctrl0000system.h:106), and
    ctrl0000client.h defines CLIENT_GET_ADDR_SPACE_TYPE = 0xd01 instead. The
    symbol CLIENT_GET_CAPABILITIES does not exist anywhere in
    NVIDIA/open-gpu-kernel-modules.
    """

    def test_build_version_command_is_named_correctly(self) -> None:
        # Control commands are resolved from CTRL2080 by the CLI, not by
        # decode(), which only handles the RM and UVM paths.
        self.assertEqual(di.CTRL2080[0x00000101], "NV0000_CTRL_CMD_SYSTEM_GET_BUILD_VERSION")

    def test_cli_prints_the_corrected_name(self) -> None:
        result = subprocess.run([sys.executable, str(ROOT / "scripts" / "decode_ioctl.py"), "0x00000101"],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("NV0000_CTRL_CMD_SYSTEM_GET_BUILD_VERSION", result.stdout)

    def test_the_invented_name_is_not_in_the_tables(self) -> None:
        names = set(di.CTRL2080.values()) | set(di.NV_LEGACY.values()) | set(di.UVM.values())
        self.assertNotIn("NV0000_CTRL_CMD_CLIENT_GET_CAPABILITIES", names)


class FieldDecodingTest(unittest.TestCase):
    def test_card_info_fields_come_from_the_kernel_layout(self) -> None:
        req = ioc(IOC_READ | IOC_WRITE, NV_IOCTL_TYPE, 200, 2304)
        scope, dname, typ, nr, size, name = di.decode(req)
        self.assertEqual(scope, "RM")
        self.assertEqual(dname, "RD/WR")
        self.assertEqual(typ, NV_IOCTL_TYPE)
        self.assertEqual(nr, 200)
        self.assertEqual(size, 2304)
        self.assertEqual(name, "NV_ESC_CARD_INFO")

    def test_register_fd_is_decoded_by_number_not_by_luck(self) -> None:
        req = ioc(IOC_READ, NV_IOCTL_TYPE, 201, 8)
        _, dname, _, nr, _, name = di.decode(req)
        self.assertEqual((nr, name), (201, "NV_ESC_REGISTER_FD"))
        self.assertEqual(dname, "READ")

    def test_rm_escape_names(self) -> None:
        for nr, expected in ((0x27, "NV_ESC_RM_ALLOC_MEMORY"),
                             (0x29, "NV_ESC_RM_FREE"),
                             (0x2A, "NV_ESC_RM_CONTROL"),
                             (0x2B, "NV_ESC_RM_ALLOC")):
            with self.subTest(nr=hex(nr)):
                req = ioc(IOC_READ | IOC_WRITE, NV_IOCTL_TYPE, nr, 32)
                self.assertEqual(di.decode(req)[5], expected)

    def test_uvm_requests_use_type_zero(self) -> None:
        req = ioc(IOC_WRITE, UVM_IOCTL_TYPE, 37, 32)
        scope, dname, typ, nr, _, name = di.decode(req)
        self.assertEqual((scope, typ, nr, name), ("UVM", 0, 37, "UVM_REGISTER_GPU"))
        self.assertEqual(dname, "WRITE")

    def test_unknown_number_is_not_given_a_name(self) -> None:
        req = ioc(IOC_READ, NV_IOCTL_TYPE, 0xFE, 4)
        self.assertEqual(di.decode(req)[5], "?")

    def test_unknown_magic_is_scoped_other(self) -> None:
        req = ioc(IOC_READ, 0x7A, 5, 4)
        scope, _, typ, _, _, name = di.decode(req)
        self.assertEqual(scope, "other")
        self.assertEqual(typ, 0x7A)
        self.assertEqual(name, "?")


class CommandLineTest(unittest.TestCase):
    def test_exits_nonzero_when_nothing_decodes(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "decode_ioctl.py")],
            input="hello world\n", capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("no ioctl request found", result.stderr)

    def test_decodes_hex_argument(self) -> None:
        req = ioc(IOC_READ | IOC_WRITE, NV_IOCTL_TYPE, 200, 2304)
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "decode_ioctl.py"), hex(req)],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("NV_ESC_CARD_INFO", result.stdout)
        self.assertIn("magic=0x46", result.stdout)

    def test_decodes_strace_line(self) -> None:
        req = ioc(IOC_READ | IOC_WRITE, NV_IOCTL_TYPE, 0x2A, 32)
        line = f'ioctl(3, {req:#x}, 0x7ffd12345678) = 0'
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "decode_ioctl.py")],
            input=line + "\n", capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("NV_ESC_RM_CONTROL", result.stdout)

    def test_reconstructs_request_from_ioc_macro_text(self) -> None:
        line = "ioctl(fd, _IOWR(0x46, 0xc8, 0x900), arg)"
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "decode_ioctl.py")],
            input=line + "\n", capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("NV_ESC_CARD_INFO", result.stdout)
        self.assertIn("nr=0xc8", result.stdout)

    def test_ctrl_command_ids_are_reported_as_commands(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "decode_ioctl.py"), "0x20803801"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RMCTRL", result.stdout)
        self.assertIn("NV2080_CTRL_CMD_GRMGR_GET_GR_FS_INFO", result.stdout)


if __name__ == "__main__":
    unittest.main()
