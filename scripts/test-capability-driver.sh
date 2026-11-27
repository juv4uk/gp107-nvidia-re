#!/usr/bin/env bash
# capability-driver gate — style of the existing wsm-lazarus-derived gates:
# named steps, fail-closed, mutation negatives, code (not prose) inspection.
# Deterministic: all negative witnesses use a synthetic sysfs fixture.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="$ROOT/build/capability-driver/gp107ctl"
ASMBIN="$ROOT/build/capability-driver/gp107ctl-asm"
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


step 'MMIO gate (opt-in required before any mapping)'
if "$BIN" mmio-read --offset=0x0 --sysfs-root="$FIX" \
    >"$WORK/noopt.out" 2>"$WORK/noopt.err"; then
  fail 'MMIO-шлях спрацював без явного opt-in'
fi
grep -Fq 'MMIO-FAIL step=opt-in-required' "$WORK/noopt.err" \
  || fail 'нема названого negative-маркера opt-in-required'
echo 'NEGATIVE-MMIO-OPTIN-OK marker=step=opt-in-required'

step 'MMIO gate (bound kernel driver is refused)'
if "$BIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/bound.out" 2>"$WORK/bound.err"; then
  fail 'MMIO-шлях проігнорував bindings драйвера'
fi
grep -Fq 'MMIO-FAIL step=driver-bound code=16 driver=nvidia' "$WORK/bound.err" \
  || fail 'нема названого negative-маркера driver-bound'
echo 'NEGATIVE-MMIO-BOUND-OK marker=step=driver-bound'

step 'public C API enforces opt-in and driver binding independently of CLI'
cat > "$WORK/mmio-api-test.c" <<'EOF'
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "gp107_identity.h"
#include "gp107_mmio.h"

int main(int argc, char **argv)
{
    char err[256] = {0};
    uint32_t value = 0;
    int rc;

    if (argc != 2)
        return 64;

    rc = gp107_mmio_read32(argv[1], "0000:01:00.0", 0, 0,
                           &value, err, sizeof(err));
    if (rc != GP107_ERR_OPTIN || strstr(err, "opt-in-required") == NULL) {
        fprintf(stderr, "API-GATE-FAIL optin rc=%d err=%s\n", rc, err);
        return 1;
    }

    err[0] = '\0';
    rc = gp107_mmio_read32(argv[1], "0000:01:00.0", 1, 0,
                           &value, err, sizeof(err));
    if (rc != GP107_ERR_DRIVER_BOUND || strstr(err, "driver-bound") == NULL) {
        fprintf(stderr, "API-GATE-FAIL driver rc=%d err=%s\n", rc, err);
        return 1;
    }

    puts("MMIO-API-GATE-OK direct-call=guarded optin=required bound-driver=denied");
    return 0;
}
EOF
cc -std=c11 -Wall -Wextra -Werror -pedantic -I"$ROOT/lib" \
  "$WORK/mmio-api-test.c" "$ROOT/lib/gp107_identity.c" \
  "$ROOT/lib/gp107_mmio.c" -o "$WORK/mmio-api-test"
"$WORK/mmio-api-test" "$FIX"


step 'negative witness (undersized resource0 is refused)'
rm "$FIX/bus/pci/devices/0000:01:00.0/driver"
python3 - "$FIX/bus/pci/devices/0000:01:00.0/resource0" <<'PY'
import sys
p = sys.argv[1]
b = bytearray(open(p, 'rb').read())
open(p, 'wb').write(b[:64])
PY
if "$BIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/small.out" 2>"$WORK/small.err"; then
  fail 'MMIO-шлях прийняв resource0 менше за вікно'
fi
grep -Fq 'MMIO-FAIL step=bar0-size-too-small code=19 size=0x40' "$WORK/small.err" \
  || fail 'нема названого negative-маркера bar0-size-too-small'
python3 - "$FIX/bus/pci/devices/0000:01:00.0/resource0" <<'PY'
import sys
p = sys.argv[1]
open(p, 'wb').write(bytes((0xde, 0x10, 0x82, 0x1c)) + bytes(4092))
PY
echo 'NEGATIVE-BAR0-SIZE-OK marker=step=bar0-size-too-small'

step 'BAR0 offset outside the 4 KiB aperture is refused'
if "$BIN" mmio-read --offset=0x1000 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/offset.out" 2>"$WORK/offset.err"; then
  fail 'MMIO accepted offset outside the mapped window'
