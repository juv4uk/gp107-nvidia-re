#!/usr/bin/env bash
# Збирає evidence для матриці #28. За замовчуванням — пасивна інвентаризація.
#
# Безпечний default:
#   * без root, mmap, resource0, BAR/MMIO, ioctl, GPU submit чи driver switch;
#   * lspci/sysfs/lsmod/dmesg — лише читання;
#   * vulkaninfo/glxinfo НЕ запускаються автоматично: вони ініціалізують
#     userspace graphics stack і потребують окремого owner-approved session;
#   * відсутні інструменти записуються як NOT_AVAILABLE;
#   * PASS не виводиться: скрипт лише збирає факти, матриця потребує review.
#
# Використання:
#   bash scripts/collect-gp107-matrix-evidence.sh [--allow-graphics-init] [output-dir]
#
# --allow-graphics-init є явним opt-in для окремо погодженої сесії. Він запускає
# лише vulkaninfo --summary та glxinfo -B; це не запускає workload/compute.
# Output може містити чутливі kernel-log рядки та локальні шляхи: каталог
# спершу приватний; перед публікацією потрібна ручна редакція PII.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYS_ROOT="${WSM_SYS_ROOT:-/sys}"
REFERENCE_VENDOR="0x10de"
REFERENCE_DEVICE="0x1c82"
ALLOW_GRAPHICS_INIT=0
OUT=""

usage() {
  cat <<'USAGE'
Usage: collect-gp107-matrix-evidence.sh [--allow-graphics-init] [output-dir]

Default mode is passive inventory only. vulkaninfo/glxinfo run only when the
explicit --allow-graphics-init option is supplied for an approved session.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --allow-graphics-init)
      ALLOW_GRAPHICS_INIT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "COLLECT-FAIL: невідомий параметр $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -n "$OUT" ]; then
        echo "COLLECT-FAIL: дозволений лише один output-dir" >&2
        exit 2
      fi
      OUT="$1"
      shift
      ;;
  esac
done

if [ -z "$OUT" ]; then
  OUT="$ROOT/evidence/matrix-$(date -u +%Y%m%dT%H%M%SZ)"
fi

mkdir -p "$(dirname "$OUT")" || {
  echo "COLLECT-FAIL: не створюється батьківський каталог для $OUT" >&2
  exit 2
}
mkdir "$OUT" 2>/dev/null || {
  echo "COLLECT-FAIL: output-dir уже існує або недоступний: $OUT" >&2
  exit 2
}

STATUS="$OUT/00-status.txt"
: > "$STATUS"

record() { printf '%s=%s\n' "$1" "$2" >> "$STATUS"; }
note()   { printf '%-24s %s\n' "$1" "$2"; }

capture() { # $1 = filename, rest = command
  local name="$1"
  shift
  local file="$OUT/$name"
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'NOT_AVAILABLE: %s\n' "$1" > "$file"
    record "${name//[.-]/_}" "NOT_AVAILABLE:no-$1"
    note "$name" "NOT_AVAILABLE ($1 відсутній)"
    return 0
  fi
  if "$@" > "$file" 2>&1; then
    record "${name//[.-]/_}" "collected"
    note "$name" "collected"
  else
    local rc=$?
    record "${name//[.-]/_}" "FAILED:rc=$rc"
    note "$name" "FAILED rc=$rc (вивід збережено)"
  fi
}

note output "$OUT"
record privacy "PRIVATE_REVIEW_REQUIRED:dmesg-and-local-paths"

# --- 1. Знаходимо точний BDF за PCI vendor/device, не припускаємо 01:00.0. ---
GPU_BDF=""
TARGET_STATE="UNKNOWN:lspci-absent"
if command -v lspci >/dev/null 2>&1; then
  if lspci -Dnn > "$OUT/01-pci-inventory.txt" 2>&1; then
    mapfile -t TARGET_BDFS < <(
      awk '$0 ~ /\[10de:1c82\]/ { print $1 }' "$OUT/01-pci-inventory.txt"
    )
    if [ "${#TARGET_BDFS[@]}" -eq 1 ]; then
      GPU_BDF="${TARGET_BDFS[0]}"
      TARGET_STATE="REFERENCE_CARD:10de:1c82:BDF=$GPU_BDF"
    elif [ "${#TARGET_BDFS[@]}" -gt 1 ]; then
      TARGET_STATE="AMBIGUOUS_REFERENCE_CARDS:count=${#TARGET_BDFS[@]}"
    else
      TARGET_STATE="NOT_THE_REFERENCE_CARD:expected=10de:1c82"
    fi
  else
    TARGET_STATE="FAILED:lspci-rc"
  fi
