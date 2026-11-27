#!/usr/bin/env bash
# capability identity gate — стиль wsm-lazarus: названий крок, fail-closed,
# мутаційні негативи, перевірка КОДУ, а не текстів пояснень.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FPC_BIN=${FPC:-fpc}
FPC_EXPECTED=3.2.2
BIN="$ROOT/build/capability-identity/bin"
UNITS="$ROOT/build/capability-identity/units"
WORK=$(mktemp -d)

trap '_rc=$?; rm -rf "$WORK"; if [ "$_rc" -ne 0 ]; then
         echo "CAPABILITY-IDENTITY-FAIL крок=\"$BASH_COMMAND\" код=$_rc" >&2
       fi' EXIT

fail() { echo "CAPABILITY-IDENTITY-FAIL: $*" >&2; exit 1; }
step() { printf '== %s\n' "$*"; }

step 'driver firewall (code, not prose)'
bash "$ROOT/scripts/check-no-driver-overreach.sh"

step 'ABI authority boundary'
if grep -RIl 'b5ec3211f6bd07fb7c4a5f704875892eff145b91' \
     pascal scripts tests 2>/dev/null >/dev/null; then
  fail 'код research-репо містить authoritative ABI-pin'
fi
echo 'ABI-BOUNDARY-OK pin-in-code=absent documented-provenance=allowed'

step 'FPC pin'
got=$("$FPC_BIN" -iV)
[ "$got" = "$FPC_EXPECTED" ] || fail "FPC pin: expected=$FPC_EXPECTED got=$got"
echo "FPC-PIN-OK $got"

step 'compile capability identity emitter'
mkdir -p "$BIN" "$UNITS"
"$FPC_BIN" -B -O2 -Mobjfpc -Sh -XS -Cr -Co -Ci -gl \
  -Fu"$ROOT/pascal" -FU"$UNITS" -FE"$BIN" \
  -o"$BIN/04_capability_identity" \
  "$ROOT/pascal/04_capability_identity.pas" >/dev/null

step 'source gate log'
if [ -n "${GATE_LOG:-}" ]; then
  [ -r "$GATE_LOG" ] || fail "GATE_LOG недоступний: $GATE_LOG"
  LOG="$GATE_LOG"
else
  LOG="$WORK/gate.log"
  bash "$ROOT/scripts/test-pascal-probe.sh" >"$LOG" 2>&1
fi
grep -Fq 'PASCAL-PROBE-GATE-OK' "$LOG" || fail ' базовий GP107 gate не зелений'

step 'emit research contract'
"$BIN/04_capability_identity" "$LOG" >"$WORK/contract.lisp"

step 'contract markers'
for marker in \
  '(kind . wsm-open-driver-capability-identity-research)' \
  '(abi-pin . untouched)' \
  '(evidence-source . pascal-probe-gate-log)' \
  '(vendor . 0x10de)' \
  '(device . 0x1c82)' \
  '(bdf . "0000:01:00.0")' \
  '(right . inventory-only)' \
  '(device-id . 0) (device-id-note . logical-not-pci)' \
  '(valid-cards . 1) (evidence . runtime-proven)' \
  '(boot0 . unproven)' \
  '((rm-control -> mmio) . forbidden-on-hosted)' \
  '(human-attestation . none)'; do
  grep -Fq "$marker" "$WORK/contract.lisp" || fail "нема маркера: $marker"
done
if grep -Eq '137000A1|Tested-by|PROT_WRITE' "$WORK/contract.lisp"; then
  fail 'контракт вийшов за identity-межу'
fi

step 'negative witness (missing BOOT0 marker is fatal)'
sed '/BOOT0: UNPROVEN/d' "$LOG" >"$WORK/no-boot0.log"
if "$BIN/04_capability_identity" "$WORK/no-boot0.log" >/dev/null 2>"$WORK/no-boot0.err"; then
  fail 'еміттер прийняв лог без BOOT0: UNPROVEN'
fi
grep -Fq 'IDENTITY-FAIL step=missing-line' "$WORK/no-boot0.err" \
  || fail 'нема названого negative-маркера для BOOT0'

step 'negative witness (second GPU is ambiguous)'
awk '{print} /NV_ESC_CARD_INFO   : GPU 0:/{print "NV_ESC_CARD_INFO   : GPU 1: 10DE:1C82 @ 0000:02:00.0, gpu_id=0x200, minor=1"}' \
  "$LOG" >"$WORK/two-gpus.log"
if "$BIN/04_capability_identity" "$WORK/two-gpus.log" >/dev/null 2>"$WORK/two-gpus.err"; then
  fail 'еміттер прийняв лог з двома GPU'
fi
grep -Fq 'IDENTITY-FAIL step=card-count code=12' "$WORK/two-gpus.err" \
  || fail 'нема названого negative-маркера для card-count'

echo "CAPABILITY-IDENTITY-GATE-OK fpc=$got abi-pin=untouched boot0=unproven mmio=deferred negative=2"
