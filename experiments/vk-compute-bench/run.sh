#!/usr/bin/env bash
# Driver-agnostic clean-room Vulkan compute benchmark runner.
# The same command is intended for the Nouveau/NVK boot and for a later
# proprietary NVIDIA boot. No PR #21 executable, no MMIO, no nvidia-settings.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BDF=${BENCH_BDF:-0000:01:00.0}
BINDING=$(basename "$(readlink -f "/sys/bus/pci/devices/$BDF/driver" 2>/dev/null || echo unknown)")
OUT=${BENCH_OUT:-$HERE/artifacts-$BINDING}

mkdir -p "$OUT"

capture_kernel() {
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -b -k --no-pager >"$1" 2>&1 || true
  else
    dmesg >"$1" 2>&1 || true
  fi
}

echo "== identity"
date -u +%Y-%m-%dT%H:%M:%SZ | tee "$OUT/00-utc.txt"
cat /proc/cmdline >"$OUT/01-cmdline.txt"
lspci -Dnnk -d 10de:1c82 >"$OUT/02-lspci.txt" 2>&1 || true
lsmod >"$OUT/03-lsmod.txt" 2>&1 || true
printf 'bdf=%s binding=%s\n' "$BDF" "$BINDING" | tee "$OUT/04-binding.txt"
printf 'icd=%s\n' "${BENCH_ICD:-default}" | tee "$OUT/05-icd.txt"

# The ICD must be selected BEFORE identity capture: 06-vulkaninfo.txt has to
# describe the very same driver that is timed in 08-run.log.
if [ -n "${BENCH_ICD:-}" ]; then
  export VK_ICD_FILENAMES="$BENCH_ICD"
else
  unset VK_ICD_FILENAMES || true
fi
export BENCH_BDF="$BDF"

if command -v vulkaninfo >/dev/null 2>&1; then
  vulkaninfo --summary >"$OUT/06-vulkaninfo.txt" 2>&1 || true
fi

echo "== kernel log before"
capture_kernel "$OUT/07-kernel-before.txt"
BEFORE=$(wc -l <"$OUT/07-kernel-before.txt")

echo "== benchmark (no strace inside the timed loop)"
set +e
"$HERE/vk_compute_bench" 2>&1 | tee "$OUT/08-run.log"
RC=${PIPESTATUS[0]}
set -e
echo "BENCH_RC=$RC" | tee -a "$OUT/08-run.log"

echo "== kernel log delta"
capture_kernel "$OUT/09-kernel-after.txt"
tail -n "+$((BEFORE + 1))" "$OUT/09-kernel-after.txt" >"$OUT/10-kernel-delta.txt" 2>&1 || true

{
  echo '# clean-room Vulkan compute benchmark artifacts'
  echo "bdf=$BDF"
  echo "binding=$BINDING"
  echo "icd=${BENCH_ICD:-default}"
  echo "bench_rc=$RC"
  echo "capture_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "uname=$(uname -a)"
  echo
  sha256sum "$OUT"/* 2>/dev/null | grep -v '/99-manifest.txt$' | sort -k2 || true
} >"$OUT/99-manifest.txt"

if [ "$RC" -eq 0 ]; then
  echo "BENCH-RUN-OK rc=0 binding=$BINDING out=$OUT"
else
  echo "BENCH-RUN-FAIL rc=$RC binding=$BINDING out=$OUT" >&2
fi
exit "$RC"
