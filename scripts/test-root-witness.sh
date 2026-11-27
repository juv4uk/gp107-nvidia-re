#!/usr/bin/env bash
# Опційний root-свідок: open(resource0) OK -> mmap(PROT_READ|MAP_SHARED)
# EINVAL -> BOOT0 UNPROVEN, причина EINVAL лишається UNPROVEN.
# НЕ входить до базового test-pascal-probe.sh. Бази гейт детермінований і
# працює звичайним користувачем (OPEN_DENIED/EACCES).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SUDO_BIN=${SUDO_BIN:-sudo}
SUDO_FLAGS=${SUDO_FLAGS:--n}
BIN="pascal/02_bar_identity"
WORK=$(mktemp -d)
OUT="$WORK/root.out"

trap '_rc=$?; rm -rf "$WORK"; if [ "$_rc" -ne 0 ]; then
          echo "ROOT-WITNESS-FAIL крок=\"$BASH_COMMAND\" код=$_rc" >&2
        fi' EXIT

fail() { echo "ROOT-WITNESS-FAIL: $*" >&2; exit 1; }
step() { printf '== %s\n' "$*"; }

step "наявність $BIN"
[ -x "$BIN" ] || make -C pascal 02_bar_identity >/dev/null

step "неінтерактивний sudo ($SUDO_BIN $SUDO_FLAGS)"
"$SUDO_BIN" $SUDO_FLAGS true || fail 'sudo недоступний; базовий гейт лишається на рівні користувача (EACCES)'

step "root-прогон $BIN"
"$SUDO_BIN" $SUDO_FLAGS "./$BIN" >"$OUT"
cat "$OUT"

for marker in \
  'NV_ESC_CARD_INFO identity : 10DE:1C82 @ 0000:01:00.0' \
  'PCI-CONFIG identity       : 10DE:1C82 BAR0=0xEE000000' \
  'CROSS-CHECK-OK: pci-config == NV_ESC_CARD_INFO'; do
  grep -Fq "$marker" "$OUT" || fail "нема маркера: $marker"
done

grep -Eq '^resource0 open            : fd=[0-9]+ O_RDONLY$' "$OUT" \
  || fail 'root не відкрив resource0'
grep -Fq 'resource0 mmap PROT_READ|MAP_SHARED: DENIED errno=22 (EINVAL)' "$OUT" \
  || fail 'root-mmap не дав EINVAL'
for marker in \
  'BAR0-STATE: MMAP_DENIED' \
  'MMAP-DENIAL-CAUSE: UNPROVEN (errno alone proves no cause)' \
  'BOOT0: UNPROVEN (mmap denied; register not read)' \
  'G1-FAIL-CLOSED-OK'; do
  grep -Fq "$marker" "$OUT" || fail "нема маркера: $marker"
done
if grep -Fq 'BAR0-STATE: OPEN_DENIED' "$OUT"; then
  fail 'root відкрив resource0, але звіт стверджує OPEN_DENIED'
fi
if grep -Eq 'BAR0 exclusively|owns BAR0|причина EINVAL' "$OUT"; then
  fail 'EINVAL перетворено на необґрунтоване твердження про причину'
fi

echo 'ROOT-WITNESS-OK resource0=open-ok mmap=EINVAL cause=unproven boot0=unproven'
