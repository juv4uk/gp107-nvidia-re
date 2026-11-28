#!/usr/bin/env bash
# Read-only GP107 evidence collector. Passive inventory only; no GPU API init.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYS_ROOT="${WSM_SYS_ROOT:-/sys}"
OUT="${1:-$ROOT/evidence/matrix-$(date -u +%Y%m%dT%H%M%SZ)}"
REFERENCE_VENDOR="0x10de"
REFERENCE_DEVICE="0x1c82"
if [ "$#" -gt 1 ]; then echo "COLLECT-FAIL: one output-dir allowed" >&2; exit 2; fi
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
OUT_PARENT="$(dirname "$OUT")"
mkdir -p "$OUT_PARENT" || { echo "COLLECT-FAIL: cannot create parent $OUT_PARENT" >&2; exit 2; }
# Never follow or overwrite an existing directory, file, or symlink.
if [ -e "$OUT" ] || [ -L "$OUT" ]; then
  echo "COLLECT-FAIL: output-dir already exists: $OUT" >&2
  exit 2
fi
mkdir "$OUT" || { echo "COLLECT-FAIL: cannot create output-dir $OUT" >&2; exit 2; }
STATUS="$OUT/00-status.txt"
TMP_CAPTURE="$(mktemp)"
trap 'rm -f -- "$TMP_CAPTURE"' EXIT

record() { printf '%s=%s\n' "$1" "$2" >> "$STATUS"; }
note() { printf '%-24s %s\n' "$1" "$2"; }
unavailable() {
  local name="$1" key="$2" reason="$3"
  printf 'NOT_AVAILABLE: %s\n' "$reason" > "$OUT/$name"
  record "$key" "NOT_AVAILABLE:$reason"
}
failed() { record "$1" "FAILED:rc=$2"; note "$1" "FAILED rc=$2"; }
capture() {
  local name="$1" key="$2"; shift 2
  local executable="$1"; shift
  if ! command -v "$executable" >/dev/null 2>&1; then
    unavailable "$name" "$key" "no-$executable"
    return 0
  fi
  if "$executable" "$@" > "$OUT/$name" 2>&1; then
    record "$key" collected
  else
    local rc=$?
    record "$key" "FAILED:rc=$rc"
  fi
}

note output "$OUT"
record privacy "PRIVATE_REVIEW_REQUIRED:dmesg-and-local-paths"

# Resolve the exact unique domain-qualified BDF for 10de:1c82.
GPU_BDF=""
TARGET_STATE="UNKNOWN:lspci-absent"
TARGET_CANDIDATE="NOT_AVAILABLE:unique-10de:1c82-BDF-not-established"
if ! command -v lspci >/dev/null 2>&1; then
  printf 'NOT_AVAILABLE: lspci\n' > "$OUT/01-pci-inventory.txt"
  record pci_driver "NOT_AVAILABLE:no-lspci"
  record pci_verbose "NOT_AVAILABLE:no-lspci"
else
  if lspci -Dnn > "$OUT/01-pci-inventory.txt" 2>&1; then
    mapfile -t TARGET_BDFS < <(awk 'tolower($0) ~ /\[10de:1c82\]/ {print $1}' "$OUT/01-pci-inventory.txt")
    if [ "${#TARGET_BDFS[@]}" -eq 1 ]; then
      candidate="${TARGET_BDFS[0]}"
      if [[ "$candidate" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$ ]]; then
        GPU_BDF="$candidate"
        TARGET_CANDIDATE="PCI_CANDIDATE:10de:1c82:BDF=$GPU_BDF"
        TARGET_STATE="UNKNOWN:sysfs-identity-pending"
      else
        TARGET_STATE="FAILED:noncanonical-bdf"
      fi
    elif [ "${#TARGET_BDFS[@]}" -gt 1 ]; then
      TARGET_STATE="AMBIGUOUS_REFERENCE_CARDS:count=${#TARGET_BDFS[@]}"
    else
      TARGET_STATE="NOT_THE_REFERENCE_CARD:expected=10de:1c82"
    fi
  else
    rc=$?
    TARGET_STATE="FAILED:lspci-rc=$rc"
  fi
fi
record target_candidate "$TARGET_CANDIDATE"
note target_candidate "$TARGET_CANDIDATE"

# Minimal host context: never report collected after a failed uname.
if command -v uname >/dev/null 2>&1 && uname -srm > "$OUT/02-system.txt" 2>&1; then
  if [ -r /etc/os-release ]; then
    if cat /etc/os-release >> "$OUT/02-system.txt" 2>&1; then record os_release collected; else record os_release FAILED:cat; fi
  else
    printf '\nNOT_AVAILABLE: /etc/os-release\n' >> "$OUT/02-system.txt"
    record os_release "NOT_AVAILABLE:/etc/os-release"
  fi
  record system collected
