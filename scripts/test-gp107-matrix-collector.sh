#!/usr/bin/env bash
# Host-independent regression coverage for the passive GP107 evidence collector.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
finish() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'MATRIX-COLLECTOR-TEST-FAIL status=%s\n' "$rc" >&2
    for artifact in "$WORK"/*.log "$WORK"/*/00-status.txt "$WORK"/*/10-manifest-check.txt; do
      [ -f "$artifact" ] || continue
      printf '\n--- %s ---\n' "$artifact" >&2
      sed -n '1,120p' "$artifact" >&2 || true
    done
  fi
  rm -rf "$WORK"
  return "$rc"
}
trap finish EXIT
trap 'rc=$?; printf "MATRIX-COLLECTOR-ERR line=%s status=%s command=%s\\n" "$LINENO" "$rc" "$BASH_COMMAND" >&2; exit "$rc"' ERR
note() { printf '[matrix-test] %s\n' "$*" >&2; }
FAKEBIN="$WORK/bin"
SYS_ROOT="$WORK/sys"
MARKER="$WORK/gpu-runtime-invoked"
mkdir -p "$FAKEBIN" "$SYS_ROOT/bus/pci/devices"
GPU="$SYS_ROOT/bus/pci/devices/0000:03:00.0"
INTEL="$SYS_ROOT/bus/pci/devices/0000:00:02.0"
mkdir -p "$GPU/hwmon/hwmon0" "$INTEL/hwmon/hwmon0"
printf '0x10de\n' > "$GPU/vendor"
printf '0x1c82\n' > "$GPU/device"
printf '0x8086\n' > "$INTEL/vendor"
printf '0x1912\n' > "$INTEL/device"
printf '42000\n' > "$GPU/hwmon/hwmon0/temp1_input"
printf '99999\n' > "$INTEL/hwmon/hwmon0/temp1_input"

cat > "$FAKEBIN/lspci" <<'LSPCI'
#!/usr/bin/env bash
case "$1" in
  -Dnn)
    if [ "${LSPCI_FAIL:-0}" = "1" ]; then echo "fake lspci failure" >&2; exit 11; fi
    case "${LSPCI_MODE:-target}" in
      target)
        printf '%s\n' \
          '0000:00:02.0 VGA compatible controller [0300]: Intel HD Graphics 530 [8086:1912]' \
          '0000:03:00.0 3D controller [0302]: NVIDIA GP107 [10de:1c82]'
        ;;
      none)
        printf '%s\n' '0000:00:02.0 VGA compatible controller [0300]: Intel HD Graphics 530 [8086:1912]'
        ;;
      multiple)
        printf '%s\n' \
          '0000:03:00.0 3D controller [0302]: NVIDIA GP107 [10de:1c82]' \
          '0000:04:00.0 3D controller [0302]: NVIDIA GP107 [10de:1c82]'
        ;;
      *) exit 12 ;;
    esac
    ;;
  -Dnnk|-Dnnvv)
    [ "$2" = "-s" ] && [ "$3" = "0000:03:00.0" ] || exit 13
    printf 'VERBOSE-BDF=%s\n' "$3"
    ;;
  *) echo "unexpected lspci args: $*" >&2; exit 14 ;;
esac
LSPCI
cat > "$FAKEBIN/lsmod" <<'LSMOD'
#!/usr/bin/env bash
if [ "${LSMOD_FAIL:-0}" = "1" ]; then echo "fake lsmod failure" >&2; exit 7; fi
printf '%s\n' 'Module Size Used by' 'nouveau 123 0' 'i915 456 1' 'snd_hda_intel 789 1'
LSMOD
cat > "$FAKEBIN/dmesg" <<'DMESG'
#!/usr/bin/env bash
if [ "${DMESG_FAIL:-0}" = "1" ]; then echo "fake dmesg failure" >&2; exit 8; fi
if [ "${1:-}" = "-r" ]; then exit 0; fi
printf '%s\n' '[ 1.0] nouveau 0000:03:00.0: GP107 initialized' '[ 1.1] i915 0000:00:02.0: Intel graphics'
DMESG
cat > "$FAKEBIN/vulkaninfo" <<'VULKAN'
#!/usr/bin/env bash
echo "vulkaninfo must not run" >> "$GPU_RUNTIME_MARKER"
exit 99
VULKAN
cat > "$FAKEBIN/glxinfo" <<'GLX'
#!/usr/bin/env bash
echo "glxinfo must not run" >> "$GPU_RUNTIME_MARKER"
exit 99
GLX
chmod +x "$FAKEBIN"/*
export PATH="$FAKEBIN:$PATH"
export WSM_SYS_ROOT="$SYS_ROOT"
export GPU_RUNTIME_MARKER="$MARKER"

note "unique BDF, exact sysfs identity and telemetry"
OUT="$WORK/passive"
bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT" > "$WORK/passive.log"
grep -Fxq 'target=REFERENCE_CARD:10de:1c82:BDF=0000:03:00.0' "$OUT/00-status.txt"
grep -Fxq 'sysfs_identity=MATCH:0000:03:00.0' "$OUT/00-status.txt"
grep -q 'VERBOSE-BDF=0000:03:00.0' "$OUT/06-pci-verbose.txt"
grep -q 'temp1_input=42000' "$OUT/09-gp107-thermal-and-clocks.txt"
! grep -q '99999' "$OUT/09-gp107-thermal-and-clocks.txt"
grep -Fxq 'gpu_runtime=NOT_RUN:owner-approval-required' "$OUT/00-status.txt"
[ ! -e "$MARKER" ]
bash "$ROOT/scripts/test-evidence-manifest.sh" "$OUT/99-manifest.txt" > "$WORK/passive-manifest.log"
grep -q 'MANIFEST-OK' "$WORK/passive-manifest.log"

note "existing output and symlink output must be refused without mutation"
EXISTING="$WORK/existing"
mkdir "$EXISTING"
printf 'preserve-this-evidence\n' > "$EXISTING/00-status.txt"
BEFORE="$(sha256sum "$EXISTING/00-status.txt" | awk '{print $1}')"
if bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$EXISTING" > "$WORK/reuse.log" 2>&1; then
  echo "collector accepted existing output directory" >&2; exit 1
fi
AFTER="$(sha256sum "$EXISTING/00-status.txt" | awk '{print $1}')"
[ "$BEFORE" = "$AFTER" ]
LINK="$WORK/output-link"
ln -s "$EXISTING" "$LINK"
if bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$LINK" > "$WORK/link.log" 2>&1; then
  echo "collector accepted symlink output directory" >&2; exit 1
fi
[ "$(sha256sum "$EXISTING/00-status.txt" | awk '{print $1}')" = "$BEFORE" ]

note "missing and ambiguous targets must not bind a different BDF"
OUT_NONE="$WORK/no-target"
LSPCI_MODE=none bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT_NONE" > "$WORK/none.log"
grep -Fxq 'target=NOT_THE_REFERENCE_CARD:expected=10de:1c82' "$OUT_NONE/00-status.txt"
grep -Fxq 'pci_verbose=NOT_AVAILABLE:no-sysfs-match' "$OUT_NONE/00-status.txt"
OUT_MULTI="$WORK/multiple"
LSPCI_MODE=multiple bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT_MULTI" > "$WORK/multiple.log"
grep -Fxq 'target=AMBIGUOUS_REFERENCE_CARDS:count=2' "$OUT_MULTI/00-status.txt"
grep -Fxq 'pci_verbose=NOT_AVAILABLE:no-sysfs-match' "$OUT_MULTI/00-status.txt"

note "tool failures must preserve exact status and stderr"
OUT_FAIL="$WORK/tool-failures"
LSMOD_FAIL=1 DMESG_FAIL=1 bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT_FAIL" > "$WORK/failures.log"
grep -Fxq 'kernel_modules=FAILED:rc=7' "$OUT_FAIL/00-status.txt"
grep -Fxq 'dmesg=FAILED:rc=8' "$OUT_FAIL/00-status.txt"
grep -q 'fake lsmod failure' "$OUT_FAIL/03-kernel-modules.txt"
grep -q 'fake dmesg failure' "$OUT_FAIL/10-dmesg.txt"
OUT_LSPCI_FAIL="$WORK/lspci-failure"
LSPCI_FAIL=1 bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT_LSPCI_FAIL" > "$WORK/lspci-failure.log"
grep -Fxq 'target=FAILED:lspci-rc=11' "$OUT_LSPCI_FAIL/00-status.txt"

echo "MATRIX-COLLECTOR-OK unique-bdf=1 output-immutable=1 telemetry-scoped=1 command-status=honest runtime=NOT_RUN"
