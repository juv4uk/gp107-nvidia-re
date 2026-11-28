#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-Volnist
"""Verify recorded evidence manifests with narrowly scoped, fail-closed exceptions."""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
MANIFEST_GLOB = "*99-manifest.txt"
SELF_MANIFEST_NAME = "99-manifest.txt"


class ManifestError(RuntimeError):
    """An evidence manifest or its exception register is invalid."""


@dataclass(frozen=True)
class Entry:
    sha256: str
    path: str


@dataclass(frozen=True)
class ExceptionEntry:
    manifest: str
    artifact: str
    sha256: str
    reason: str

    @property
    def key(self) -> tuple[str, str]:
        return (self.manifest, self.artifact)


@dataclass(frozen=True)
class ManifestResult:
    manifest: str
    verified: int
    known_missing: tuple[str, ...] = ()


def repo_relative(root: Path, path: Path) -> str:
    """Return a canonical repository-relative POSIX path or fail closed."""
    resolved = path.resolve()
    try:
        return resolved.relative_to(root.resolve()).as_posix()
    except ValueError as exc:
        raise ManifestError(f"path escapes repository root: {path}") from exc


def parse_manifest(path: Path) -> list[Entry]:
    entries: list[Entry] = []
    seen_paths: set[str] = set()
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ManifestError(f"cannot read manifest {path}: {exc}") from exc

    for line_number, line in enumerate(lines, start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fields = stripped.split(maxsplit=1)
        if not SHA256_RE.fullmatch(fields[0]):
            continue
        if len(fields) != 2 or not fields[1].strip():
            raise ManifestError(f"{path}:{line_number}: SHA-256 entry has no artifact path")
        artifact = fields[1].strip()
        if artifact in seen_paths:
            raise ManifestError(f"{path}:{line_number}: duplicate artifact path {artifact!r}")
        seen_paths.add(artifact)
        entries.append(Entry(fields[0], artifact))

    if not entries:
        raise ManifestError(f"manifest contains no SHA-256 entries: {path}")
    return entries


def parse_exceptions(root: Path, exceptions_file: Path) -> dict[tuple[str, str], ExceptionEntry]:
    """Read manifest<TAB>artifact<TAB>sha256<TAB>reason rows."""
    if not exceptions_file.is_file():
        return {}
    result: dict[tuple[str, str], ExceptionEntry] = {}
    try:
        lines = exceptions_file.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ManifestError(f"cannot read exception register: {exc}") from exc

    for line_number, line in enumerate(lines, start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 4:
            raise ManifestError(
                f"{exceptions_file}:{line_number}: expected exactly four tab-separated fields"
            )
        manifest, artifact, digest, reason = fields
        if not manifest or not artifact or not reason.strip():
            raise ManifestError(f"{exceptions_file}:{line_number}: empty exception field")
        manifest_path = PurePosixPath(manifest)
        if manifest_path.is_absolute() or ".." in manifest_path.parts or manifest_path.as_posix() != manifest:
            raise ManifestError(f"{exceptions_file}:{line_number}: non-canonical manifest path {manifest!r}")
        if not SHA256_RE.fullmatch(digest):
            raise ManifestError(f"{exceptions_file}:{line_number}: invalid SHA-256 {digest!r}")
        key = (manifest, artifact)
        if key in result:
            raise ManifestError(f"{exceptions_file}:{line_number}: duplicate exception for {key!r}")
        result[key] = ExceptionEntry(manifest, artifact, digest, reason.strip())
    return result


def resolve_artifact(
    root: Path,
    manifest_path: Path,
    recorded_path: str,
    *,
    external_bundle: bool = False,
) -> Path | None:
    """Resolve an artifact without allowing it to escape its verification root."""
    manifest_dir = manifest_path.parent
    recorded = Path(recorded_path)
    basename = recorded.name
    if external_bundle and not recorded.is_absolute() and ".." in PurePosixPath(recorded_path).parts:
        raise ManifestError(
            f"external bundle artifact path traverses its directory: {recorded_path!r}"
        )
    if recorded.is_absolute():
        candidates = [manifest_dir / basename]
    else:
        candidates = [manifest_dir / recorded, manifest_dir.parent / recorded, manifest_dir / basename]

    # Preserve manifest-local snapshot precedence. For an external bundle, root
    # is the bundle directory, so parent fallbacks are naturally rejected.
    for candidate in candidates:
        try:
            resolved = candidate.resolve(strict=True)
            resolved.relative_to(root.resolve())
        except (OSError, ValueError):
            continue
        if resolved.is_file():
            return resolved
    return None


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_manifest(
    root: Path,
    manifest_path: Path,
    exceptions: dict[tuple[str, str], ExceptionEntry],
    *,
    external_bundle: bool = False,
) -> tuple[ManifestResult, set[tuple[str, str]]]:
    manifest_path = manifest_path.resolve()
    if external_bundle:
        # An explicitly supplied external manifest is a self-contained bundle.
        # Its directory is the only artifact root; repository exceptions never
        # apply to it and cannot accidentally bless an absent external file.
        manifest_rel = f"external:{manifest_path.as_posix()}"
        artifact_root = manifest_path.parent.resolve()
        applicable_exceptions: dict[tuple[str, str], ExceptionEntry] = {}
    else:
        manifest_rel = repo_relative(root, manifest_path)
        artifact_root = root.resolve()
        applicable_exceptions = exceptions

    entries = parse_manifest(manifest_path)
    verified = 0
    known_missing: list[str] = []
    used_exceptions: set[tuple[str, str]] = set()

    for entry in entries:
        if Path(entry.path).name == SELF_MANIFEST_NAME:
            continue
        key = (manifest_rel, entry.path)
        exception = applicable_exceptions.get(key)
        if exception is not None and exception.sha256 != entry.sha256:
            raise ManifestError(
                f"exception SHA does not match manifest for {manifest_rel}: {entry.path}"
            )

        artifact = resolve_artifact(
            artifact_root, manifest_path, entry.path, external_bundle=external_bundle
        )
        if artifact is None:
            if exception is None:
                raise ManifestError(f"missing artifact {entry.path!r} in {manifest_rel}")
            used_exceptions.add(key)
            known_missing.append(entry.path)
            continue

        actual = sha256_file(artifact)
        if actual != entry.sha256:
            raise ManifestError(
                f"SHA-256 mismatch for {entry.path!r} in {manifest_rel}: "
                f"expected={entry.sha256} actual={actual}"
            )
        if exception is not None:
            raise ManifestError(
                f"stale exception for {manifest_rel}: {entry.path} now exists with its recorded SHA; "
                "remove the exception row"
            )
        verified += 1

    manifest_exceptions = {key for key in applicable_exceptions if key[0] == manifest_rel}
    unused_for_manifest = manifest_exceptions - used_exceptions
    if unused_for_manifest:
        raise ManifestError(
            f"exception does not identify a missing manifest entry in {manifest_rel}: "
            + ", ".join(repr(key[1]) for key in sorted(unused_for_manifest))
        )
    if verified == 0:
        raise ManifestError(f"manifest has no verified artifacts: {manifest_rel}")
    return ManifestResult(manifest_rel, verified, tuple(known_missing)), used_exceptions


def is_negative_control(path: Path) -> bool:
    return path.parent.name.endswith("-negative")


def tracked_manifests(root: Path) -> list[Path]:
    try:
        completed = subprocess.run(
            ["git", "ls-files", MANIFEST_GLOB],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ManifestError(f"cannot enumerate tracked manifests: {exc}") from exc
    return [root / line for line in completed.stdout.splitlines() if line]


def check_repository(root: Path, paths: list[Path] | None = None) -> tuple[int, int, int]:
    root = root.resolve()
    exception_file = root / "scripts" / "manifest-exceptions.txt"
    exceptions = parse_exceptions(root, exception_file)
    explicit_paths = paths is not None
    manifests = paths if explicit_paths else tracked_manifests(root)
    used_exceptions: set[tuple[str, str]] = set()
    selected_repository_manifests: set[str] = set()
    verified_count = 0
    known_bad_count = 0
    negative_count = 0

    for manifest_arg in manifests:
        manifest = manifest_arg if manifest_arg.is_absolute() else root / manifest_arg
        manifest = manifest.resolve()
        try:
            repo_relative(root, manifest)
            external_bundle = False
            selected_repository_manifests.add(repo_relative(root, manifest))
        except ManifestError:
            if not explicit_paths or not manifest_arg.is_absolute():
                raise
            external_bundle = True

        manifest_label = (
            f"external:{manifest.as_posix()}"
            if external_bundle
            else repo_relative(root, manifest)
        )
        if is_negative_control(manifest):
            try:
                verify_manifest(
                    root, manifest, exceptions, external_bundle=external_bundle
                )
            except ManifestError:
                negative_count += 1
                print(f"MANIFEST-NEGATIVE-OK manifest={manifest_label} (expected failure)")
                continue
            raise ManifestError(f"negative control unexpectedly verifies: {manifest}")

        result, used = verify_manifest(
            root, manifest, exceptions, external_bundle=external_bundle
        )
        used_exceptions.update(used)
        verified_count += result.verified
        if result.known_missing:
            known_bad_count += len(result.known_missing)
            print(
                f"MANIFEST-KNOWN-MISSING manifest={result.manifest} "
                f"artifacts={','.join(result.known_missing)}"
            )
        else:
            print(f"MANIFEST-OK manifest={result.manifest} files={result.verified}")

    # A full tracked-tree scan must consume every registered exception. An
    # explicit path check is intentionally narrower: only rows for the selected
    # repository manifests are in scope; external bundles never use repo rows.
    if explicit_paths:
        relevant_exceptions = {
            key for key in exceptions if key[0] in selected_repository_manifests
        }
        unused = relevant_exceptions - used_exceptions
    else:
        unused = set(exceptions) - used_exceptions
    if unused:
        rendered = ", ".join(f"{manifest}:{artifact}" for manifest, artifact in sorted(unused))
        raise ManifestError(f"unused or stale exception entries: {rendered}")

    print(
        f"MANIFEST-SUMMARY verified={verified_count} "
        f"known_missing={known_bad_count} negative_controls={negative_count}"
    )
    return verified_count, known_bad_count, negative_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", nargs="*", help="repo-relative manifests, or an explicit absolute path to a self-contained external bundle")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        selected = [Path(item) for item in args.manifests] if args.manifests else None
        check_repository(root, selected)
    except ManifestError as exc:
        print(f"MANIFEST-FAIL: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
