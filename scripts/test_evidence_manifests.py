#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-Volnist
"""Regression tests for artifact-scoped historical evidence exceptions."""

from __future__ import annotations

import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from check_evidence_manifests import (  # noqa: E402
    ManifestError,
    check_repository,
    parse_exceptions,
    verify_manifest,
)


class EvidenceManifestExceptionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.directory = self.root / "experiments" / "capture" / "artifacts-v4"
        self.directory.mkdir(parents=True)
        self.manifest = self.directory / "99-manifest.txt"
        self.manifest_rel = self.manifest.relative_to(self.root).as_posix()
        self.records: list[tuple[str, str, str]] = []
        for index in range(1, 8):
            name = f"{index:02d}-artifact.txt"
            data = f"capture-{index}".encode()
            (self.directory / name).write_bytes(data)
            self.records.append((hashlib.sha256(data).hexdigest(), f"/original/host/{name}", name))
        missing_data = b"historical run log"
        self.missing_sha = hashlib.sha256(missing_data).hexdigest()
        self.missing_path = "/original/host/03-run.log"
        self.write_manifest()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_manifest(self) -> None:
        rows = ["# test evidence manifest", ""]
        rows.extend(f"{digest}  {recorded}" for digest, recorded, _ in self.records[:2])
        rows.append(f"{self.missing_sha}  {self.missing_path}")
        rows.extend(f"{digest}  {recorded}" for digest, recorded, _ in self.records[2:])
        self.manifest.write_text("\n".join(rows) + "\n", encoding="utf-8")

    def write_exceptions(self, rows: list[str] | None = None) -> dict:
        exception_file = self.root / "scripts" / "manifest-exceptions.txt"
        exception_file.parent.mkdir(parents=True, exist_ok=True)
        if rows is None:
            reason = "historical 03-run.log was not committed"
            rows = [f"{self.manifest_rel}\t{self.missing_path}\t{self.missing_sha}\t{reason}"]
        exception_file.write_text(
            "# manifest<TAB>artifact<TAB>sha256<TAB>reason\n" + "\n".join(rows) + "\n",
            encoding="utf-8",
        )
        return parse_exceptions(self.root, exception_file)

    def test_only_named_missing_artifact_is_accepted_and_all_others_hash(self) -> None:
        exceptions = self.write_exceptions()
        result, used = verify_manifest(self.root, self.manifest, exceptions)
        self.assertEqual(result.verified, 7)
        self.assertEqual(result.known_missing, (self.missing_path,))
        self.assertEqual(len(used), 1)

    def test_manifest_directory_path_wins_over_parent_basename(self) -> None:
        local = self.directory / "vk_min.h"
        parent = self.directory.parent / "vk_min.h"
        local.write_bytes(b"local historical snapshot")
        parent.write_bytes(b"different parent file")
        local_sha = hashlib.sha256(local.read_bytes()).hexdigest()
        self.manifest.write_text(
            "# static snapshot\n" + f"{local_sha}  vk_min.h\n",
            encoding="utf-8",
        )
        result, used = verify_manifest(self.root, self.manifest, {})
        self.assertEqual(result.verified, 1)
        self.assertEqual(result.known_missing, ())
        self.assertEqual(used, set())

    def test_explicit_external_bundle_is_verified_inside_its_own_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            bundle = Path(temporary) / "bundle"
            bundle.mkdir()
            artifact = bundle / "artifact.txt"
            artifact.write_bytes(b"external evidence")
            digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
            manifest = bundle / "99-manifest.txt"
            manifest.write_text(f"{digest}  artifact.txt\n", encoding="utf-8")

            result = check_repository(ROOT, [manifest])

        self.assertEqual(result, (1, 0, 0))

    def test_external_bundle_rejects_symlink_to_file_outside_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            bundle = base / "bundle"
            outside = base / "private" / "secret.txt"
            bundle.mkdir()
            outside.parent.mkdir()
            outside.write_bytes(b"must not be read as bundle evidence")
            link = bundle / "artifact.txt"
            link.symlink_to(outside)
            digest = hashlib.sha256(outside.read_bytes()).hexdigest()
            manifest = bundle / "99-manifest.txt"
            manifest.write_text(f"{digest}  artifact.txt\n", encoding="utf-8")

            with self.assertRaisesRegex(ManifestError, "escapes verification root"):
                check_repository(ROOT, [manifest])

    def test_external_bundle_rejects_parent_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            bundle = base / "bundle"
            bundle.mkdir()
            outside = base / "outside.txt"
            outside.write_bytes(b"must not be read")
            digest = hashlib.sha256(outside.read_bytes()).hexdigest()
            manifest = bundle / "99-manifest.txt"
            manifest.write_text(f"{digest}  ../outside.txt\n", encoding="utf-8")

            with self.assertRaisesRegex(ManifestError, "traverses its directory"):
                check_repository(ROOT, [manifest])

    def test_multiple_fallback_candidates_are_ambiguous(self) -> None:
        recorded = "nested/recorded.bin"
        parent_fallback = self.directory.parent / recorded
        basename_fallback = self.directory / "recorded.bin"
        parent_fallback.parent.mkdir(parents=True, exist_ok=True)
        parent_fallback.write_bytes(b"parent fallback")
        basename_fallback.write_bytes(b"basename fallback")
        digest = hashlib.sha256(parent_fallback.read_bytes()).hexdigest()
        self.manifest.write_text(f"{digest}  {recorded}\n", encoding="utf-8")
        with self.assertRaisesRegex(ManifestError, "ambiguous fallback"):
            verify_manifest(self.root, self.manifest, {})

    def test_single_fallback_candidate_is_verified(self) -> None:
        recorded = "nested/recorded.bin"
        parent_fallback = self.directory.parent / recorded
        parent_fallback.parent.mkdir(parents=True, exist_ok=True)
        parent_fallback.write_bytes(b"only fallback")
        digest = hashlib.sha256(parent_fallback.read_bytes()).hexdigest()
        self.manifest.write_text(f"{digest}  {recorded}\n", encoding="utf-8")
        result, used = verify_manifest(self.root, self.manifest, {})
        self.assertEqual(result.verified, 1)
        self.assertEqual(result.known_missing, ())
        self.assertEqual(used, set())

    def test_missing_artifact_without_exception_fails(self) -> None:
        with self.assertRaisesRegex(ManifestError, "missing artifact"):
            verify_manifest(self.root, self.manifest, {})

    def test_second_missing_artifact_fails_even_with_known_exception(self) -> None:
        (self.directory / "02-artifact.txt").unlink()
        exceptions = self.write_exceptions()
        with self.assertRaisesRegex(ManifestError, "missing artifact"):
            verify_manifest(self.root, self.manifest, exceptions)

    def test_unrelated_hash_mismatch_fails_with_known_exception(self) -> None:
        (self.directory / "04-artifact.txt").write_text("tampered", encoding="utf-8")
        exceptions = self.write_exceptions()
        with self.assertRaisesRegex(ManifestError, "SHA-256 mismatch"):
            verify_manifest(self.root, self.manifest, exceptions)

    def test_exception_for_wrong_artifact_path_does_not_match(self) -> None:
        exceptions = self.write_exceptions([
            f"{self.manifest_rel}\t/original/host/other.log\t{self.missing_sha}\twrong path"
        ])
        with self.assertRaisesRegex(ManifestError, "missing artifact"):
            verify_manifest(self.root, self.manifest, exceptions)

    def test_exception_with_wrong_sha_fails(self) -> None:
        exceptions = self.write_exceptions([
            f"{self.manifest_rel}\t{self.missing_path}\t{'0' * 64}\twrong digest"
        ])
        with self.assertRaisesRegex(ManifestError, "exception SHA"):
            verify_manifest(self.root, self.manifest, exceptions)

    def test_duplicate_exception_fails(self) -> None:
        row = f"{self.manifest_rel}\t{self.missing_path}\t{self.missing_sha}\tduplicate"
        with self.assertRaisesRegex(ManifestError, "duplicate exception"):
            self.write_exceptions([row, row])

    def test_malformed_exception_fails(self) -> None:
        with self.assertRaisesRegex(ManifestError, "exactly four"):
            self.write_exceptions([f"{self.manifest_rel}\t{self.missing_path}\t{self.missing_sha}"])

    def test_restoring_exact_file_makes_exception_stale(self) -> None:
        (self.directory / "03-run.log").write_bytes(b"historical run log")
        exceptions = self.write_exceptions()
        with self.assertRaisesRegex(ManifestError, "stale exception"):
            verify_manifest(self.root, self.manifest, exceptions)

    def test_restoring_file_with_wrong_bytes_fails_digest(self) -> None:
        (self.directory / "03-run.log").write_bytes(b"replacement log")
        exceptions = self.write_exceptions()
        with self.assertRaisesRegex(ManifestError, "SHA-256 mismatch"):
            verify_manifest(self.root, self.manifest, exceptions)


if __name__ == "__main__":
    unittest.main()