else
  printf 'NOT_AVAILABLE: lspci\n' > "$OUT/01-pci-inventory.txt"
fi
record target "$TARGET_STATE"
note target "$TARGET_STATE"

# Полний PCI/driver inventory допомагає відрізнити bound driver від module candidate.
if command -v lspci >/dev/null 2>&1; then
  capture 02-pci-drivers.txt lspci -Dnnk
else
  printf 'NOT_AVAILABLE: lspci\n' > "$OUT/02-pci-drivers.txt"
fi

# --- 2. Система та модулі. ---
{
  uname -srm
  echo
  cat /etc/os-release 2>/dev/null || true
} > "$OUT/03-system.txt" 2>&1
record system collected

if command -v lsmod >/dev/null 2>&1; then
  lsmod 2>/dev/null | awk 'NR == 1 || $1 ~ /^(nouveau|nvidia|nvidia_uvm|nvidia_drm|nvidia_modeset|i915)$/ ' \
    > "$OUT/04-kernel-modules.txt" || true
  record kernel_modules collected
else
  printf 'NOT_AVAILABLE: lsmod\n' > "$OUT/04-kernel-modules.txt"
  record kernel_modules NOT_AVAILABLE:lsmod
fi

# Додатково звіряємо sysfs identity та фактичне driver symlink тільки для
# єдиного точного 10de:1c82. Ніякого bind/unbind або читання BAR.
if [ -n "$GPU_BDF" ]; then
  DEVICE_SYS="$SYS_ROOT/bus/pci/devices/$GPU_BDF"
  {
    printf 'BDF=%s\n' "$GPU_BDF"
    if [ -r "$DEVICE_SYS/vendor" ]; then printf 'vendor=%s\n' "$(cat "$DEVICE_SYS/vendor")"; else echo 'vendor=NOT_AVAILABLE'; fi
    if [ -r "$DEVICE_SYS/device" ]; then printf 'device=%s\n' "$(cat "$DEVICE_SYS/device")"; else echo 'device=NOT_AVAILABLE'; fi
    if [ -r "$DEVICE_SYS/subsystem_vendor" ]; then printf 'subsystem_vendor=%s\n' "$(cat "$DEVICE_SYS/subsystem_vendor")"; fi
    if [ -r "$DEVICE_SYS/subsystem_device" ]; then printf 'subsystem_device=%s\n' "$(cat "$DEVICE_SYS/subsystem_device")"; fi
    if [ -L "$DEVICE_SYS/driver" ]; then
      printf 'driver=%s\n' "$(basename "$(readlink "$DEVICE_SYS/driver")")"
    else
      echo 'driver=UNBOUND_OR_UNKNOWN'
    fi
  } > "$OUT/05-gpu-sysfs-identity.txt" 2>&1
  if [ -r "$DEVICE_SYS/vendor" ] && [ -r "$DEVICE_SYS/device" ] \
      && [ "$(cat "$DEVICE_SYS/vendor")" = "$REFERENCE_VENDOR" ] \
      && [ "$(cat "$DEVICE_SYS/device")" = "$REFERENCE_DEVICE" ]; then
    record sysfs_identity "MATCH:$GPU_BDF"
  else
    record sysfs_identity "MISMATCH_OR_UNAVAILABLE:$GPU_BDF"
  fi
  capture 06-gpu-pci-verbose.txt lspci -Dnnvv -s "$GPU_BDF"
else
  printf 'NOT_AVAILABLE: unique target BDF not established\n' > "$OUT/05-gpu-sysfs-identity.txt"
  printf 'NOT_AVAILABLE: unique target BDF not established\n' > "$OUT/06-gpu-pci-verbose.txt"
  record sysfs_identity NOT_AVAILABLE:no-unique-target
fi

# --- 3. Графічна ідентифікація — лише після явного opt-in. ---
if [ "$ALLOW_GRAPHICS_INIT" -eq 1 ]; then
  if [ -n "$GPU_BDF" ]; then
    capture 07-vulkaninfo.txt vulkaninfo --summary
    capture 08-glxinfo.txt glxinfo -B
    {
      grep -Ei 'deviceName|driverName|driverID|apiVersion|GPU' "$OUT/07-vulkaninfo.txt" 2>/dev/null || true
      grep -Ei 'OpenGL vendor|OpenGL renderer|OpenGL version' "$OUT/08-glxinfo.txt" 2>/dev/null || true
    } > "$OUT/09-renderer-summary.txt"
    record graphics_probes "REQUESTED_BY_EXPLICIT_FLAG"
  else
    printf 'NOT_RUN: unique 10de:1c82 BDF not established\n' > "$OUT/07-vulkaninfo.txt"
    printf 'NOT_RUN: unique 10de:1c82 BDF not established\n' > "$OUT/08-glxinfo.txt"
    printf 'NOT_RUN: unique target BDF not established\n' > "$OUT/09-renderer-summary.txt"
    record graphics_probes "NOT_RUN:no-unique-target"
  fi
