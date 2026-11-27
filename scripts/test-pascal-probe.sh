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
BAR_BIN="pascal/02_bar_identity"
RM_BIN="pascal/03_rm_arch_info"
WORK=$(mktemp -d)
OUT="$WORK/out"
BAR_OUT="$WORK/bar.out"
RM_OUT="$WORK/rm.out"

trap '_rc=$?; rm -rf "$WORK"; if [ "$_rc" -ne 0 ]; then
         echo "PASCAL-PROBE-FAIL крок=\"$BASH_COMMAND\" код=$_rc" >&2
       fi' EXIT

fail() { echo "PASCAL-PROBE-FAIL: $*" >&2; exit 1; }
step() { printf '== %s\n' "$*"; }

# Firewalls must inspect CODE, not prose in Pascal { } / // comments.
strip_pascal_comments() {
  awk '
  {
    line = $0
    while (match(line, /\{[^\}]*\}/))
      line = substr(line, 1, RSTART-1) substr(line, RSTART+RLENGTH)
    if (inblock) {
      i = index(line, "}")
      if (i > 0) { inblock = 0; line = substr(line, i+1) } else next
    }
    i = index(line, "{")
    if (i > 0) { inblock = 1; line = substr(line, 1, i-1) }
    sub(/\/\/.*/, "", line)
    print line
  }' "$1"
}

# 1) Toolchain pin. wsm-lazarus records 3.2.2 as the baseline and 3.2.4 as
#    an unmeasured source-tag candidate; mixing them would invalidate
#    byte-level evidence.
step "FPC pin ($FPC_EXPECTED)"
command -v "$FPC_BIN" >/dev/null 2>&1 || fail "нема $FPC_BIN"
got="$("$FPC_BIN" -iV)"
[ "$got" = "$FPC_EXPECTED" ] || fail "FPC pin: очікували $FPC_EXPECTED, маємо $got"

# 2) Firewall: no GUI, no libc link directive, no thread manager dependency.
#    BaseUnix wrappers are syscall imports only where FPC_SYSC_* exists;
#    the final ELF check below proves absence of dynamic dependencies, not static libc absence.
step 'firewall (no LCL / libc link / cthreads)'
if grep -nHEn '(Forms|Controls|LCL|Interfaces|cthreads)|\{\$linklib[[:space:]]+c\}|external[[:space:]]+['\''"]c['\''"]' \
      pascal/*.pas; then
  fail 'заборонена залежність у Pascal-дисках'
fi

# 3) BAR firewall. The BAR probe must not contain a writable mapping or a
#    writable fd. PROT_WRITE / MAP_FIXED / O_RDWR are compile-time crimes here,
#    exactly like LCL in wsm-lazarus's no-LCL firewall.
step 'BAR firewall (PROT_READ|MAP_SHARED, O_RDONLY only)'
if strip_pascal_comments pascal/02_bar_identity.pas \
   | grep -nE 'PROT_WRITE|MAP_FIXED|O_RDWR|FpWrite|pwrite'; then
  fail 'BAR-пробник містить writable шлях'
fi
grep -Fq 'FpMMap(nil, MMIO_PAGE_BYTES, PROT_READ, MAP_SHARED, fd, 0)' \
  pascal/02_bar_identity.pas || fail 'нема явного PROT_READ|MAP_SHARED FpMMap'
grep -Fq 'FpOpen(PChar(path), O_RDONLY or O_CLOEXEC, 0)' \
  pascal/02_bar_identity.pas || fail 'resource0 відкрито не O_RDONLY'

# 3b) RM firewall. The GPU node must be derived from NV_ESC_CARD_INFO.
step 'RM firewall (dynamic GPU node, unique GP107)'
if strip_pascal_comments pascal/03_rm_arch_info.pas \
   | grep -nE '/dev/nvidia0'; then
  fail 'RM-зонд містить хардкодований /dev/nvidia0'
fi
grep -Fq 'SelectTargetCard(card, matches, valid_cards)' \
  pascal/03_rm_arch_info.pas || fail 'нема вибору цільової картки через nv_device'
grep -Fq 'GpuDevicePath(card)' pascal/03_rm_arch_info.pas \
  || fail 'шлях GPU-пристрою не похідний від minor_number'
grep -Fq 'ReadPciConfig(card, pci)' pascal/03_rm_arch_info.pas \
  || fail 'нема незалежного PCI config cross-check'
grep -Fq 'rm_gpu_count <> 1' pascal/03_rm_arch_info.pas \
  || fail 'нема fail-closed перевірки неоднозначного RM GPU-ID list'

# 4) Clean build: compile-time SizeOf asserts live in nv_abi.pas.
step 'clean build'
make -C pascal clean >/dev/null
make -C pascal all

# 5) Negative witness: the SizeOf assertion must actually fail the build.
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

