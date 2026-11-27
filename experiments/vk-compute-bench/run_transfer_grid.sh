#!/usr/bin/env bash
# DEVICE_LOCAL staging/compute/readback phases: 3 повтори на розмір.
# Окремий вимір; не підміняє HOST_VISIBLE-результати з docs/17, docs/20, docs/21.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN=${BENCH_BIN:-$HERE/vk_transfer_bench}
: "${BENCH_ICD:?задайте BENCH_ICD}"
[ -x "$BIN" ] || { echo "TRANSFER-GRID-FAIL binary=$BIN" >&2; exit 2; }
SIZES=${BENCH_GRID_SIZES:-4096 1048576 8388608 33554432}
REPS=${BENCH_GRID_REPS:-1 2 3}
SUMMARY=${BENCH_GRID_SUMMARY:-$HERE/transfer-summary.tsv}

printf '#utc size rep rc driver_id driver_name host_type device_type ' >"$SUMMARY"
printf 'mismatch h2d_a_ns h2d_b_ns compute_ns d2h_c_ns h2d_a_gbs ' >>"$SUMMARY"
printf 'd2h_c_gbs out\n' >>"$SUMMARY"

for size in $SIZES; do
  for rep in $REPS; do
    out="$HERE/artifacts-transfer-${size}-rep${rep}"
    log="$out/08-run.log"
    BENCH_OUT="$out" BENCH_ICD="$BENCH_ICD" BENCH_BIN="$BIN" \
      BENCH_ELEMENTS="$size" BENCH_ITERS=20 \
      bash "$HERE/run.sh" >"$HERE/.transfer-grid-last.out" 2>&1
    rc=$?
    drv=$(grep -m1 '^TRANSFER-DRIVER-RECORD ' "$log" 2>/dev/null || true)
    mem=$(grep -m1 '^TRANSFER-MEM-RECORD ' "$log" 2>/dev/null || true)
    cor=$(grep -m1 '^TRANSFER-CORRECT ' "$log" 2>/dev/null || true)
    phase() {
      grep -m1 "^TRANSFER-PHASE phase=$1 " "$log" 2>/dev/null \
        | sed -n 's/.*median_ns=\([0-9.]*\).*/\1/p'
    }
    phase_gbs() {
      grep -m1 "^TRANSFER-PHASE phase=$1 " "$log" 2>/dev/null \
        | sed -n 's/.*effective_gb_s=\([0-9.]*\).*/\1/p'
    }
    printf '%s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$size" "$rep" "$rc" \
      "$(printf '%s' "$drv" | sed -n 's/.*id=\([0-9]*\).*/\1/p')" \
      "$(printf '%s' "$drv" | sed -n 's/.*name=\([^ ]*\).*/\1/p')" \
      "$(printf '%s' "$mem" | sed -n 's/.*host_type=\([0-9]*\).*/\1/p')" \
      "$(printf '%s' "$mem" | sed -n 's/.*device_type=\([0-9]*\).*/\1/p')" \
      "$(printf '%s' "$cor" | sed -n 's/.*mismatch=\([0-9]*\).*/\1/p')" \
      "$(phase h2d_a)" "$(phase h2d_b)" "$(phase compute)" "$(phase d2h_c)" \
      "$(phase_gbs h2d_a)" "$(phase_gbs d2h_c)" "${out#$HERE/}" >>"$SUMMARY"
    printf 'TRANSFER-POINT size=%s rep=%s rc=%s h2d_a=%s d2h_c=%s\n' \
      "$size" "$rep" "$rc" "$(phase h2d_a)" "$(phase d2h_c)"
  done
done
rm -f "$HERE/.transfer-grid-last.out"
echo "TRANSFER-GRID-DONE points=$(( $(wc -l <"$SUMMARY") - 1 ))"