else
  printf 'NOT_RUN: requires separately approved --allow-graphics-init\n' > "$OUT/07-vulkaninfo.txt"
  printf 'NOT_RUN: requires separately approved --allow-graphics-init\n' > "$OUT/08-glxinfo.txt"
  printf 'NOT_RUN: graphics stack was not initialized\n' > "$OUT/09-renderer-summary.txt"
  record graphics_probes "NOT_RUN:passive-default"
fi

# --- 4. Telemetry лише з DRM card, чий sysfs PCI device дорівнює GP107. ---
TELEMETRY_FOUND=0
TELEMETRY_FILE="$OUT/10-gp107-thermal-and-clocks.txt"
: > "$TELEMETRY_FILE"
if [ -n "$GPU_BDF" ]; then
  for card in "$SYS_ROOT"/class/drm/card*; do
    [ -e "$card/device" ] || continue
    card_device="$(readlink -f "$card/device" 2>/dev/null || true)"
    [ -n "$card_device" ] || continue
    [ -r "$card_device/vendor" ] && [ -r "$card_device/device" ] || continue
    [ "$(cat "$card_device/vendor")" = "$REFERENCE_VENDOR" ] || continue
    [ "$(cat "$card_device/device")" = "$REFERENCE_DEVICE" ] || continue
    TELEMETRY_FOUND=1
    printf 'BDF=%s\n' "$GPU_BDF" >> "$TELEMETRY_FILE"
    for hw in "$card"/device/hwmon/hwmon*; do
      [ -d "$hw" ] || continue
      printf '== hwmon/%s\n' "$(basename "$hw")" >> "$TELEMETRY_FILE"
      for f in temp1_input temp1_max power1_average; do
        [ -r "$hw/$f" ] && printf '%s=%s\n' "$f" "$(cat "$hw/$f")" >> "$TELEMETRY_FILE"
      done
    done
    for f in gt_cur_freq_mhz gt_max_freq_mhz; do
      [ -r "$card/device/$f" ] && printf '%s=%s\n' "$f" "$(cat "$card/device/$f")" >> "$TELEMETRY_FILE"
    done
  done
fi
if [ "$TELEMETRY_FOUND" -eq 1 ] && [ -s "$TELEMETRY_FILE" ]; then
  record gp107_telemetry collected
else
  printf 'NOT_AVAILABLE: no GP107-specific DRM hwmon/clock entries\n' > "$TELEMETRY_FILE"
  record gp107_telemetry "NOT_AVAILABLE:no-matching-gp107-drm-node"
fi

# --- 5. Kernel log — read-only, але може містити ідентифікатори: редагувати. ---
if command -v dmesg >/dev/null 2>&1 && dmesg -r >/dev/null 2>&1; then
  dmesg 2>/dev/null | grep -Ei 'nouveau|nvidia|drm' | tail -300 > "$OUT/11-kernel-log-private.txt" || true
  record kernel_log "collected:PRIVATE_REDACTION_REQUIRED"
else
  printf 'NOT_AVAILABLE: dmesg permission or command\n' > "$OUT/11-kernel-log-private.txt"
  record kernel_log "NOT_AVAILABLE:permission-or-absent"
fi

# --- 6. Manifest. Жоден файл у OUT більше не змінюється після цього місця. ---
MANIFEST="$OUT/99-manifest.txt"
{
  echo "# GP107 matrix evidence, зібрано $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# target=$TARGET_STATE"
  echo "# mode=$([ "$ALLOW_GRAPHICS_INIT" -eq 1 ] && echo graphics-opt-in || echo passive-inventory-only)"
  echo "# private: review 11-kernel-log-private.txt and local paths before publication"
} > "$MANIFEST"
for f in "$OUT"/*.txt; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = "99-manifest.txt" ] && continue
  printf '%s  %s\n' "$(sha256sum "$f" | awk '{print $1}')" "$base" >> "$MANIFEST"
done

# Self-check виводиться в stdout; нічого не дописуємо в evidence після hashing.
if bash "$ROOT/scripts/test-evidence-manifest.sh" "$MANIFEST"; then
  note manifest "self-check OK"
else
  echo "COLLECT-FAIL: власний маніфест не проходить перевірку" >&2
  exit 2
fi

note summary "$STATUS"
echo "COLLECT-OK dir=$OUT"
