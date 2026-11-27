#!/usr/bin/env bash
# capability-driver gate — style of the existing wsm-lazarus-derived gates:
# named steps, fail-closed, mutation negatives, code (not prose) inspection.
# Deterministic: all negative witnesses use a synthetic sysfs fixture.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="$ROOT/build/capability-driver/gp107ctl"
WORK=$(mktemp -d)
FIX="$WORK/sysfs"

trap '_rc=$?; rm -rf "$WORK"; if [ "$_rc" -ne 0 ]; then
          echo "CAPABILITY-DRIVER-FAIL крок=\"$BASH_COMMAND\" код=$_rc" >&2
        fi' EXIT

fail() { echo "CAPABILITY-DRIVER-FAIL: $*" >&2; exit 1; }
step() { printf '== %s\n' "$*"; }

step 'shell syntax'
bash -n "$ROOT/scripts/test-capability-driver.sh"
bash -n "$ROOT/scripts/test-capability-identity.sh"
echo 'SHELL-SYNTAX-OK'

step 'driver firewall (code, not prose)'
if grep -nHE '\b(PROT_WRITE|MAP_FIXED|O_RDWR|FpWrite|pwrite|msync|nva|ioctl|NV_ESC|137000A1|Tested-by|RM_ALLOC)\b' \
     lib/*.c lib/*.h >>"$WORK/fw.txt"; then
  cat "$WORK/fw.txt" >&2
  fail 'banned operation or claim in library code'
fi
if grep -R -F -q 'b5ec3211f6bd07fb7c4a5f704875892eff145b91' lib; then
  fail 'authoritative ABI pin present in library code'
fi
echo 'DRIVER-FIREWALL-OK banned-ops=absent pin-in-code=absent boot0-value=absent'

step 'compile C11 gate with warnings as errors'
make -C "$ROOT/lib" clean all >/dev/null
[ -x "$BIN" ] || fail 'no gp107ctl binary'
"$BIN" layout | grep -Fq 'LAYOUT-OK identity=32 binding=68 inventory=140' \
  || fail 'compile-time layout assertion output missing'
echo 'C11-COMPILE-OK werror=yes layout=32/68/140'

step 'synthetic sysfs fixture (single card, nvidia bound)'
mkdir -p "$FIX/bus/pci/devices/0000:01:00.0"
python3 - "$FIX/bus/pci/devices/0000:01:00.0" <<'PY'
import os
import sys

dev = sys.argv[1]
cfg = bytearray(32)
cfg[0:2] = bytes((0xde, 0x10))
cfg[2:4] = bytes((0x82, 0x1c))
cfg[0x04:0x06] = bytes((0x07, 0x04))
cfg[0x08] = 0xa1
cfg[0x0b] = 0x03
cfg[0x0e] = 0x80
cfg[0x10:0x14] = bytes((0x00, 0x00, 0x00, 0xee))
with open(os.path.join(dev, 'config'), 'wb') as fh:
    fh.write(cfg)
with open(os.path.join(dev, 'vendor'), 'w') as fh:
    fh.write('0x10de\n')
with open(os.path.join(dev, 'device'), 'w') as fh:
    fh.write('0x1c82\n')
with open(os.path.join(dev, 'resource0'), 'wb') as fh:
    fh.write(bytes((0xde, 0x10, 0x82, 0x1c)) + bytes(4092))
PY
ln -s "$FIX/bus/pci/drivers/nvidia" "$FIX/bus/pci/devices/0000:01:00.0/driver"

step 'fixture identity (single card is accepted)'
GP107_SYSFS_ROOT=unused "$BIN" inventory --sysfs-root="$FIX" >"$WORK/inv.out"
for marker in \
  '(kind . gp107-userspace-capability-identity)' \
  '(abi-pin . untouched)' \
  '(vendor . 0x10de)' \
  '(device . 0x1c82)' \
  '(bdf . "0000:01:00.0")' \
  '(bar0-base . 0xee000000)' \
  '(config (revision . 0xa1) (class . 0x030000) (header . 0x80) (command . 0x0407))' \
  '(bar0 (raw . 0xee000000) (space . memory) (width . 32-bit) (prefetch . no) (source . public-pci-header))' \
  '(driver (bound . yes) (name . "nvidia"))' \
  '(rm-control . none)' \
  '(boot0 . unproven)' \
  '(summary . IDENTITY-OK)'; do
  grep -Fq "$marker" "$WORK/inv.out" || fail "нема маркера: $marker"
done
echo 'FIXTURE-IDENTITY-OK source=synthetic-sysfs'

step 'capability ledger (bound driver denies MMIO, RM deferred)'
"$BIN" capabilities --sysfs-root="$FIX" >"$WORK/ledger-bound.out"
for marker in \
  '(kind . gp107-capability-ledger)' \
  '(abi-pin . untouched)' \
  '(pci-inventory . observed)' \
  '(bar0-decode . complete)' \
  '(rm-identity . deferred) (reason . not-in-this-slice)' \
  '(mmio-read-software-gate . denied) (reason . driver-bound)' \
  '(owner-approval . not-inferred)' \
  '(physical-mmio . not-authorized)' \
  '(boot0 . unproven) (evidence . unproven)' \
  '(rights (write . none) (dispatch . none) (rm . none))' \
  '(summary . CAPABILITY-LEDGER-OK)'; do
  grep -Fq "$marker" "$WORK/ledger-bound.out" || fail "нема маркера: $marker"
done
echo 'LEDGER-BOUND-OK mmio=denied rm=deferred'

step 'negative witness (second matching card is ambiguous)'
mkdir -p "$FIX/bus/pci/devices/0000:02:00.0"
cp "$FIX/bus/pci/devices/0000:01:00.0"/{config,vendor,device,resource0} \
   "$FIX/bus/pci/devices/0000:02:00.0/"
if "$BIN" inventory --sysfs-root="$FIX" >"$WORK/two.out" 2>"$WORK/two.err"; then
  fail 'еміттер прийняв дві картки'
fi
grep -Fq 'IDENTITY-FAIL step=card-count' "$WORK/two.err" \
  || fail 'нема названого negative-маркера card-count'
rm -rf "$FIX/bus/pci/devices/0000:02:00.0"
echo 'NEGATIVE-CARD-COUNT-OK marker=step=card-count'

step 'negative witness (unreadable PCI config is fatal)'
mv "$FIX/bus/pci/devices/0000:01:00.0/config" "$WORK/config.saved"
if "$BIN" inventory --sysfs-root="$FIX" >"$WORK/nocfg.out" 2>"$WORK/nocfg.err"; then
  fail 'еміттер прийняв картку без config'
fi
grep -Fq 'IDENTITY-FAIL step=pci-config-read' "$WORK/nocfg.err" \
  || fail 'нема названого negative-маркера pci-config-read'
mv "$WORK/config.saved" "$FIX/bus/pci/devices/0000:01:00.0/config"
echo 'NEGATIVE-CONFIG-READ-OK marker=step=pci-config-read'

step 'negative witness (BDF assertion is enforced)'
if "$BIN" inventory --sysfs-root="$FIX" --expect-bdf=0000:09:00.0 \
    >"$WORK/bdf.out" 2>"$WORK/bdf.err"; then
  fail 'еміттер прийняв чужкий BDF'
fi
grep -Fq 'IDENTITY-FAIL step=bdf-mismatch' "$WORK/bdf.err" \
  || fail 'нема названого negative-маркера bdf-mismatch'
echo 'NEGATIVE-BDF-OK marker=step=bdf-mismatch'

step 'driver-link error is unknown, never unbound'
rm "$FIX/bus/pci/devices/0000:01:00.0/driver"
printf 'not-a-symlink\n' > "$FIX/bus/pci/devices/0000:01:00.0/driver"
if "$BIN" inventory --sysfs-root="$FIX" >"$WORK/baddriver.out" 2>"$WORK/baddriver.err"; then
  fail 'invalid driver entry was accepted as unbound'
fi
grep -Fq 'IDENTITY-FAIL step=driver-binding-read code=20' "$WORK/baddriver.err" \
  || fail 'driver-link read error did not fail closed'
rm "$FIX/bus/pci/devices/0000:01:00.0/driver"
ln -s "$FIX/bus/pci/drivers/nvidia" "$FIX/bus/pci/devices/0000:01:00.0/driver"
echo 'NEGATIVE-DRIVER-LINK-OK unknown=denied only-ENOENT=unbound'


step 'MMIO CLI requires an explicit offset'
if "$BIN" mmio-read --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/no-offset.out" 2>"$WORK/no-offset.err"; then
  fail 'MMIO CLI accepted implicit offset zero'
fi
grep -Fq 'USAGE-FAIL step=offset-required' "$WORK/no-offset.err" \
  || fail 'missing explicit-offset usage error'
echo 'NEGATIVE-MMIO-OFFSET-REQUIRED-OK'

step 'physical MMIO is denied with and without --allow-mmio'
for mode in no-opt-in allow-flag; do
  if [ "$mode" = allow-flag ]; then
    if "$BIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" \
        >"$WORK/mmio-$mode.out" 2>"$WORK/mmio-$mode.err"; then
      fail '--allow-mmio unexpectedly authorized physical MMIO'
    fi
  else
    if "$BIN" mmio-read --offset=0x0 --sysfs-root="$FIX" \
        >"$WORK/mmio-$mode.out" 2>"$WORK/mmio-$mode.err"; then
      fail 'physical MMIO unexpectedly succeeded without owner authorization'
    fi
  fi
  grep -Fq 'MMIO-FAIL step=owner-authorization-required code=21' \
      "$WORK/mmio-$mode.err" \
    || fail "physical MMIO denial missing for $mode"
done
echo 'NEGATIVE-MMIO-OWNER-AUTH-OK allow-flag=not-authorization'

step 'public C API cannot bypass physical MMIO denial'
cat > "$WORK/mmio-api-test.c" <<'EOF'
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "gp107_identity.h"
#include "gp107_mmio.h"

int main(void)
{
    char err[256] = {0};
    uint32_t value = 0;
    int rc = gp107_mmio_read32("/path/that-must-not-be-opened",
                               "0000:01:00.0", 1, 0,
                               &value, err, sizeof(err));

    if (rc != GP107_ERR_NOT_AUTHORIZED ||
        strstr(err, "owner-authorization-required") == NULL) {
        fprintf(stderr, "MMIO-API-DENIAL-FAIL rc=%d err=%s\n", rc, err);
        return 1;
    }
    puts("MMIO-API-DENIAL-OK direct-call=denied");
    return 0;
}
EOF
cc -std=c11 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L \
  -I"$ROOT/lib" "$WORK/mmio-api-test.c" "$ROOT/lib/gp107_identity.c" \
  "$ROOT/lib/gp107_mmio.c" -o "$WORK/mmio-api-test"
"$WORK/mmio-api-test"

step 'MMIO implementation contains no device-file or mapping calls'
if grep -nE '\b(open|openat|mmap|munmap)[[:space:]]*\(' lib/gp107_mmio.c; then
  fail 'MMIO implementation still contains physical access calls'
fi
echo 'MMIO-SOURCE-FIREWALL-OK no-open=no-map'

step 'capability ledger denies physical MMIO regardless of CLI flag'
rm "$FIX/bus/pci/devices/0000:01:00.0/driver"
for mode in no-flag allow-flag; do
  if [ "$mode" = allow-flag ]; then
    "$BIN" capabilities --allow-mmio --sysfs-root="$FIX" >"$WORK/ledger-$mode.out"
  else
    "$BIN" capabilities --sysfs-root="$FIX" >"$WORK/ledger-$mode.out"
  fi
  grep -Fq '(mmio-read-software-gate . denied) (reason . owner-authorization-required)' \
      "$WORK/ledger-$mode.out" \
    || fail "ledger did not deny unbound MMIO for $mode"
  grep -Fq '(owner-approval . not-inferred)' "$WORK/ledger-$mode.out" \
    || fail "ledger inferred owner approval for $mode"
  grep -Fq '(physical-mmio . not-authorized)' "$WORK/ledger-$mode.out" \
    || fail "ledger omitted physical MMIO denial for $mode"
done
grep -Fq '(rights (write . none) (dispatch . none) (rm . none))' \
    "$WORK/ledger-allow-flag.out" \
  || fail 'ledger expanded rights outside the permitted boundary'
echo 'LEDGER-OWNER-AUTH-DENIED allow-flag=not-authorization'

step 'BAR flag mutation (I/O space is decoded, then restored)'
python3 - "$FIX/bus/pci/devices/0000:01:00.0/config" <<'PY'
import sys
p = sys.argv[1]
b = bytearray(open(p, 'rb').read())
b[0x10] = 0x01
open(p, 'wb').write(b)
PY
"$BIN" inventory --sysfs-root="$FIX" >"$WORK/io-bar.out"
grep -Fq '(bar0 (raw . 0xee000001) (space . io) (width . 32-bit) (prefetch . no)' "$WORK/io-bar.out" \
  || fail 'I/O-прапорець BAR0 не декодовано'
echo 'BAR0-SPACE-DECODE-OK io-space=observed physical-mmio=not-authorized'
python3 - "$FIX/bus/pci/devices/0000:01:00.0/config" <<'PY'
import sys
p = sys.argv[1]
b = bytearray(open(p, 'rb').read())
b[0x10] = 0x00
open(p, 'wb').write(b)
PY
echo 'BAR-FLAG-MUTATION-OK space=memory -> io -> memory'

step 'host PCI inventory (best effort, read-only)'
if [ -d /sys/bus/pci/devices/0000:01:00.0 ]; then
  "$BIN" inventory >"$WORK/host.out"
  grep -Fq '(vendor . 0x10de)' "$WORK/host.out" || fail 'host vendor mismatch'
  grep -Fq '(device . 0x1c82)' "$WORK/host.out" || fail 'host device mismatch'
  grep -Fq '(bdf . "0000:01:00.0")' "$WORK/host.out" || fail 'host BDF mismatch'
  echo 'HOST-INVENTORY-PASS evidence=runtime-proven'
else
  echo 'HOST-INVENTORY-SKIP reason=device-absent'
fi

echo "CAPABILITY-DRIVER-GATE-OK c11=yes layout=32/68/140 fail-closed=passed synthetic-sysfs=only physical-mmio=NOT-AUTHORIZED/NOT-RUN"
