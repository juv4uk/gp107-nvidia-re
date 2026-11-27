#!/usr/bin/env bash
# Negative control: same GPU, same dispatch/fence path, no-op SPIR-V.
# Expected outcome is failure at the checksum step.  This is NOT an acceptance
# run and is never used as a CPU fallback.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${SMOKE_OUT:-$HERE/artifacts-negative}"
ICD="${SMOKE_ICD:-/usr/share/vulkan/icd.d/nouveau_icd.json}"
BDF="${SMOKE_BDF:-0000:01:00.0}"

mkdir -p "$OUT"
export VK_ICD_FILENAMES="$ICD" SMOKE_BDF="$BDF"

set +e
"$HERE/nvk_compute_smoke_noop" >"$OUT/01-noop.log" 2>&1
RC=$?
set -e
echo "NOOP_RC=$RC" >>"$OUT/01-noop.log"

grep -q 'FENCE-OK status=SIGNALED' "$OUT/01-noop.log" || {
  echo 'NEGATIVE-CONTROL-FAIL: fence not signaled' >&2; exit 2; }
grep -q 'NVK-COMPUTE-FAIL step=checksum' "$OUT/01-noop.log" || {
  echo 'NEGATIVE-CONTROL-FAIL: checksum guard did not fire' >&2; exit 2; }
[ "$RC" -eq 2 ] || {
  echo "NEGATIVE-CONTROL-FAIL: unexpected rc=$RC" >&2; exit 2; }

{
  echo '# NVK compute smoke negative control'
  echo "icd=$ICD"
  echo "bdf=$BDF"
  echo "noop_rc=$RC"
  echo "capture_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  sha256sum "$OUT"/* 2>/dev/null | grep -v '/99-manifest.txt$' | sort -k2 || true
} >"$OUT/99-manifest.txt"

echo "NEGATIVE-CONTROL-OK rc=$RC step=checksum out=$OUT"
