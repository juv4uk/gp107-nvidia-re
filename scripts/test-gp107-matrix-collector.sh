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

# Build a hermetic PATH: only the requested fake tools plus real core utilities.
# Never inherit the host PATH, or a real lspci/lsmod/dmesg can defeat a
# "tool is missing" regression test on GitHub's Ubuntu runner.
make_minimal_path() {
  local destination="$1"
  shift
  mkdir "$destination"
  for tool in dirname date mkdir mktemp awk cat basename readlink sha256sum grep tail rm bash python3 cp git; do
    local resolved
    resolved="$(command -v "$tool")"
    ln -s "$resolved" "$destination/$tool"
  done
  for tool in "$@"; do
    [ -x "$FAKEBIN/$tool" ] || { echo "missing fake tool: $tool" >&2; return 1; }
    ln -s "$FAKEBIN/$tool" "$destination/$tool"
  done
}

note "unique BDF, exact sysfs identity and telemetry"
OUT="$WORK/passive"
bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT" > "$WORK/passive.log"
grep -Fxq 'target=REFERENCE_CARD:10de:1c82:BDF=0000:03:00.0' "$OUT/00-status.txt"
grep -Fxq 'pci_inventory=collected' "$OUT/00-status.txt"
grep -q 'VERBOSE-BDF=0000:03:00.0' "$OUT/05-pci-driver.txt"
grep -q 'VERBOSE-BDF=0000:03:00.0' "$OUT/06-pci-verbose.txt"
grep -q 'temp1_input=42000' "$OUT/09-gp107-thermal-and-clocks.txt"
! grep -q '99999' "$OUT/09-gp107-thermal-and-clocks.txt"
grep -Fxq 'gpu_runtime=NOT_RUN:owner-approval-required' "$OUT/00-status.txt"
[ ! -e "$MARKER" ]

# A PCI candidate is not authoritative until the same BDF agrees in sysfs.
printf '0x8086\n' > "$GPU/vendor"
OUT_MISMATCH="$WORK/sysfs-mismatch"
bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT_MISMATCH" > "$WORK/sysfs-mismatch.log"
grep -Fxq 'target=SYSFS_IDENTITY_MISMATCH: BDF=0000:03:00.0' "$OUT_MISMATCH/00-status.txt"
grep -Fxq 'target_candidate=PCI_CANDIDATE:10de:1c82:BDF=0000:03:00.0' "$OUT_MISMATCH/00-status.txt"
grep -Fxq 'pci_verbose=NOT_AVAILABLE:no-sysfs-match' "$OUT_MISMATCH/00-status.txt"
grep -q 'NOT_AVAILABLE: exact GP107 sysfs identity not established' "$OUT_MISMATCH/09-gp107-thermal-and-clocks.txt"
printf '0x10de\n' > "$GPU/vendor"

bash "$ROOT/scripts/test-evidence-manifest.sh" "$OUT/99-manifest.txt" > "$WORK/passive-manifest.log"
# Specific to the manifest under test: a bare `MANIFEST-OK` could match any
# line, and the wrapper used to emit the self-test's fixture lines here.
# Absolute paths are labelled `external:` by the gate, so match the label too.
grep -q "MANIFEST-OK manifest=external:$OUT/99-manifest.txt" "$WORK/passive-manifest.log"

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
grep -Fxq 'pci_inventory=FAILED:rc=11' "$OUT_LSPCI_FAIL/00-status.txt"

note "missing tools are tested without falling back to host executables"
MINBIN_NO_LSMOD="$WORK/path-no-lsmod"
make_minimal_path "$MINBIN_NO_LSMOD" lspci dmesg
OUT_NO_LSMOD="$WORK/no-lsmod"
PATH="$MINBIN_NO_LSMOD" /bin/bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT_NO_LSMOD" > "$WORK/no-lsmod.log"
grep -Fxq 'kernel_modules=NOT_AVAILABLE:no-lsmod' "$OUT_NO_LSMOD/00-status.txt"

MINBIN_NO_DMESG="$WORK/path-no-dmesg"
make_minimal_path "$MINBIN_NO_DMESG" lspci lsmod
OUT_NO_DMESG="$WORK/no-dmesg"
PATH="$MINBIN_NO_DMESG" /bin/bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT_NO_DMESG" > "$WORK/no-dmesg.log"
grep -Fxq 'dmesg=NOT_AVAILABLE:no-dmesg' "$OUT_NO_DMESG/00-status.txt"

MINBIN_NO_LSPCI="$WORK/path-no-lspci"
make_minimal_path "$MINBIN_NO_LSPCI" lsmod dmesg
OUT_NO_LSPCI="$WORK/no-lspci"
PATH="$MINBIN_NO_LSPCI" /bin/bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT_NO_LSPCI" > "$WORK/no-lspci.log"
grep -Fxq 'target=UNKNOWN:lspci-absent' "$OUT_NO_LSPCI/00-status.txt"
grep -Fxq 'pci_inventory=NOT_AVAILABLE:no-lspci' "$OUT_NO_LSPCI/00-status.txt"
grep -Fxq 'pci_driver=NOT_AVAILABLE:no-lspci' "$OUT_NO_LSPCI/00-status.txt"
grep -Fxq 'pci_verbose=NOT_AVAILABLE:no-lspci' "$OUT_NO_LSPCI/00-status.txt"

# The no-uname case also runs with a hermetic PATH (the fake PCI/module tools
# remain present, but the host's real uname is not reachable).
MINBIN_NO_UNAME="$WORK/path-no-uname"
make_minimal_path "$MINBIN_NO_UNAME" lspci lsmod dmesg
OUT_NO_UNAME="$WORK/no-uname"
PATH="$MINBIN_NO_UNAME" /bin/bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT_NO_UNAME" > "$WORK/no-uname.log"
grep -Fxq 'system=NOT_AVAILABLE:no-uname' "$OUT_NO_UNAME/00-status.txt"

# A present uname that exits nonzero is a command failure, not NOT_AVAILABLE.
cat > "$FAKEBIN/uname" <<'UNAME'
#!/usr/bin/env bash
echo "fake uname failure" >&2
exit 9
UNAME
chmod +x "$FAKEBIN/uname"
OUT_FAIL_UNAME="$WORK/uname-failure"
PATH="$FAKEBIN:$PATH" bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT_FAIL_UNAME" > "$WORK/uname-failure.log"
grep -Fxq 'system=FAILED:rc=9' "$OUT_FAIL_UNAME/00-status.txt"
grep -q 'fake uname failure' "$OUT_FAIL_UNAME/02-system.txt"
rm "$FAKEBIN/uname"

echo "MATRIX-COLLECTOR-OK unique-bdf=1 output-immutable=1 telemetry-scoped=1 command-status=honest runtime=NOT_RUN"
