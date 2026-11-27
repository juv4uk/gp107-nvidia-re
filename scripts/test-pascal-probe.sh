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
EXPECTED_VENDOR=0x10de
EXPECTED_DEVICE=0x1c82
EXPECTED_BDF=0000:01:00.0
EXPECTED_DRIVER=580.196.11
EXPECTED_BLOCK=8000000
EXPECTED_BAR0=0x00000000ee000000
BIN="pascal/01_min_cuinit"
BAR_BIN="pascal/02_bar_identity"
RM_BIN="pascal/03_rm_arch_info"
WORK=$(mktemp -d)
OUT="$WORK/out"
BAR_OUT="$WORK/bar.out"
RM_OUT="$WORK/rm.out"
UNSUPPORTED_EXIT=0

trap '_rc=$?; rm -rf "$WORK"; if [ "$_rc" -ne 0 ] && [ "$UNSUPPORTED_EXIT" -eq 0 ]; then
         echo "PASCAL-PROBE-FAIL крок=\"$BASH_COMMAND\" код=$_rc" >&2
       fi' EXIT

fail() { echo "PASCAL-PROBE-FAIL: $*" >&2; exit 1; }
unsupported() {
  UNSUPPORTED_EXIT=1
  echo "PASCAL-PROBE-UNSUPPORTED reason=$*" >&2
  exit 3
}
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

# Check the RM probe's fail-closed valid-card invariant in executable Pascal
# code, not in prose in Pascal comments.
check_valid_cards_gate() {
  local body
  body=$(strip_pascal_comments "$1")
  printf '%s\n' "$body" | grep -Fq 'valid_cards <> 1' || return 1
  printf '%s\n' "$body" | grep -Fq 'ambiguous valid_cards=' || return 1
}

# 1) Toolchain pin. wsm-lazarus records 3.2.2 as the baseline and 3.2.4 as
#    an unmeasured source-tag candidate; mixing them would invalidate
#    byte-level evidence. A different toolchain/host is UNSUPPORTED (exit 3),
#    never a green gate and never a silent relaxation of the pin.
step "FPC pin ($FPC_EXPECTED)"
command -v "$FPC_BIN" >/dev/null 2>&1 || unsupported "fpc-missing:$FPC_BIN"
got="$("$FPC_BIN" -iV)"
[ "$got" = "$FPC_EXPECTED" ] || unsupported "fpc-version=$got expected=$FPC_EXPECTED"
[ "$("$FPC_BIN" -iTP)" = 'x86_64' ] || unsupported "fpc-target=$("$FPC_BIN" -iTP) expected=x86_64"
[ "$("$FPC_BIN" -iTO)" = 'linux' ] || unsupported "fpc-os=$("$FPC_BIN" -iTO) expected=linux"
[ "$(uname -m)" = 'x86_64' ] || unsupported "host-arch=$(uname -m) expected=x86_64"
for tool in make readelf file nm mktemp awk grep sed tr head readlink; do
  command -v "$tool" >/dev/null 2>&1 || unsupported "tool-missing:$tool"
done

# 1b) Host profile. This repository is pinned to the measured R580/GP107 box.
#     A different GPU, BDF, BAR0, driver or memory block is reported as an
#     incompatible host BEFORE any runtime assertion; it is not promoted to
#     a passing witness.
step 'host profile (R580 / GP107 / 10de:1c82)'
bdf_count=0
target_bdf=''
for cfg in /sys/bus/pci/devices/*/config; do
  [ -e "$cfg" ] || continue
  devdir=${cfg%/config}
  [ -r "$devdir/vendor" ] && [ -r "$devdir/device" ] || continue
  pci_v=$(tr -d '[:space:]' <"$devdir/vendor")
  pci_d=$(tr -d '[:space:]' <"$devdir/device")
  if [ "$pci_v" = "$EXPECTED_VENDOR" ] && [ "$pci_d" = "$EXPECTED_DEVICE" ]; then
    bdf_count=$((bdf_count + 1))
    target_bdf=${devdir##*/}
  fi