else
  rc=$?
  printf 'FAILED: uname rc=%s\n' "$rc" > "$OUT/02-system.txt"
  failed system "$rc"
fi

if ! command -v lsmod >/dev/null 2>&1; then
  unavailable 03-kernel-modules.txt kernel_modules no-lsmod
elif lsmod > "$TMP_CAPTURE" 2>&1; then
  awk 'NR == 1 || $1 ~ /^(nouveau|nvidia|nvidia_uvm|nvidia_drm|nvidia_modeset|i915)$/' "$TMP_CAPTURE" > "$OUT/03-kernel-modules.txt"
  record kernel_modules collected
else
  rc=$?
  cp "$TMP_CAPTURE" "$OUT/03-kernel-modules.txt"
  failed kernel_modules "$rc"
fi

# Cross-check the selected PCI function against its own sysfs node.
SYSFS_MATCH=0
DEVICE_SYS=""
if [ -n "$GPU_BDF" ]; then
  DEVICE_SYS="$SYS_ROOT/bus/pci/devices/$GPU_BDF"
  {
    printf 'BDF=%s\n' "$GPU_BDF"
    if [ -r "$DEVICE_SYS/vendor" ]; then printf 'vendor=%s\n' "$(cat "$DEVICE_SYS/vendor" 2>/dev/null || echo FAILED)"; else echo 'vendor=NOT_AVAILABLE'; fi
    if [ -r "$DEVICE_SYS/device" ]; then printf 'device=%s\n' "$(cat "$DEVICE_SYS/device" 2>/dev/null || echo FAILED)"; else echo 'device=NOT_AVAILABLE'; fi
    if [ -r "$DEVICE_SYS/subsystem_vendor" ]; then printf 'subsystem_vendor=%s\n' "$(cat "$DEVICE_SYS/subsystem_vendor" 2>/dev/null || echo FAILED)"; fi
    if [ -r "$DEVICE_SYS/subsystem_device" ]; then printf 'subsystem_device=%s\n' "$(cat "$DEVICE_SYS/subsystem_device" 2>/dev/null || echo FAILED)"; fi
    if [ -L "$DEVICE_SYS/driver" ]; then printf 'driver=%s\n' "$(basename "$(readlink "$DEVICE_SYS/driver" 2>/dev/null || echo UNKNOWN)")"; else echo 'driver=UNBOUND_OR_UNKNOWN'; fi
  } > "$OUT/04-gpu-sysfs-identity.txt" 2>&1
  if [ -r "$DEVICE_SYS/vendor" ] && [ -r "$DEVICE_SYS/device" ] \
      && [ "$(cat "$DEVICE_SYS/vendor" 2>/dev/null || true)" = "$REFERENCE_VENDOR" ] \
      && [ "$(cat "$DEVICE_SYS/device" 2>/dev/null || true)" = "$REFERENCE_DEVICE" ]; then
    SYSFS_MATCH=1
    TARGET_STATE="REFERENCE_CARD:10de:1c82:BDF=$GPU_BDF"
    record sysfs_identity "MATCH:$GPU_BDF"
  else
    TARGET_STATE="SYSFS_IDENTITY_MISMATCH: BDF=$GPU_BDF"
    record sysfs_identity "MISMATCH_OR_UNAVAILABLE:$GPU_BDF"
  fi
else
  printf 'NOT_AVAILABLE: unique 10de:1c82 BDF not established\n' > "$OUT/04-gpu-sysfs-identity.txt"
  record sysfs_identity "NOT_AVAILABLE:no-unique-target"
fi
record target "$TARGET_STATE"
note target "$TARGET_STATE"

# Query the exact BDF only after both PCI and sysfs identity agree.
if [ "$SYSFS_MATCH" -eq 1 ]; then
  capture 05-pci-driver.txt pci_driver lspci -Dnnk -s "$GPU_BDF"
  capture 06-pci-verbose.txt pci_verbose lspci -Dnnvv -s "$GPU_BDF"
else
  printf 'NOT_AVAILABLE: exact sysfs identity not established\n' > "$OUT/05-pci-driver.txt"
  printf 'NOT_AVAILABLE: exact sysfs identity not established\n' > "$OUT/06-pci-verbose.txt"
  if command -v lspci >/dev/null 2>&1; then
    record pci_driver "NOT_AVAILABLE:no-sysfs-match"
    record pci_verbose "NOT_AVAILABLE:no-sysfs-match"
  else
    record pci_driver "NOT_AVAILABLE:no-lspci"
    record pci_verbose "NOT_AVAILABLE:no-lspci"
  fi
