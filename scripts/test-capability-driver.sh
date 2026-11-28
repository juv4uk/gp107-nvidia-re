#!/usr/bin/env bash
# capability-driver gate — style of the existing wsm-lazarus-derived gates:
# named steps, fail-closed, mutation negatives, code (not prose) inspection.
# Deterministic: all negative witnesses use a synthetic sysfs fixture.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="$ROOT/build/capability-driver/gp107ctl"
ASMBIN="$ROOT/build/capability-driver/gp107ctl-asm"
PASBIN="$ROOT/pascal/gp107ctl-pascal"
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
     lib/*.c lib/*.h pascal/gp107_*.pas >>"$WORK/fw.txt"; then
  cat "$WORK/fw.txt" >&2
  fail 'banned operation or claim in library code'
fi
if grep -R -F -q 'b5ec3211f6bd07fb7c4a5f704875892eff145b91' lib pascal; then
  fail 'authoritative ABI pin present in library code'
fi
if grep -nHE '\b(mmap|munmap|openat|FpMMap|FpMunmap|FpOpen)\s*\(' \
     lib/gp107_mmio.c pascal/gp107_mmio.pas >>"$WORK/fw-mmio.txt"; then
  cat "$WORK/fw-mmio.txt" >&2
  fail 'production MMIO API must not open resource0 or map an aperture'
fi
echo 'DRIVER-FIREWALL-OK banned-ops=absent pin-in-code=absent boot0-value=absent mapping-api=absent'

step 'compile C11 gate with warnings as errors'
make -C "$ROOT/lib" clean all >/dev/null
[ -x "$BIN" ] || fail 'no gp107ctl binary'
"$BIN" layout | grep -Fq 'LAYOUT-OK identity=32 binding=68 inventory=140' \
  || fail 'compile-time layout assertion output missing'
echo 'C11-COMPILE-OK werror=yes layout=32/68/140'

step 'compile Free Pascal capability driver (pinned 3.2.2)'
make -C "$ROOT/pascal" gp107ctl-pascal >/dev/null
[ -x "$PASBIN" ] || fail 'no Pascal gp107ctl binary'
[ "$("$PASBIN" layout)" = 'LAYOUT-OK identity=32 binding=68 inventory=140' ] \
  || fail 'Pascal compile-time layout assertion output missing'
echo 'FPC-COMPILE-OK version=3.2.2 layout=32/68/140'

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
"$PASBIN" inventory --sysfs-root="$FIX" >"$WORK/inv-pas.out"
cmp -s "$WORK/inv.out" "$WORK/inv-pas.out" \
  || fail 'Pascal inventory відрізняється від C'

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
"$PASBIN" capabilities --sysfs-root="$FIX" >"$WORK/ledger-bound-pas.out"
cmp -s "$WORK/ledger-bound.out" "$WORK/ledger-bound-pas.out" \
  || fail 'Pascal bound-driver ledger відрізняється від C'
echo 'LEDGER-BOUND-OK mmio=denied rm=deferred'
echo 'PASCAL-PARITY-OK inventory-and-ledger identical-to-C'

step 'negative witness (second matching card is ambiguous)'
mkdir -p "$FIX/bus/pci/devices/0000:02:00.0"
cp "$FIX/bus/pci/devices/0000:01:00.0"/{config,vendor,device,resource0} \
   "$FIX/bus/pci/devices/0000:02:00.0/"
if "$BIN" inventory --sysfs-root="$FIX" >"$WORK/two.out" 2>"$WORK/two.err"; then
  fail 'еміттер прийняв дві картки'
fi
grep -Fq 'IDENTITY-FAIL step=card-count' "$WORK/two.err" \
  || fail 'нема названого negative-маркера card-count'
if "$PASBIN" inventory --sysfs-root="$FIX" >"$WORK/two-pas.out" 2>"$WORK/two-pas.err"; then
  fail 'Pascal прийняв дві картки'
fi
cmp -s "$WORK/two.err" "$WORK/two-pas.err" \
  || fail 'Pascal card-count ERROR відрізняється від C'
rm -rf "$FIX/bus/pci/devices/0000:02:00.0"
echo 'NEGATIVE-CARD-COUNT-OK marker=step=card-count pascal=C'

step 'negative witness (unreadable PCI config is fatal)'
mv "$FIX/bus/pci/devices/0000:01:00.0/config" "$WORK/config.saved"
if "$BIN" inventory --sysfs-root="$FIX" >"$WORK/nocfg.out" 2>"$WORK/nocfg.err"; then
  fail 'еміттер прийняв картку без config'
fi
grep -Fq 'IDENTITY-FAIL step=pci-config-read' "$WORK/nocfg.err" \
  || fail 'нема названого negative-маркера pci-config-read'
if "$PASBIN" inventory --sysfs-root="$FIX" >"$WORK/nocfg-pas.out" 2>"$WORK/nocfg-pas.err"; then
  fail 'Pascal прийняв картку без config'
fi
cmp -s "$WORK/nocfg.err" "$WORK/nocfg-pas.err" \
  || fail 'Pascal pci-config-read ERROR відрізняється від C'
mv "$WORK/config.saved" "$FIX/bus/pci/devices/0000:01:00.0/config"
echo 'NEGATIVE-CONFIG-READ-OK marker=step=pci-config-read'

step 'negative witness (BDF assertion is enforced)'
if "$BIN" inventory --sysfs-root="$FIX" --expect-bdf=0000:09:00.0 \
    >"$WORK/bdf.out" 2>"$WORK/bdf.err"; then
  fail 'еміттер прийняв чужкий BDF'
fi
grep -Fq 'IDENTITY-FAIL step=bdf-mismatch' "$WORK/bdf.err" \
  || fail 'нема названого negative-маркера bdf-mismatch'
if "$PASBIN" inventory --sysfs-root="$FIX" --expect-bdf=0000:09:00.0 \
    >"$WORK/bdf-pas.out" 2>"$WORK/bdf-pas.err"; then
  fail 'Pascal прийняв чужий BDF'
fi
cmp -s "$WORK/bdf.err" "$WORK/bdf-pas.err" \
  || fail 'Pascal bdf-mismatch ERROR відрізняється від C'
echo 'NEGATIVE-BDF-OK marker=step=bdf-mismatch pascal=C'

step 'driver-link error is unknown, never unbound'
rm "$FIX/bus/pci/devices/0000:01:00.0/driver"
printf 'not-a-symlink\n' > "$FIX/bus/pci/devices/0000:01:00.0/driver"
if "$BIN" inventory --sysfs-root="$FIX" >"$WORK/baddriver.out" 2>"$WORK/baddriver.err"; then
  fail 'invalid driver entry was accepted as unbound'
fi
grep -Fq 'IDENTITY-FAIL step=driver-binding-read code=20' "$WORK/baddriver.err" \
  || fail 'driver-link read error did not fail closed'
if "$PASBIN" inventory --sysfs-root="$FIX" \
    >"$WORK/baddriver-pas.out" 2>"$WORK/baddriver-pas.err"; then
  fail 'Pascal прийняв не-symlink driver entry'
fi
cmp -s "$WORK/baddriver.err" "$WORK/baddriver-pas.err" \
  || fail 'Pascal driver-binding-read ERROR відрізняється від C'
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
if "$PASBIN" mmio-read --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/no-offset-pas.out" 2>"$WORK/no-offset-pas.err"; then
  fail 'Pascal MMIO CLI прийняв неявний offset'
fi
cmp -s "$WORK/no-offset.err" "$WORK/no-offset-pas.err" \
  || fail 'Pascal offset-required ERROR відрізняється від C'
echo 'NEGATIVE-MMIO-OFFSET-REQUIRED-OK pascal=C'

step 'MMIO gate (opt-in required before any mapping)'
if "$BIN" mmio-read --offset=0x0 --sysfs-root="$FIX" \
    >"$WORK/noopt.out" 2>"$WORK/noopt.err"; then
  fail 'MMIO-шлях спрацював без явного opt-in'
fi
grep -Fq 'MMIO-FAIL step=opt-in-required' "$WORK/noopt.err" \
  || fail 'нема названого negative-маркера opt-in-required'
if "$PASBIN" mmio-read --offset=0x0 --sysfs-root="$FIX" \
    >"$WORK/noopt-pas.out" 2>"$WORK/noopt-pas.err"; then
  fail 'Pascal MMIO-шлях спрацював без opt-in'
fi
cmp -s "$WORK/noopt.err" "$WORK/noopt-pas.err" \
  || fail 'Pascal opt-in ERROR відрізняється від C'
echo 'NEGATIVE-MMIO-OPTIN-OK marker=step=opt-in-required pascal=C'

step 'MMIO gate (bound kernel driver is refused)'
if "$BIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/bound.out" 2>"$WORK/bound.err"; then
  fail 'MMIO-шлях проігнорував bindings драйвера'
fi
grep -Fq 'MMIO-FAIL step=driver-bound code=16 driver=nvidia' "$WORK/bound.err" \
  || fail 'нема названого negative-маркера driver-bound'
if "$PASBIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/bound-pas.out" 2>"$WORK/bound-pas.err"; then
  fail 'Pascal ігнорував bindings драйвера'
fi
cmp -s "$WORK/bound.err" "$WORK/bound-pas.err" \
  || fail 'Pascal driver-bound ERROR відрізняється від C'
echo 'NEGATIVE-MMIO-BOUND-OK marker=step=driver-bound pascal=C'

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
cc -std=c11 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L \
  -I"$ROOT/lib" "$WORK/mmio-api-test.c" "$ROOT/lib/gp107_identity.c" \
  "$ROOT/lib/gp107_mmio.c" -o "$WORK/mmio-api-test"
"$WORK/mmio-api-test" "$FIX"

step 'public C API defers unbound reads without a source-proven safe offset'
rm "$FIX/bus/pci/devices/0000:01:00.0/driver"
cat > "$WORK/mmio-safe-offset-api-test.c" <<'EOF'
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "gp107_identity.h"
#include "gp107_mmio.h"

int main(int argc, char **argv)
{
    char err[256] = {0};
    uint32_t value = 0xdeadbeefu;
    int rc;

    if (argc != 2)
        return 64;
    rc = gp107_mmio_read32(argv[1], "0000:01:00.0", 1, 0,
                           &value, err, sizeof(err));
    if (rc != GP107_ERR_SAFE_OFFSET_UNPROVEN ||
        strstr(err, "read-safe-offset-unproven") == NULL || value != 0) {
        fprintf(stderr, "API-SAFE-OFFSET-FAIL rc=%d value=0x%x err=%s\\n",
                rc, value, err);
        return 1;
    }
    puts("MMIO-API-SAFE-OFFSET-OK direct-call=deferred map=absent");
    return 0;
}
EOF
cc -std=c11 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L \
  -I"$ROOT/lib" "$WORK/mmio-safe-offset-api-test.c" "$ROOT/lib/gp107_identity.c" \
  "$ROOT/lib/gp107_mmio.c" -o "$WORK/mmio-safe-offset-api-test"
"$WORK/mmio-safe-offset-api-test" "$FIX"
if "$PASBIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/safe-offset-pas.out" 2>"$WORK/safe-offset-pas.err"; then
  fail 'Pascal API allowed an unproven BAR0 read'
fi
grep -Fq 'MMIO-FAIL step=read-safe-offset-unproven code=21 offset=0x0' \
  "$WORK/safe-offset-pas.err" || fail 'Pascal safe-offset gate missing'
ln -s "$FIX/bus/pci/drivers/nvidia" "$FIX/bus/pci/devices/0000:01:00.0/driver"
echo 'MMIO-API-SAFE-OFFSET-OK C-and-Pascal direct API deferred'

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
if "$PASBIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/small-pas.out" 2>"$WORK/small-pas.err"; then
  fail 'Pascal прийняв resource0 менше за вікно'
fi
cmp -s "$WORK/small.err" "$WORK/small-pas.err" \
  || fail 'Pascal bar0-size-too-small ERROR відрізняється від C'
python3 - "$FIX/bus/pci/devices/0000:01:00.0/resource0" <<'PY'
import sys
p = sys.argv[1]
open(p, 'wb').write(bytes((0xde, 0x10, 0x82, 0x1c)) + bytes(4092))
PY
echo 'NEGATIVE-BAR0-SIZE-OK marker=step=bar0-size-too-small'

step 'safe-offset gate precedes all possible BAR access'
grep -Fq 'read-safe-offset-unproven' "$ROOT/lib/gp107_mmio.c" \
  || fail 'C safe-offset refusal missing'
grep -Fq 'read-safe-offset-unproven' "$ROOT/pascal/gp107_mmio.pas" \
  || fail 'Pascal safe-offset refusal missing'
echo 'MMIO-RESOURCE0-ACCESS-ABSENT-OK'


step 'MMIO refuses an unaligned 32-bit offset'
if "$BIN" mmio-read --offset=0x2 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/unaligned.out" 2>"$WORK/unaligned.err"; then
  fail 'MMIO accepted unaligned offset'
fi
grep -Fq 'MMIO-FAIL step=offset-unaligned' "$WORK/unaligned.err" \
  || fail 'missing unaligned-offset failure marker'
if "$PASBIN" mmio-read --offset=0x2 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/unaligned-pas.out" 2>"$WORK/unaligned-pas.err"; then
  fail 'Pascal прийняв невирівняний offset'
fi
cmp -s "$WORK/unaligned.err" "$WORK/unaligned-pas.err" \
  || fail 'Pascal offset-unaligned ERROR відрізняється від C'
echo 'NEGATIVE-MMIO-ALIGNMENT-OK offset=0x2 denied pascal=C'


step 'BAR0 offset outside the 4 KiB aperture is refused'
if "$BIN" mmio-read --offset=0x1000 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/offset.out" 2>"$WORK/offset.err"; then
  fail 'MMIO accepted offset outside the mapped window'
fi
grep -Fq 'MMIO-FAIL step=offset-out-of-window' "$WORK/offset.err" \
  || fail 'missing out-of-window failure marker'
if "$PASBIN" mmio-read --offset=0x1000 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/offset-pas.out" 2>"$WORK/offset-pas.err"; then
  fail 'Pascal прийняв offset поза вікном'
fi
cmp -s "$WORK/offset.err" "$WORK/offset-pas.err" \
  || fail 'Pascal offset-out-of-window ERROR відрізняється від C'
echo 'NEGATIVE-MMIO-OFFSET-OK offset=0x1000 denied pascal=C'


step 'MMIO refuses every valid-looking offset until safe register semantics are proven'
if "$BIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/mmio.out" 2>"$WORK/mmio.err"; then
  fail 'C API returned a BAR0 value without a proven safe register'
fi
grep -Fq 'MMIO-FAIL step=read-safe-offset-unproven code=21 offset=0x0' \
  "$WORK/mmio.err" || fail 'C safe-offset refusal marker missing'
if "$PASBIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/mmio-pas.out" 2>"$WORK/mmio-pas.err"; then
  fail 'Pascal API returned a BAR0 value without a proven safe register'
fi
cmp -s "$WORK/mmio.err" "$WORK/mmio-pas.err" \
  || fail 'Pascal safe-offset ERROR differs from C'
echo 'NEGATIVE-SAFE-OFFSET-UNPROVEN-OK pascal=C'

step 'negative witness (offset past one-page window is refused)'
if "$BIN" mmio-read --offset=0x1000 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/offset.out" 2>"$WORK/offset.err"; then
  fail 'MMIO-шлях прийняв offset поза вікном'
fi
grep -Fq 'MMIO-FAIL step=offset-out-of-window code=17 offset=0x1000' "$WORK/offset.err" \
  || fail 'нема названого negative-маркера offset-out-of-window'
echo 'NEGATIVE-MMIO-OFFSET-OK marker=step=offset-out-of-window'

step 'assembly leaf is inspected statically only; public API never calls it'
if [ -x "$ASMBIN" ]; then
  "$BIN" capabilities --allow-mmio --sysfs-root="$FIX" >"$WORK/ledger-c.out"
  "$ASMBIN" capabilities --allow-mmio --sysfs-root="$FIX" >"$WORK/ledger-asm.out"
  cmp -s "$WORK/ledger-c.out" "$WORK/ledger-asm.out" \
    || fail 'ledger differs between C and assembly-linked builds'
  if command -v objdump >/dev/null 2>&1; then
    objdump -d "$ASMBIN" >"$WORK/asm-dis.txt"
    grep -A8 '<gp107_mmio_load32_asm>:' "$WORK/asm-dis.txt" | grep -q 'lfence' \
      || fail 'isolated asm leaf has no lfence'
    echo 'ASM-STATIC-OK primitive=movl+lfence api-call=absent'
  else
    echo 'ASM-STATIC-SKIP reason=objdump-absent'
  fi
  echo 'ASM-NO-HARDWARE-PATH-OK ledger-only=yes'
else
  echo 'ASM-STATIC-SKIP reason=non-x86_64-host'
fi

step 'capability ledger (unbound + no opt-in stays deferred)'
"$BIN" capabilities --sysfs-root="$FIX" >"$WORK/ledger-deferred.out"
grep -Fq '(mmio-read-software-gate . deferred) (reason . opt-in-required)' "$WORK/ledger-deferred.out" \
  || fail 'ledger не лишив MMIO у deferred без opt-in'
"$PASBIN" capabilities --sysfs-root="$FIX" >"$WORK/ledger-deferred-pas.out"
cmp -s "$WORK/ledger-deferred.out" "$WORK/ledger-deferred-pas.out" \
  || fail 'Pascal deferred-ledger відрізняється від C'
echo 'LEDGER-DEFERRED-OK marker=step=opt-in-required pascal=C'

step 'capability ledger (unbound + opt-in remains deferred until safe offset proof)'
"$BIN" capabilities --allow-mmio --sysfs-root="$FIX" >"$WORK/ledger-safe-offset.out"
grep -Fq '(mmio-read-software-gate . deferred) (reason . read-safe-offset-unproven)' "$WORK/ledger-safe-offset.out" \
  || fail 'ledger granted MMIO without a source-proven safe register'
grep -Fq '(owner-approval . not-inferred)' "$WORK/ledger-safe-offset.out" \
  || fail 'ledger inferred owner approval'
grep -Fq '(physical-mmio . not-authorized)' "$WORK/ledger-safe-offset.out" \
  || fail 'ledger authorized physical MMIO'
grep -Fq '(rights (write . none) (dispatch . none) (rm . none))' "$WORK/ledger-safe-offset.out" \
  || fail 'ledger expanded rights'
"$PASBIN" capabilities --allow-mmio --sysfs-root="$FIX" >"$WORK/ledger-safe-offset-pas.out"
cmp -s "$WORK/ledger-safe-offset.out" "$WORK/ledger-safe-offset-pas.out" \
  || fail 'Pascal safe-offset ledger differs from C'
echo 'LEDGER-SAFE-OFFSET-DEFERRED-OK owner-approval=not-inferred pascal=C'

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
if "$BIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/io-mmio.out" 2>"$WORK/io-mmio.err"; then
  fail 'MMIO accepted an I/O-space BAR0'
fi
grep -Fq 'MMIO-FAIL step=bar0-not-memory' "$WORK/io-mmio.err" \
  || fail 'missing I/O-space BAR0 denial'
"$PASBIN" inventory --sysfs-root="$FIX" >"$WORK/io-bar-pas.out"
cmp -s "$WORK/io-bar.out" "$WORK/io-bar-pas.out" \
  || fail 'Pascal BAR-flag decoding відрізняється від C'
if "$PASBIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" \
    >"$WORK/io-mmio-pas.out" 2>"$WORK/io-mmio-pas.err"; then
  fail 'Pascal прийняв I/O-space BAR0'
fi
cmp -s "$WORK/io-mmio.err" "$WORK/io-mmio-pas.err" \
  || fail 'Pascal bar0-not-memory ERROR відрізняється від C'
echo 'NEGATIVE-BAR0-SPACE-OK io-space=denied pascal=C'
python3 - "$FIX/bus/pci/devices/0000:01:00.0/config" <<'PY'
import sys
p = sys.argv[1]
b = bytearray(open(p, 'rb').read())
b[0x10] = 0x00
open(p, 'wb').write(b)
PY
echo 'BAR-FLAG-MUTATION-OK space=memory -> io -> memory'

step 'host PCI inventory (best effort, only on the expected GP107 BDF)'
HOST_BDF=/sys/bus/pci/devices/0000:01:00.0
if [ ! -d "$HOST_BDF" ]; then
  echo 'HOST-INVENTORY-SKIP reason=expected-bdf-absent'
elif [ ! -r "$HOST_BDF/vendor" ] || [ ! -r "$HOST_BDF/device" ]; then
  echo 'HOST-INVENTORY-SKIP reason=expected-bdf-identity-unreadable'
else
  HOST_VENDOR=$(tr -d '\n' <"$HOST_BDF/vendor")
  HOST_DEVICE=$(tr -d '\n' <"$HOST_BDF/device")
  if [ "$HOST_VENDOR" != "0x10de" ] || [ "$HOST_DEVICE" != "0x1c82" ]; then
    echo "HOST-INVENTORY-SKIP reason=not-target-gp107 vendor=$HOST_VENDOR device=$HOST_DEVICE"
  else
    "$BIN" inventory >"$WORK/host.out"
    grep -Fq '(vendor . 0x10de)' "$WORK/host.out" || fail 'host vendor mismatch after target identity match'
    grep -Fq '(device . 0x1c82)' "$WORK/host.out" || fail 'host device mismatch after target identity match'
    grep -Fq '(bdf . "0000:01:00.0")' "$WORK/host.out" || fail 'host BDF mismatch after target identity match'
    "$PASBIN" inventory >"$WORK/host-pas.out"
    cmp -s "$WORK/host.out" "$WORK/host-pas.out" \
      || fail 'Pascal host inventory відрізняється від C'
    echo 'HOST-INVENTORY-PASS evidence=runtime-proven pascal=C'
  fi
fi

echo "CAPABILITY-DRIVER-GATE-OK c11=yes fpc=3.2.2 layout=32/68/140 fail-closed=passed mmio=deferred safe-offset=unproven pascal=C-parity hardware-mmio=NOT-AUTHORIZED/NOT-RUN"
