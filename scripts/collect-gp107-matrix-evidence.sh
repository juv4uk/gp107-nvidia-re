#!/usr/bin/env bash
# Збирає evidence-матрицю для #28 на еталонній карті — лише читанням.
#
# Правила, які цей скрипт не порушує:
#   * нічого не пише в пристрій, не робить mmap, не чіпає resource0;
#   * не потребує root і не підвищує привілеї;
#   * відсутній інструмент — це записаний стан NOT_AVAILABLE, а не привід
#     впасти або вигадати значення;
#   * якщо карта не 10de:1c82, це фіксується як TARGET=NOT_THE_REFERENCE_CARD,
#     і жодна клітинка не стає PASS.
#
# Використання:
#   bash scripts/collect-gp107-matrix-evidence.sh [output-dir]
#
# Результат: каталог з артефактами + 99-manifest.txt із SHA-256, сумісний із
# scripts/test-evidence-manifest.sh (тобто його одразу перевіряє наявний гейт).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/evidence/matrix-$(date -u +%Y%m%dT%H%M%SZ)}"
REFERENCE_PCI="10de:1c82"

mkdir -p "$OUT" || { echo "COLLECT-FAIL: не створюється $OUT" >&2; exit 2; }

STATUS="$OUT/00-status.txt"
: > "$STATUS"

record() { printf '%s=%s\n' "$1" "$2" >> "$STATUS"; }
note()   { printf '%-14s %s\n' "$1" "$2"; }

# Кожен збирач: якщо інструмента немає — фіксуємо NOT_AVAILABLE і йдемо далі.
capture() { # $1 = назва артефакту, решта = команда
  local name="$1"; shift
  local file="$OUT/$name"
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'NOT_AVAILABLE: %s\n' "$1" > "$file"
    record "${name//[.-]/_}" "NOT_AVAILABLE:no-$1"
    note "$name" "NOT_AVAILABLE ($1 відсутній)"
    return 0
  fi
  if "$@" > "$file" 2>&1; then
    record "${name//[.-]/_}" "collected"
    note "$name" "collected"
  else
    local rc=$?
    record "${name//[.-]/_}" "FAILED:rc=$rc"
    note "$name" "FAILED rc=$rc (вивід збережено)"
  fi
}

note "output" "$OUT"

# --- 1. ідентичність цілі -------------------------------------------------
if command -v lspci >/dev/null 2>&1; then
  lspci -nn 2>/dev/null | grep -Ei "vga|3d|display" > "$OUT/01-gpu-identity.txt" || true
  if grep -qi "$REFERENCE_PCI" "$OUT/01-gpu-identity.txt"; then
    record target "REFERENCE_CARD:$REFERENCE_PCI"
  else
    record target "NOT_THE_REFERENCE_CARD:expected=$REFERENCE_PCI"
  fi
else
  printf 'NOT_AVAILABLE: lspci\n' > "$OUT/01-gpu-identity.txt"
  record target "UNKNOWN:lspci-absent"
fi
note "target" "$(grep '^target=' "$STATUS" | cut -d= -f2-)"

# --- 2. система й драйвери ------------------------------------------------
{ uname -srm; echo; cat /etc/os-release 2>/dev/null; } > "$OUT/02-system.txt" 2>&1 || true
record system "collected"

lsmod 2>/dev/null | grep -Ei "nouveau|nvidia|i915" > "$OUT/03-kernel-modules.txt" \
  || printf 'NOT_AVAILABLE: lsmod\n' > "$OUT/03-kernel-modules.txt"
record kernel_modules "collected"

capture 04-lspci-verbose.txt lspci -nnvv -s 01:00.0

# --- 3. відкритий стек: хто насправді обслуговує карту --------------------
capture 05-vulkaninfo.txt vulkaninfo --summary
capture 06-glxinfo.txt glxinfo -B

if command -v vulkaninfo >/dev/null 2>&1; then
  vulkaninfo --summary 2>/dev/null | grep -i "deviceName" | head -3 \
    > "$OUT/07-renderer.txt" || printf 'NOT_AVAILABLE: renderer\n' > "$OUT/07-renderer.txt"
else
  printf 'NOT_AVAILABLE: vulkaninfo\n' > "$OUT/07-renderer.txt"
fi
record renderer "collected"

# --- 4. частоти/температури без nvidia-smi --------------------------------
{
  for hw in /sys/class/drm/card*/device/hwmon/hwmon*; do
    [ -d "$hw" ] || continue
    echo "== $hw"
    for f in temp1_input temp1_max power1_average; do
      [ -r "$hw/$f" ] && printf '%s=%s\n' "$f" "$(cat "$hw/$f")"
    done
  done
  for card in /sys/class/drm/card*; do
    [ -d "$card" ] || continue
    for f in gt_cur_freq_mhz gt_max_freq_mhz; do
      [ -r "$card/device/$f" ] && printf '%s=%s\n' "$f" "$(cat "$card/device/$f")"
    done
  done
} > "$OUT/08-clocks-and-thermal.txt" 2>&1
[ -s "$OUT/08-clocks-and-thermal.txt" ] || printf 'NOT_AVAILABLE: no hwmon/gt entries\n' > "$OUT/08-clocks-and-thermal.txt"
record clocks_thermal "collected"

# --- 5. журнал ядра -------------------------------------------------------
if command -v dmesg >/dev/null 2>&1 && dmesg -r >/dev/null 2>&1; then
  dmesg 2>/dev/null | grep -Ei "nouveau|nvidia|drm" | tail -300 > "$OUT/09-dmesg.txt" || true
  record dmesg "collected"
else
  printf 'NOT_AVAILABLE: dmesg потребує прав або відсутній\n' > "$OUT/09-dmesg.txt"
  record dmesg "NOT_AVAILABLE:permission-or-absent"
fi
note "dmesg" "$(grep '^dmesg=' "$STATUS" | cut -d= -f2-)"

# --- 6. маніфест: ті самі SHA-256, які перевіряє наявний гейт -------------
MANIFEST="$OUT/99-manifest.txt"
{
  echo "# GP107 matrix evidence, зібрано $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# target=$(grep '^target=' "$STATUS" | cut -d= -f2-)"
  echo "# read-only: жодного запису в пристрій, mmap або resource0"
} > "$MANIFEST"
for f in "$OUT"/*.txt; do
  base="$(basename "$f")"
  [ "$base" = "99-manifest.txt" ] && continue
  printf '%s  %s\n' "$(sha256sum "$f" | awk '{print $1}')" "$base" >> "$MANIFEST"
done

# Маніфест не може хешувати сам себе; гейт це знає і пропускає 99-manifest.txt.
if bash "$ROOT/scripts/test-evidence-manifest.sh" "$MANIFEST" > "$OUT/10-manifest-check.txt" 2>&1; then
  note "manifest" "self-check OK"
  record manifest "self-check=OK"
else
  note "manifest" "self-check FAILED"
  record manifest "self-check=FAILED"
  echo "COLLECT-FAIL: власний маніфест не проходить перевірку — див. 10-manifest-check.txt" >&2
  exit 2
fi

note "summary" "$OUT/00-status.txt"
echo "COLLECT-OK dir=$OUT"
