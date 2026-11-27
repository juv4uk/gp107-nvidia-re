#!/usr/bin/env bash
# PASCAL-PROBE gate for the clean-room FPC probes.
# Discipline borrowed from juv4uk/wsm-lazarus scripts/test.sh and
# check-no-lcl.sh: fail closed, name the failing step, never relax a gate
# to obtain a green result.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FPC_BIN=${FPC:-fpc}
FPC_EXPECTED=${FPC_EXPECTED:-3.2.2}
BIN="pascal/01_min_cuinit"
WORK=$(mktemp -d)
OUT="$WORK/out"

trap '_rc=$?; rm -rf "$WORK"; if [ "$_rc" -ne 0 ]; then
         echo "PASCAL-PROBE-FAIL крок=\"$BASH_COMMAND\" код=$_rc" >&2
       fi' EXIT

fail() { echo "PASCAL-PROBE-FAIL: $*" >&2; exit 1; }
step() { printf '== %s\n' "$*"; }

# 1) Toolchain pin. wsm-lazarus records 3.2.2 as the baseline and 3.2.4 as
#    an unmeasured source-tag candidate; mixing them would invalidate
#    byte-level evidence.
step "FPC pin ($FPC_EXPECTED)"
command -v "$FPC_BIN" >/dev/null 2>&1 || fail "нема $FPC_BIN"
got="$("$FPC_BIN" -iV)"
[ "$got" = "$FPC_EXPECTED" ] || fail "FPC pin: очікували $FPC_EXPECTED, маємо $got"

# 2) Firewall: no GUI, no libc link directive, no thread manager dependency.
#    BaseUnix wrappers are syscall imports only where FPC_SYSC_* exists;
#    the final ELF check below is the real proof of libc-freedom.
step 'firewall (no LCL / libc link / cthreads)'
if grep -nHEn '(Forms|Controls|LCL|Interfaces|cthreads)|\{\$linklib[[:space:]]+c\}|external[[:space:]]+['\''"]c['\''"]' \
      pascal/*.pas; then
  fail 'заборонена залежність у Pascal-дисках'
fi

# 3) Clean build: compile-time SizeOf asserts live in nv_abi.pas.
step 'clean build'
make -C pascal clean >/dev/null
make -C pascal all

# 4) Negative witness: the SizeOf assertion must actually fail the build.
#    Without this, a vacuous assertion would look like a green gate.
step 'negative witness (compile-time assert is not vacuous)'
mkdir -p "$WORK/neg"
cp pascal/nv_abi.pas "$WORK/neg/"
sed -i 's/minor_number:   LongWord;/minor_number:   QWord;/' "$WORK/neg/nv_abi.pas"
printf 'program neg;\n{$mode objfpc}\nuses nv_abi;\nbegin WriteLn(NV_IOC_CARD_INFO); end.\n' \
  > "$WORK/neg/neg.pas"
if "$FPC_BIN" -O2 -Fu"$WORK/neg" -FU"$WORK/neg" -o"$WORK/neg/neg" \
     "$WORK/neg/neg.pas" >"$WORK/neg.log" 2>&1; then
  fail 'negative witness зібрався: compile-time assert нічого не перевіряє'
fi
grep -Fq 'Upper bound of range is less than lower bound' "$WORK/neg.log" \
  || fail 'negative witness впав з іншої причини (див. лог)'

# 5) Runtime witness.
step 'runtime witness'
timeout 20s "./$BIN" >"$OUT"
cat "$OUT"
for marker in \
  'sysfs block_size_bytes : 0x08000000' \
  'NV_ESC_SYS_PARAMS  : memblock_size = 134217728 bytes' \
  'NV_ESC_CARD_INFO   : GPU 0: 10DE:1C82' \
  'minor=0' \
  'BAR0=0xEE000000+0x01000000' \
  'open(/dev/nvidia0)' \
  'open(/dev/nvidia-uvm)'; do
  grep -Fq "$marker" "$OUT" || fail "нема маркера: $marker"
done

# 6) Binary proof: statically linked, no DT_NEEDED entries.
step 'binary proof'
file "$BIN" | grep -q 'statically linked' || fail 'бінарник не статичний'
if readelf -d "$BIN" 2>/dev/null | grep -q 'NEEDED'; then
  fail 'є динамічні залежності (DT_NEEDED)'
fi

echo 'PASCAL-PROBE-GATE-OK fpc='"$got"' static=yes no-libc=yes gpu=10de:1c82'
