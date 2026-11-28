#!/usr/bin/env bash
# Host-independent regression test for the GP107 matrix evidence collector.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKEBIN="$TMP/bin"
SYS_ROOT="$TMP/sys"
mkdir -p "$FAKEBIN" "$SYS_ROOT/bus/pci/devices" "$SYS_ROOT/class/drm"
MARKER="$TMP/graphics-probe-ran"

NVIDIA="$SYS_ROOT/bus/pci/devices/0000:03:00.0"
INTEL="$SYS_ROOT/bus/pci/devices/0000:00:02.0"
mkdir -p "$NVIDIA/hwmon/hwmon1" "$INTEL/hwmon/hwmon0"
printf '0x10de\n' > "$NVIDIA/vendor"
printf '0x1c82\n' > "$NVIDIA/device"
printf '0x8086\n' > "$INTEL/vendor"
printf '0x1912\n' > "$INTEL/device"
printf '42000\n' > "$NVIDIA/hwmon/hwmon1/temp1_input"
printf '99999\n' > "$INTEL/hwmon/hwmon0/temp1_input"
printf '1000\n' > "$NVIDIA/gt_cur_freq_mhz"
printf '9999\n' > "$INTEL/gt_cur_freq_mhz"
ln -s "$NVIDIA" "$SYS_ROOT/class/drm/card1-device-link"
ln -s "$NVIDIA" "$SYS_ROOT/class/drm/card1"
ln -s "$NVIDIA" "$SYS_ROOT/class/drm/card1/device" 2>/dev/null || true
ln -s "$INTEL" "$SYS_ROOT/class/drm/card0/device"

cat > "$FAKEBIN/lspci" <<'LSPCI'
#!/usr/bin/env bash
case "$1" in
  -Dnn)
    printf '%s\n' '0000:00:02.0 VGA compatible controller [0300]: Intel Corporation HD Graphics 530 [8086:1912]'
    printf '%s\n' '0000:03:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP107 [10de:1c82]'
    ;;
  -Dnnk)
    printf '%s\n' '0000:03:00.0 VGA compatible controller [0300]: NVIDIA GP107 [10de:1c82]'
    printf '%s\n' '        Kernel driver in use: nouveau'
    ;;
  -Dnnvv)
    [ "$2" = "-s" ] && [ "$3" = "0000:03:00.0" ] || exit 9
    printf 'VERBOSE-BDF=%s\n' "$3"
    ;;
  *)
    echo "unexpected lspci arguments: $*" >&2
    exit 10
    ;;
esac
LSPCI
cat > "$FAKEBIN/lsmod" <<'LSMOD'
#!/usr/bin/env bash
printf '%s\n' 'Module Size Used by' 'nouveau 123 0' 'i915 456 1'
LSMOD
cat > "$FAKEBIN/dmesg" <<'DMESG'
#!/usr/bin/env bash
if [ "$1" = "-r" ]; then exit 0; fi
printf '%s\n' '[  1.0] nouveau 0000:03:00.0: GP107 initialized' '[ 1.1] i915 0000:00:02.0: Intel graphics'
DMESG
cat > "$FAKEBIN/vulkaninfo" <<'VULKAN'
#!/usr/bin/env bash
touch "$PROBE_MARKER"
echo 'deviceName = NVIDIA GeForce GTX 1050 Ti'
VULKAN
cat > "$FAKEBIN/glxinfo" <<'GLX'
#!/usr/bin/env bash
touch "$PROBE_MARKER"
echo 'OpenGL renderer string: NVK'
GLX
chmod +x "$FAKEBIN"/*

OUT="$TMP/passive"
PATH="$FAKEBIN:$PATH" WSM_SYS_ROOT="$SYS_ROOT" PROBE_MARKER="$MARKER" \
  bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT" > "$TMP/passive.log"

grep -q 'REFERENCE_CARD:10de:1c82:BDF=0000:03:00.0' "$OUT/00-status.txt"
grep -q 'VERBOSE-BDF=0000:03:00.0' "$OUT/06-gpu-pci-verbose.txt"
grep -q 'NOT_RUN: requires separately approved --allow-graphics-init' "$OUT/07-vulkaninfo.txt"
[ ! -e "$MARKER" ]
grep -q 'temp1_input=42000' "$OUT/10-gp107-thermal-and-clocks.txt"
! grep -q '99999\|9999' "$OUT/10-gp107-thermal-and-clocks.txt"
bash "$ROOT/scripts/test-evidence-manifest.sh" "$OUT/99-manifest.txt" >/dev/null

OUT_OPT="$TMP/opt-in"
PATH="$FAKEBIN:$PATH" WSM_SYS_ROOT="$SYS_ROOT" PROBE_MARKER="$MARKER" \
  bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" --allow-graphics-init "$OUT_OPT" > "$TMP/opt-in.log"
[ -e "$MARKER" ]
grep -q 'deviceName = NVIDIA GeForce GTX 1050 Ti' "$OUT_OPT/07-vulkaninfo.txt"
grep -q 'OpenGL renderer string: NVK' "$OUT_OPT/08-glxinfo.txt"
bash "$ROOT/scripts/test-evidence-manifest.sh" "$OUT_OPT/99-manifest.txt" >/dev/null

echo "MATRIX-COLLECTOR-TEST-OK passive-default=1 explicit-graphics-opt-in=1 bdf=dynamic telemetry=pci-filtered"