fi

# GPU API initialization and workloads remain outside this passive collector.
GPU_RUNTIME_STATE="NOT_RUN: owner-approved runtime session required"
printf '%s\n' "$GPU_RUNTIME_STATE" > "$OUT/07-gpu-runtime.txt"
printf '%s\n' "$GPU_RUNTIME_STATE" > "$OUT/08-renderer.txt"
record gpu_runtime "NOT_RUN:owner-approval-required"
record renderer "NOT_RUN:owner-approval-required"

# Read thermal/power telemetry only below the selected GP107 sysfs device.
THERMAL="$OUT/09-gp107-thermal-and-clocks.txt"
THERMAL_COUNT=0
THERMAL_FAILED=0
: > "$THERMAL"
if [ "$SYSFS_MATCH" -eq 1 ]; then
  for hw in "$DEVICE_SYS"/hwmon/hwmon*; do
    [ -d "$hw" ] || continue
    printf '== %s ==\n' "$(basename "$hw")" >> "$THERMAL"
    for attribute in temp1_input temp1_max power1_average power1_input gpu_busy_percent freq1_input; do
      if [ -r "$hw/$attribute" ]; then
        if value="$(cat "$hw/$attribute" 2>/dev/null)"; then
          printf '%s=%s\n' "$attribute" "$value" >> "$THERMAL"
          THERMAL_COUNT=$((THERMAL_COUNT + 1))
        else
          printf 'FAILED:%s\n' "$attribute" >> "$THERMAL"
          THERMAL_FAILED=1
        fi
      fi
    done
  done
  for attribute in gpu_busy_percent mem_info_vram_used mem_info_vram_total; do
    if [ -r "$DEVICE_SYS/$attribute" ]; then
      if value="$(cat "$DEVICE_SYS/$attribute" 2>/dev/null)"; then
        printf '%s=%s\n' "$attribute" "$value" >> "$THERMAL"
        THERMAL_COUNT=$((THERMAL_COUNT + 1))
      else
        printf 'FAILED:%s\n' "$attribute" >> "$THERMAL"
        THERMAL_FAILED=1
      fi
    fi
  done
else
  printf 'NOT_AVAILABLE: exact GP107 sysfs identity not established\n' > "$THERMAL"
fi
if [ "$THERMAL_FAILED" -ne 0 ]; then
  record clocks_thermal FAILED:read-error
elif [ "$THERMAL_COUNT" -gt 0 ]; then
  record clocks_thermal collected
else
  printf 'NOT_AVAILABLE: no GP107 hwmon/telemetry nodes\n' >> "$THERMAL"
  record clocks_thermal "NOT_AVAILABLE:gp107-hwmon"
fi

# Filter kernel log and record actual command status.
if ! command -v dmesg >/dev/null 2>&1; then
  unavailable 10-dmesg.txt dmesg no-dmesg
elif dmesg -r > "$TMP_CAPTURE" 2>&1; then
  if dmesg > "$TMP_CAPTURE" 2>&1; then
    grep -Ei 'nouveau|nvidia|drm' "$TMP_CAPTURE" | tail -300 > "$OUT/10-dmesg.txt" || true
    record dmesg collected
  else
    rc=$?; cp "$TMP_CAPTURE" "$OUT/10-dmesg.txt"; failed dmesg "$rc"
  fi
else
  rc=$?; cp "$TMP_CAPTURE" "$OUT/10-dmesg.txt"; failed dmesg "$rc"
fi

# Hash final evidence files; manifest and its later self-check are not captures.
MANIFEST="$OUT/99-manifest.txt"
{
  echo "# GP107 matrix evidence, collected $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# target=$TARGET_STATE"
  echo "# passive-only: no Vulkan/OpenGL init, ioctl, GPU submit or device writes"
} > "$MANIFEST"
for file in "$OUT"/*.txt; do
  [ -f "$file" ] || continue
  name="$(basename "$file")"
  case "$name" in 99-manifest.txt|10-manifest-check.txt) continue ;; esac
  printf '%s  %s\n' "$(sha256sum "$file" | awk '{print $1}')" "$name" >> "$MANIFEST"
done
if bash "$ROOT/scripts/test-evidence-manifest.sh" "$MANIFEST" > "$OUT/10-manifest-check.txt" 2>&1; then
  note manifest "self-check OK"
else
  note manifest "self-check FAILED"
  echo "COLLECT-FAIL: self-manifest check failed; see 10-manifest-check.txt" >&2
  exit 2
fi
note summary "$OUT/00-status.txt"
echo "COLLECT-OK dir=$OUT"
