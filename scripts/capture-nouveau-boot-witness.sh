#!/usr/bin/env bash
# capture-nouveau-boot-witness.sh — одноразовий read-only збір свідків у сесії
# з активним nouveau. НЕ змінює boot, драйвер, firmware чи конфігурацію.
# НЕ запускає PR #21 executable і не виконує MMIO-читань/записів.
#
# Використання (вже в сесії Nouveau, без root):
#   bash scripts/capture-nouveau-boot-witness.sh
#   BOOT_OUT=/tmp/opencode/nouveau-witness bash scripts/capture-nouveau-boot-witness.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${BOOT_OUT:-/tmp/opencode/nouveau-witness}"
BDF="${BOOT_BDF:-0000:01:00.0}"
ICD="${BOOT_ICD:-/usr/share/vulkan/icd.d/nouveau_icd.json}"

step() { printf '== %s\n' "$*"; }
fail() { echo "NOUVEAU-WITNESS-FAIL: $*" >&2; exit 1; }
record() { printf '%s\n' "$*" >>"$OUT/00-status.txt"; }

trap '_rc=$?; if [ "$_rc" -ne 0 ]; then
         echo "NOUVEAU-WITNESS-FAIL крок=\"$BASH_COMMAND\" код=$_rc" >&2
       fi' EXIT

step 'output directory (fresh)'
[ ! -e "$OUT" ] || fail "каталог уже існує, відмова перезаписати: $OUT"
mkdir -p "$OUT"
: >"$OUT/00-status.txt"
echo "capture-utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$OUT/00-status.txt"
echo "kernel=$(uname -a)" >>"$OUT/00-status.txt"

step 'boot cmdline (read-only)'
cp /proc/cmdline "$OUT/01-cmdline.txt"
grep -q 'nouveau.debug=' "$OUT/01-cmdline.txt" \
  || fail 'нема nouveau.debug у /proc/cmdline — trace-сесія не та'
grep -q 'modprobe.blacklist=nvidia' "$OUT/01-cmdline.txt" \
  || fail 'нема modprobe.blacklist=nvidia у /proc/cmdline'
record 'W1:BOOT-CMDLINE runtime-proven'

step 'PCI identity + bound driver (read-only)'
command -v lspci >/dev/null 2>&1 || fail 'lspci недоступний'
lspci -Dnnk -d 10de:1c82 >"$OUT/02-lspci.txt" 2>&1
grep -q '10de:1c82' "$OUT/02-lspci.txt" || fail '10de:1c82 не знайдено'
grep -q "$BDF" "$OUT/02-lspci.txt" || fail "BDF $BDF не знайдено"
grep -q 'Kernel driver in use: nouveau' "$OUT/02-lspci.txt" \
  || fail 'Kernel driver in use не nouveau'
record 'W2:PCI-IDENTITY runtime-proven'

step 'proprietary modules absent (read-only)'
lsmod >"$OUT/03-lsmod.txt" 2>&1 || true
if grep -Eq '^nvidia(_uvm|_drm|_modeset|_peermem)?[[:space:]]' "$OUT/03-lsmod.txt"; then
  fail 'пропрієтарний модуль nvidia все ще завантажений'
fi
record 'W3:NVIDIA-MODULES-ABSENT runtime-proven'

step 'kernel log (newest boot, read-only)'
if command -v journalctl >/dev/null 2>&1; then
  journalctl -b -k --no-pager >"$OUT/04-kernel-log.txt" 2>&1 || true
else
  dmesg >"$OUT/04-kernel-log.txt" 2>&1 || true
fi
grep -i 'nouveau' "$OUT/04-kernel-log.txt" >"$OUT/05-nouveau-log.txt" 2>&1 || true
record 'W4:KERNEL-LOG captured (privilege-level noted)'