fi
grep -Fq 'MMIO-FAIL step=offset-out-of-window' "$WORK/offset.err" \
  || fail 'missing out-of-window failure marker'
echo 'NEGATIVE-MMIO-OFFSET-OK offset=0x1000 denied'


step 'MMIO read-only witness on synthetic resource0 (not hardware)'
"$BIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" >"$WORK/mmio.out"
for marker in \
  '(kind . gp107-mmio-read)' \
  '(offset . 0x0)' \
  '(value . 0x1c8210de)' \
  '(right . read-only)' \
  '(boot0 . unproven)' \
  '(summary . MMIO-READ-OK)'; do
  grep -Fq "$marker" "$WORK/mmio.out" || fail "нема маркера: $marker"
done
echo 'FIXTURE-MMIO-READ-OK scope=synthetic-resource0 hardware=NOT-RUN'

step 'negative witness (offset past one-page window is refused)'
if "$BIN" mmio-read --offset=0x1000 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/offset.out" 2>"$WORK/offset.err"; then
  fail 'MMIO-шлях прийняв offset поза вікном'
fi
grep -Fq 'MMIO-FAIL step=offset-out-of-window code=17 offset=0x1000' "$WORK/offset.err" \
  || fail 'нема названого negative-маркера offset-out-of-window'
echo 'NEGATIVE-MMIO-OFFSET-OK marker=step=offset-out-of-window'

step 'assembly read-only path equivalence (x86-64 only)'
if [ -x "$ASMBIN" ]; then
  "$ASMBIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" >"$WORK/mmio-asm.out"
  cmp -s "$WORK/mmio.out" "$WORK/mmio-asm.out" \
    || fail 'асемблерний read-only шлях відрізняється від C'
  "$BIN" capabilities --allow-mmio --sysfs-root="$FIX" >"$WORK/ledger-c.out"
  "$ASMBIN" capabilities --allow-mmio --sysfs-root="$FIX" >"$WORK/ledger-asm.out"
  cmp -s "$WORK/ledger-c.out" "$WORK/ledger-asm.out" \
    || fail 'ledger відрізняється між C і assembly builds'
  if command -v objdump >/dev/null 2>&1; then
    objdump -d "$ASMBIN" | grep -q 'lfence' \
      || fail 'у asm-примітиві немає lfence'
    echo 'ASM-STATIC-OK primitive=movl+lfence calling-convention=sysv-amd64'
  else
    echo 'ASM-STATIC-SKIP reason=objdump-absent'
  fi
  echo 'ASM-EQUIV-OK fixture-read-and-ledger identical-to-C hardware=NOT-RUN'
else
  echo 'ASM-EQUIV-SKIP reason=non-x86_64-host'
fi

step 'capability ledger (unbound + no opt-in stays deferred)'
"$BIN" capabilities --sysfs-root="$FIX" >"$WORK/ledger-deferred.out"
grep -Fq '(mmio-read-software-gate . deferred) (reason . opt-in-required)' "$WORK/ledger-deferred.out" \
  || fail 'ledger не лишив MMIO у deferred без opt-in'
echo 'LEDGER-DEFERRED-OK marker=step=opt-in-required'

step 'capability ledger (unbound + opt-in grants read-only only)'
"$BIN" capabilities --allow-mmio --sysfs-root="$FIX" >"$WORK/ledger-granted.out"
grep -Fq '(mmio-read-software-gate . granted) (reason . read-only-window)' "$WORK/ledger-granted.out" \
  || fail 'ledger не надав read-only MMIO після opt-in'
grep -Fq '(rights (write . none) (dispatch . none) (rm . none))' "$WORK/ledger-granted.out" \
  || fail 'ledger розширив права поза read-only'
echo 'LEDGER-GRANTED-OK write=none dispatch=none'

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
  echo 'HOST-INVENTORY-PASS evidence=sysfs-observation'
else
  echo 'HOST-INVENTORY-SKIP reason=device-absent'
fi

echo "CAPABILITY-DRIVER-GATE-OK c11=yes layout=32/68/140 fail-closed=passed synthetic-mmio=only asm=equiv-x86_64 hardware-mmio=NOT-AUTHORIZED/NOT-RUN"
