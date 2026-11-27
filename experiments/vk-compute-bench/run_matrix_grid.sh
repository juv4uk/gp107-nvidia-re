#!/usr/bin/env bash
# Експериментальна матриця: local size × submits × розмір задачі, 3 повтори.
# Driver-agnostic: ICD задається BENCH_ICD, драйвер лише записується; PR #21
# і MMIO не використовуються. Усі запуски (у тому числі невдалі) потрапляють
# до matrix-summary.tsv; жоден результат не відкидається без причини.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN=${BENCH_BIN:-$HERE/vk_compute_matrix}
: "${BENCH_ICD:?задайте BENCH_ICD}"
[ -x "$BIN" ] || { echo "MATRIX-FAIL binary=$BIN" >&2; exit 2; }

SIZES=${BENCH_GRID_SIZES:-4096 1048576 8388608}
LS=${BENCH_GRID_LS:-32 64 128 256}
SUBS=${BENCH_GRID_SUBMITS:-1 4 16}
REPS=${BENCH_GRID_REPS:-1 2 3}
SUMMARY=${BENCH_GRID_SUMMARY:-$HERE/matrix-summary.tsv}

printf '#utc size local_size submits rep rc driver_id driver_name ' \
  >"$SUMMARY"
printf 'median_ns_batch median_ns_per_submit effective_gb_s mismatches ' >>"$SUMMARY"
printf 'out\n' >>"$SUMMARY"

for size in $SIZES; do
  for ls in $LS; do
    for sub in $SUBS; do
      for rep in $REPS; do
        out="$HERE/artifacts-matrix-${size}-ls${ls}-s${sub}-rep${rep}"
        log="$out/08-run.log"
        BENCH_OUT="$out" BENCH_ICD="$BENCH_ICD" BENCH_BIN="$BIN" \
          BENCH_ELEMENTS="$size" BENCH_ITERS=20 \
          BENCH_LOCAL_SIZE="$ls" BENCH_SUBMITS="$sub" \
          bash "$HERE/run.sh" >"$HERE/.matrix-grid-last.out" 2>&1
        rc=$?
        case_line=$(grep -m1 '^MATRIX-CASE ' "$log" 2>/dev/null || true)
        drv=$(grep -m1 '^BENCH-DRIVER-RECORD ' "$log" 2>/dev/null || true)
        did=$(printf '%s' "$drv" | sed -n 's/.*id=\([0-9]*\).*/\1/p')
        dname=$(printf '%s' "$drv" | sed -n 's/.*name=\([^ ]*\).*/\1/p')
        med=$(printf '%s' "$case_line" | sed -n 's/.*median_ns_batch=\([0-9.]*\).*/\1/p')
        persub=$(printf '%s' "$case_line" | sed -n 's/.*median_ns_per_submit=\([0-9.]*\).*/\1/p')
        gbs=$(printf '%s' "$case_line" | sed -n 's/.*effective_gb_s=\([0-9.]*\).*/\1/p')
        bad=$(grep -c 'mismatch=[^0]' "$log" 2>/dev/null || true)
        printf '%s %s %s %s %s %s %s %s %s %s %s %s %s\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$size" "$ls" "$sub" "$rep" \
          "$rc" "${did:-NA}" "${dname:-NA}" "${med:-NA}" "${persub:-NA}" \
          "${gbs:-NA}" "${bad:-NA}" "${out#$HERE/}" >>"$SUMMARY"
        printf 'MATRIX-POINT size=%s ls=%s submits=%s rep=%s rc=%s median=%s\n' \
          "$size" "$ls" "$sub" "$rep" "$rc" "${med:-NA}"
      done
    done
  done
done
rm -f "$HERE/.matrix-grid-last.out"
echo "MATRIX-GRID-DONE summary=${SUMMARY#$HERE/} points=$(( $(wc -l <"$SUMMARY") - 1 ))"
