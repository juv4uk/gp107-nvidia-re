#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-Volnist
# Artifact-scoped, fail-closed SHA-256 verification for recorded evidence.
#
# This is a shim, not a second implementation. The gate is
# scripts/check_evidence_manifests.py; its unit suite is
# scripts/test_evidence_manifests.py and runs as its own step in `make test` and
# in CI. It used to run here, inside the wrapper, which put the self-test's
# temporary fixtures into the gate's stdout: MANIFEST-SUMMARY appeared three
# times, and any `grep MANIFEST-OK` on that output could match a fixture instead
# of the manifest under test.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec python3 scripts/check_evidence_manifests.py "$@"