# 5b) Same proof for the RM unit: its SizeOf asserts must not be vacuous.
step 'negative witness (RM ABI assert is not vacuous)'
mkdir -p "$WORK/neg2"
cp pascal/nv_abi.pas pascal/nv_rm.pas "$WORK/neg2/"
sed -i 's/SizeOf(Tnvos54)             = 32/SizeOf(Tnvos54)             = 33/' \
  "$WORK/neg2/nv_rm.pas"
printf 'program neg2;\n{$mode objfpc}\nuses nv_rm;\nbegin WriteLn(AbiRmProven); end.\n' \
  > "$WORK/neg2/neg2.pas"
if "$FPC_BIN" -O2 -Fu"$WORK/neg2" -FU"$WORK/neg2" -o"$WORK/neg2/neg2" \
   "$WORK/neg2/neg2.pas" >"$WORK/neg2.log" 2>&1; then
  fail 'negative witness RM зібрався: RM SizeOf-перевірка нічого не перевіряє'
fi
grep -Fq 'Upper bound of range is less than lower bound' "$WORK/neg2.log" \
  || fail 'negative witness RM впав з іншої причини (див. лог)'

# 6) Runtime witness: the no-libcuda probe.
step 'runtime witness (01_min_cuinit)'
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

# 7) Runtime witness: two independent identities must agree, and BAR0 must
#    fail closed. The unprivileged run must stop at OPEN_DENIED: no mmap was
#    attempted and EACCES proves only that this uid cannot open resource0.
#    The optional root witness exercises MMAP_DENIED separately.
step 'runtime witness (02_bar_identity)'
timeout 20s "./$BAR_BIN" >"$BAR_OUT"
cat "$BAR_OUT"
for marker in \
  'NV_ESC_CARD_INFO identity : 10DE:1C82 @ 0000:01:00.0' \
  'PCI-CONFIG identity       : 10DE:1C82 BAR0=0xEE000000' \
  'CROSS-CHECK-OK: pci-config == NV_ESC_CARD_INFO' \
  'resource0 open            : DENIED errno=13 (EACCES)' \
  'BAR0-STATE: OPEN_DENIED' \
  'BOOT0: UNPROVEN (open denied; MMIO not attempted)' \
  'G1-FAIL-CLOSED-OK'; do
  grep -Fq "$marker" "$BAR_OUT" || fail "нема маркера: $marker"
done
if grep -Fq 'BAR0-STATE: MMAP_DENIED' "$BAR_OUT"; then
  fail 'open не відбувся, а звіт стверджує mmap-відмову'
fi
if grep -Eq 'BAR0 exclusively|owns BAR0' "$BAR_OUT"; then
  fail 'EACCES перетворено на необґрунтоване твердження про володіння BAR0'
fi

# 8) Runtime witness: RM arch info is a SEPARATE channel from BOOT0/MMIO.
#    The GPU fd must stay open and GPU_ATTACH_IDS must succeed first; a
#    failure here is a hard failure, never a guessed arch value.
step 'runtime witness (03_rm_arch_info)'
timeout 20s "./$RM_BIN" >"$RM_OUT"
cat "$RM_OUT"
if ! grep -Eq '^NV_ESC_CARD_INFO target[[:space:]]+: 10DE:1C82 @ [[:xdigit:]]{4}:[[:xdigit:]]{2}:[[:xdigit:]]{2}[.][0-7] minor=[0-9]+$' "$RM_OUT"; then
  fail 'NV_ESC_CARD_INFO did not identify one GP107 with a PCI BDF and minor'
fi
if ! grep -Eq '^GPU device node[[:space:]]+: /dev/nvidia[0-9]+$' "$RM_OUT"; then
  fail 'GPU device node was not derived from the selected minor'
fi
grep -Fq 'PCI config identity       : 10DE:1C82 BAR0=0xEE000000' "$RM_OUT" \
  || fail 'PCI config identity cross-check marker is missing'
grep -Fq 'RM GPU candidate count   : 1' "$RM_OUT" \
  || fail 'RM GPU-ID list was not uniquely resolved'
for marker in \
  'GPU_ATTACH_IDS            : gpu=0x100 status=0 deviceInstance=0 subDeviceInstance=0' \
  'NV2080_CTRL_MC_GET_ARCH_INFO: arch=0x00000130 impl=0x00000007 rev=0x000000A1 subrev=0x02' \
  'BOOT0: UNPROVEN (RM arch info is a separate channel)' \
  'RM-ARCH-OK'; do
  grep -Fq "$marker" "$RM_OUT" || fail "нема маркера: $marker"
done

# 9) Binary proof for ALL probes: static ELF, no DT_NEEDED entries.
step 'binary proof'
for b in "$BIN" "$BAR_BIN" "$RM_BIN"; do
  file "$b" | grep -q 'statically linked' || fail "$b не статичний"
  if readelf -d "$b" 2>/dev/null | grep -q 'NEEDED'; then
    fail "$b має динамічні залежності (DT_NEEDED)"
  fi
done

echo 'PASCAL-PROBE-GATE-OK fpc='"$got"' static=yes no-dynamic-deps=yes gpu=10de:1c82 bar0=fail-closed rmarch=runtime-proven boot0=unproven'
