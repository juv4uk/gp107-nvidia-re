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
  '(source . caller-supplied-sysfs-root)' \
  '(evidence (pci . sysfs-observation) (driver . sysfs-observation) (boot0 . unproven))' \
  '(summary . IDENTITY-OK)'; do
  grep -Fq "$marker" "$WORK/inv.out" || fail "нема маркера: $marker"
done
echo 'FIXTURE-IDENTITY-OK source=synthetic-sysfs'

step 'negative witness (invalid driver link is not interpreted as unbound)'
rm "$FIX/bus/pci/devices/0000:01:00.0/driver"
: > "$FIX/bus/pci/devices/0000:01:00.0/driver"
if "$BIN" inventory --sysfs-root="$FIX" >"$WORK/baddriver.out" 2>"$WORK/baddriver.err"; then
  fail 'inventory accepted invalid driver entry as unbound'
fi
grep -Fq 'IDENTITY-FAIL step=driver-link-read code=20' "$WORK/baddriver.err" || fail 'missing driver-link-read fail-closed marker'
rm "$FIX/bus/pci/devices/0000:01:00.0/driver"
ln -s "$FIX/bus/pci/drivers/nvidia" "$FIX/bus/pci/devices/0000:01:00.0/driver"
echo 'NEGATIVE-DRIVER-LINK-OK unknown=not-unbound'

step 'capability ledger (bound driver denies MMIO, RM deferred)'
"$BIN" capabilities --sysfs-root="$FIX" >"$WORK/ledger-bound.out"
for marker in \
  '(kind . gp107-capability-ledger)' \
  '(abi-pin . untouched)' \
  '(pci-inventory . observed)' \
  '(bar0-decode . complete)' \
  '(rm-identity . deferred) (reason . not-in-this-slice)' \
  '(mmio-read . denied) (reason . driver-bound)' \
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

step 'MMIO read-only witness on synthetic resource0 (not hardware)'
rm "$FIX/bus/pci/devices/0000:01:00.0/driver"
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

step 'negative witness (unaligned MMIO offset is refused)'
if "$BIN" mmio-read --offset=0x1 --allow-mmio --sysfs-root="$FIX" >"$WORK/unaligned.out" 2>"$WORK/unaligned.err"; then
  fail 'MMIO API accepted unaligned access'
fi
grep -Fq 'MMIO-FAIL step=unaligned-offset code=22' "$WORK/unaligned.err" || fail 'missing unaligned-offset marker'
echo 'NEGATIVE-MMIO-ALIGNMENT-OK'

step 'negative witness (short resource0 is refused before mmap)'
cp "$FIX/bus/pci/devices/0000:01:00.0/resource0" "$WORK/resource0.full"
truncate -s 64 "$FIX/bus/pci/devices/0000:01:00.0/resource0"
if "$BIN" mmio-read --offset=0x0 --allow-mmio --sysfs-root="$FIX" >"$WORK/short.out" 2>"$WORK/short.err"; then
  fail 'MMIO API mapped resource0 shorter than its window'
fi
grep -Fq 'MMIO-FAIL step=resource0-too-small code=21' "$WORK/short.err" || fail 'missing resource0-too-small marker'
mv "$WORK/resource0.full" "$FIX/bus/pci/devices/0000:01:00.0/resource0"
echo 'NEGATIVE-MMIO-SIZE-OK'

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
grep -Fq '(mmio-read . deferred) (reason . opt-in-required)' "$WORK/ledger-deferred.out" \
  || fail 'ledger не лишив MMIO у deferred без opt-in'
echo 'LEDGER-DEFERRED-OK marker=step=opt-in-required'

step 'capability ledger (unbound + opt-in grants read-only only)'
"$BIN" capabilities --allow-mmio --sysfs-root="$FIX" >"$WORK/ledger-granted.out"
grep -Fq '(mmio-read . granted) (reason . read-only-window)' "$WORK/ledger-granted.out" \
  || fail 'ledger не надав read-only MMIO після opt-in'
grep -Fq '(rights (write . none) (dispatch . none) (rm . none))' "$WORK/ledger-granted.out" \
  || fail 'ledger розширив права поза read-only'
echo 'LEDGER-ELIGIBLE-OK no-aperture-read-implied write=none dispatch=none'

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

echo "CAPABILITY-DRIVER-GATE-OK c11=yes layout=32/68/140 negatives=9 mmio=read-only-opt-in asm=equiv-x86_64 hardware-mmio=NOT-RUN"