done
[ "$bdf_count" -eq 1 ] || unsupported "gpu-count=$bdf_count target=$EXPECTED_VENDOR:$EXPECTED_DEVICE"
[ "$target_bdf" = "$EXPECTED_BDF" ] || unsupported "gpu-bdf=$target_bdf expected=$EXPECTED_BDF"
target_dir="/sys/bus/pci/devices/$target_bdf"
[ -e "$target_dir/resource0" ] || unsupported 'resource0-missing'
[ -r /proc/driver/nvidia/version ] || unsupported 'nvidia-version-missing'
drv=$(sed -n 's/.*Kernel Module  \([0-9.]*\).*/\1/p' /proc/driver/nvidia/version | head -1)
[ "$drv" = "$EXPECTED_DRIVER" ] || unsupported "driver=$drv expected=$EXPECTED_DRIVER"
[ "$(readlink -f "$target_dir/driver")" = '/sys/bus/pci/drivers/nvidia' ]   || unsupported 'driver-bind-not-nvidia'
[ -r /sys/devices/system/memory/block_size_bytes ] || unsupported 'block-size-missing'
blk=$(tr -d '[:space:]' < /sys/devices/system/memory/block_size_bytes)
[ "$blk" = "$EXPECTED_BLOCK" ] || unsupported "block-size=$blk expected=$EXPECTED_BLOCK"
bar0=$(awk 'NR == 1 { print $1 }' "$target_dir/resource")
[ "$bar0" = "$EXPECTED_BAR0" ] || unsupported "bar0=$bar0 expected=$EXPECTED_BAR0"
[ -c /dev/nvidiactl ] || unsupported 'nvidiactl-missing'
echo "HOST-PROFILE-OK bdf=$target_bdf driver=$drv block=$blk bar0=$bar0"

# 2) Firewall: no GUI, no libc link directive, no thread manager dependency.
#    BaseUnix wrappers are syscall imports only where FPC_SYSC_* exists;
#    the final ELF check below is the real proof of libc-freedom.
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
check_valid_cards_gate pascal/03_rm_arch_info.pas \
  || fail 'нема статичного fail-closed gate valid_cards <> 1 або маркера ambiguous valid_cards=N'

step 'negative witness (valid_cards static gate is not vacuous)'
mut_src="$WORK/03_rm_arch_info.no-gate.pas"
sed -e '/valid_cards <> 1/d' -e '/ambiguous valid_cards=/d' \
  pascal/03_rm_arch_info.pas >"$mut_src"
if check_valid_cards_gate "$mut_src"; then
  fail 'мутований source без gate пройшов статичну перевірку'
fi
echo 'VALID-CARDS-GATE-NEGATIVE-OK removed-gate-detected=yes'

grep -Fq 'GpuDevicePath(card)' pascal/03_rm_arch_info.pas \
  || fail 'шлях GPU-пристрою не похідний від minor_number'

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
#    failure here is a hard failure, never a guessed arch value. Explicit
#    NV_ESC_RM_FREE must be observed in reverse creation order; fd close is
#    NOT claimed to free RM objects.
step 'RM lifecycle firewall (explicit NV_ESC_RM_FREE, reverse order)'
grep -Fq 'RmIOC(NV_ESC_RM_FREE, SizeOf(free_pars))' \
  pascal/03_rm_arch_info.pas || fail 'нема явного NV_ESC_RM_FREE'
order=$(strip_pascal_comments pascal/03_rm_arch_info.pas \
        | grep -F 'FreeRmObject(' \
        | grep -oE "'NV20_SUBDEVICE_0'|'NV01_DEVICE_0'|'NV01_ROOT_CLIENT'" \
        | tr -d "'" | paste -sd, -)
[ "$order" = 'NV20_SUBDEVICE_0,NV01_DEVICE_0,NV01_ROOT_CLIENT' ] \
  || fail "порядок звільнення не зворотний: $order"

