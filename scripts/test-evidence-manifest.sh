#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-Volnist
# Artifact-scoped, fail-closed SHA-256 verification for recorded evidence.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 scripts/test_evidence_manifests.py
python3 scripts/check_evidence_manifests.py "$@"
