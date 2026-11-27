#!/usr/bin/env bash
# Run the clean-room NVK compute smoke test and capture runtime evidence.
# No PR #21 executable, no proprietary ICD, no MMIO access.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${SMOKE_OUT:-$HERE/artifacts}"
ICD="${SMOKE_ICD:-/usr/share/vulkan/icd.d/nouveau_icd.json}"
BDF="${SMOKE_BDF:-0000:01:00.0}"

mkdir -p "$OUT"
export VK_ICD_FILENAMES="$ICD"
export SMOKE_BDF="$BDF"

capture_log() {
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -b -k --no-pager >"$1" 2>&1 || true
  else
    dmesg >"$1" 2>&1 || true
  fi
}

echo "== env"
echo "icd=$ICD bdf=$BDF"
command -v strace >/dev/null 2>&1 || { echo 'RUN-FAIL: strace unavailable' >&2; exit 2; }
[ -r "$ICD" ] || { echo "RUN-FAIL: ICD unreadable: $ICD" >&2; exit 2; }

echo "== kernel log before"
capture_log "$OUT/01-kernel-before.txt"
BEFORE=$(wc -l <"$OUT/01-kernel-before.txt")

echo "== harness under strace"
set +e
strace -f -e trace=ioctl -o "$OUT/02-ioctl.txt" \
  "$HERE/nvk_compute_smoke" 2>&1 | tee "$OUT/03-run.log"
RC=${PIPESTATUS[0]}
set -e
echo "HARNESS_RC=$RC" | tee -a "$OUT/03-run.log"

echo "== filter ioctl trace"
grep -E 'DRM_IOCTL|drm|nouveau' "$OUT/02-ioctl.txt" >"$OUT/04-drm-ioctl.txt" 2>&1 || true

# Submit-side fragment: the last NOUVEAU_EXEC calls and their SYNCOBJ_WAITs.
# Line numbers are preserved from the full strace output.
grep -nE 'DRM_IOCTL_NOUVEAU_EXEC|DRM_IOCTL_SYNCOBJ_WAIT' \
  "$OUT/02-ioctl.txt" | tail -n 8 >"$OUT/08-dispatch-ioctl.txt" 2>&1 || true

echo "== kernel log delta"
capture_log "$OUT/05-kernel-after.txt"
tail -n "+$((BEFORE + 1))" "$OUT/05-kernel-after.txt" >"$OUT/06-kernel-delta.txt" 2>&1 || true
grep -Ei 'nouveau|fifo|gr|ce|dispatch' "$OUT/06-kernel-delta.txt" \
  >"$OUT/07-kernel-delta-filtered.txt" 2>&1 || true

{
  echo '# NVK compute smoke artifacts'
  echo "icd=$ICD"
  echo "bdf=$BDF"
  echo "harness_rc=$RC"
  echo "capture_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  sha256sum "$OUT"/* 2>/dev/null | grep -v '/99-manifest.txt$' | sort -k2 || true
} >"$OUT/99-manifest.txt"

if [ "$RC" -eq 0 ]; then
  echo "NVK-COMPUTE-RUN-OK rc=0 out=$OUT"
else
  echo "NVK-COMPUTE-RUN-FAIL rc=$RC out=$OUT" >&2
fi
exit "$RC"