step 'runtime witness (03_rm_arch_info)'
timeout 20s env -u WSM_RM_FAIL_STEP "./$RM_BIN" >"$RM_OUT"
cat "$RM_OUT"
for marker in \
  'NV_ESC_CARD_INFO target   : 10DE:1C82 @ 0000:01:00.0 minor=0' \
  'GPU device node           : /dev/nvidia0' \
  'GPU_ATTACH_IDS            : gpu=0x100 status=0 deviceInstance=0 subDeviceInstance=0' \
  'NV2080_CTRL_MC_GET_ARCH_INFO: arch=0x00000130 impl=0x00000007 rev=0x000000A1 subrev=0x02' \
  'BOOT0: UNPROVEN (RM arch info is a separate channel)' \
  'RM-ARCH-OK' \
  'RM-FREE-OK object=NV20_SUBDEVICE_0 status=0' \
  'RM-FREE-OK object=NV01_DEVICE_0 status=0' \
  'RM-FREE-OK object=NV01_ROOT_CLIENT status=0' \
  'RM-CLEANUP-COMPLETE objects=3'; do
  grep -Fq "$marker" "$RM_OUT" || fail "нема маркера: $marker"
done

step 'negative witness (partial-failure RM cleanup)'
for spec in after_alloc_client:1 after_alloc_device:2 after_alloc_subdev:3; do
  inj=${spec%%:*}
  expected=${spec##*:}
  inj_out="$WORK/rm-$inj.out"
  if timeout 20s env WSM_RM_FAIL_STEP="$inj" "./$RM_BIN" >"$inj_out" 2>&1; then
    fail "інʼєкція $inj не завершилася відмовою"
  fi
  cat "$inj_out"
  grep -Fq "RM-ARCH-FAIL step=INJECT-$inj injected=fail" "$inj_out" \
    || fail "нема маркера інʼєкції: $inj"
  grep -Fq "RM-CLEANUP-COMPLETE objects=$expected" "$inj_out" \
    || fail "частковий cleanup для $inj звільнив не $expected обʼєктів"
  if grep -Fq 'RM-CLEANUP-FAIL' "$inj_out"; then
    fail "cleanup для $inj містить RM-CLEANUP-FAIL"
  fi
done

# 9) Binary proof for ALL probes. Three distinct claims are checked apart:
#    (a) static ELF: no PT_INTERP dynamic loader;
#    (b) no dynamic dependencies: no dynamic section / DT_NEEDED;
#    (c) no libc: no libc.so / GLIBC_* / __libc_start_main strings or symbols.
#    A static binary that embeds libc would pass (a)+(b) but fail (c).
step 'binary proof 1/3 (static ELF, no PT_INTERP)'
for b in "$BIN" "$BAR_BIN" "$RM_BIN"; do
  file "$b" | grep -Fq 'statically linked' || fail "$b не статичний"
  readelf -h "$b" | grep -Fq 'Advanced Micro Devices X86-64'     || fail "$b не x86-64 ELF"
  if readelf -lW "$b" | grep -q 'INTERP'; then
    fail "$b має PT_INTERP (динамічний завантажник)"
  fi
done

step 'binary proof 2/3 (no dynamic dependencies)'
for b in "$BIN" "$BAR_BIN" "$RM_BIN"; do
  if readelf -SW "$b" | grep -q '\.dynamic'; then
    fail "$b має розділ .dynamic"
  fi
  if readelf -lW "$b" | grep -q 'DYNAMIC'; then
    fail "$b має сегмент PT_DYNAMIC"
  fi
  if readelf -d "$b" 2>/dev/null | grep -q 'NEEDED'; then
    fail "$b має DT_NEEDED"
  fi
done

step 'binary proof 3/3 (no libc)'
for b in "$BIN" "$BAR_BIN" "$RM_BIN"; do
  if readelf --dyn-syms "$b" 2>/dev/null \
     | grep -Eq 'GLIBC_|__libc_start_main|libc\.so'; then
    fail "$b містить libc-символи"
  fi
  if grep -aEq 'libc\.so(\.[0-9]+)*|GLIBC_[0-9.]+|__libc_start_main' "$b"; then
    fail "$b містить libc-рядки"
  fi
done

echo 'BINARY-PROOF-OK elf-static=yes no-dynamic-deps=yes libc-dynamic=no'
echo 'PASCAL-PROBE-GATE-OK fpc='"$got"' static=yes no-libc=yes gpu=10de:1c82 bar0=fail-closed rmarch=runtime-proven boot0=unproven'