step 'nouveau debugfs inventory (read-only)'
: >"$OUT/06-debugfs.txt"
if [ -d /sys/kernel/debug/dri ]; then
  find /sys/kernel/debug/dri -maxdepth 2 -type f 2>/dev/null \
    | sort >"$OUT/06-debugfs-files.txt" || true
  while IFS= read -r f; do
    case "$(basename "$f")" in
      name|unique|instance|vram|gart|clients|objects|channels|pstate)
        printf '--- %s\n' "$f" >>"$OUT/06-debugfs.txt"
        cat "$f" >>"$OUT/06-debugfs.txt" 2>&1 || echo 'DENIED' >>"$OUT/06-debugfs.txt"
        ;;
    esac
  done <"$OUT/06-debugfs-files.txt"
else
  echo 'debugfs-unavailable-or-unprivileged' >"$OUT/06-debugfs-files.txt"
fi
record 'W5:DEBUGFS captured-best-effort'

step 'BAR0 inventory only (NO mmap, NO read)'
PCI_SYS="/sys/bus/pci/devices/$BDF"
[ -r "$PCI_SYS/resource" ] || fail "нема sysfs resource для $BDF"
cp "$PCI_SYS/resource" "$OUT/07-pci-resource.txt"
if [ -r "$PCI_SYS/resource0" ]; then
  echo 'resource0-readable-but-NOT-opened' >"$OUT/08-mmio.txt"
else
  echo 'resource0-denied' >"$OUT/08-mmio.txt"
fi
echo 'BOOT0: UNPROVEN (не читався, не стверджується)' >>"$OUT/08-mmio.txt"
echo 'MMIO-RIGHT: none' >>"$OUT/08-mmio.txt"
record 'W6:MMIO-DEFERRED explicitly'

step 'NVK driver assertion (vulkaninfo --summary)'
[ -r "$ICD" ] || fail "ICD недоступний: $ICD"
command -v vulkaninfo >/dev/null 2>&1 || fail 'vulkaninfo недоступний'
VK_ICD_FILENAMES="$ICD" vulkaninfo --summary >"$OUT/09-vulkaninfo.txt" 2>&1 \
  || echo 'VULKANINFO-NONZERO (див. файл)' >>"$OUT/00-status.txt"
grep -q 'DRIVER_ID_MESA_NVK' "$OUT/09-vulkaninfo.txt" \
  || fail 'DRIVER_ID_MESA_NVK не спостережено — NVK не активний'
if grep -Eq 'NVIDIA_PROPRIETARY|llvmpipe|softpipe|DRIVER_ID_MESA_LLVMPIPE' "$OUT/09-vulkaninfo.txt"; then
  fail 'присутній пропрієтарний або програмний драйвер'
fi
record 'W7:NVK-DRIVER-ID runtime-proven'

step 'DRM ioctl trace (vulkaninfo only; NOT PR #21)'
if command -v strace >/dev/null 2>&1; then
  VK_ICD_FILENAMES="$ICD" strace -f -e trace=ioctl -o "$OUT/10-ioctl.txt" \
    vulkaninfo --summary >/dev/null 2>&1 || true
  grep -E 'DRM_IOCTL|drm|NOUVEAU' "$OUT/10-ioctl.txt" \
    >"$OUT/11-drm-ioctl.txt" 2>&1 || true
  record 'W8:IOCTL-TRACE captured (names не стверджуються без header-перевірки)'
else
  echo 'strace-unavailable' >"$OUT/10-ioctl.txt"
  record 'W8:IOCTL-TRACE not-available'
fi

step 'manifest with per-file SHA-256'
{
  echo "# Nouveau boot witness manifest"
  echo "capture-utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "bdf=$BDF"
  echo "icd=$ICD"
  echo "boot0=UNPROVEN"
  echo "mmio-write=absent"
  echo "pr21-executable=NOT-RUN"
  echo
  sha256sum "$OUT"/* 2>/dev/null | sort -k2 || true
} >"$OUT/99-manifest.txt"

echo "NOUVEAU-WITNESS-CAPTURE-OK out=$OUT bdf=$BDF icd=$ICD boot0=unproven pr21=not-run"
