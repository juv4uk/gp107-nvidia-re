#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'PREFLIGHT: NOT_READY: %s\n' "$*" >&2
    exit 1
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

need_command lspci
need_command modinfo
need_command uname
need_command grep
need_command awk
need_command readlink
need_command basename
need_command cat
need_command cut
need_command tail

KREL="$(uname -r)"
printf 'KERNEL: %s\n' "$KREL"

CONFIG_VALUE=""
CONFIG_SOURCE=""
CONFIG_FILE="/boot/config-$KREL"

if [[ -r "$CONFIG_FILE" ]]; then
    CONFIG_SOURCE="$CONFIG_FILE"
    CONFIG_VALUE="$(grep -E '^CONFIG_NOUVEAU_DEBUG=' "$CONFIG_FILE" | tail -n 1 || true)"
fi

if [[ -z "$CONFIG_VALUE" && -r /proc/config.gz ]] &&
   command -v zgrep >/dev/null 2>&1; then
    CONFIG_SOURCE="/proc/config.gz"
    CONFIG_VALUE="$(zgrep -E '^CONFIG_NOUVEAU_DEBUG=' /proc/config.gz | tail -n 1 || true)"
fi

[[ -n "$CONFIG_SOURCE" ]] || fail "kernel config unavailable; cannot verify CONFIG_NOUVEAU_DEBUG"
[[ -n "$CONFIG_VALUE" ]] || fail "CONFIG_NOUVEAU_DEBUG is unset or not present in $CONFIG_SOURCE"

DEBUG_LEVEL="$(printf '%s' "$CONFIG_VALUE" | cut -d= -f2)"
[[ "$DEBUG_LEVEL" =~ ^[0-9]+$ ]] || fail "unexpected CONFIG_NOUVEAU_DEBUG value: $CONFIG_VALUE"
printf 'NOUVEAU_DEBUG: %s (source=%s)\n' "$DEBUG_LEVEL" "$CONFIG_SOURCE"

if (( DEBUG_LEVEL < 5 )); then
    fail "TRACE requires CONFIG_NOUVEAU_DEBUG >= 5; found $DEBUG_LEVEL"
fi

MODULE_PARAMS="$(modinfo -p nouveau 2>/dev/null || true)"
if ! awk -F: '$1 == "debug" { found = 1 } END { exit !found }' <<<"$MODULE_PARAMS"; then
    fail "installed nouveau module does not advertise the debug parameter"
fi
printf 'MODULE_PARAMETER: nouveau.debug available\n'

if [[ -r /sys/module/nouveau/parameters/debug ]]; then
    printf 'LOADED_MODULE_DEBUG: '
    cat /sys/module/nouveau/parameters/debug
else
    printf 'LOADED_MODULE_DEBUG: module not currently loaded (read-only observation)\n'
fi

GP107_LIST="$(lspci -Dnn -d 10de:1c82 | awk '{print $1}')"
GP107_COUNT="$(printf '%s\n' "$GP107_LIST" | awk 'NF { n++ } END { print n+0 }')"
if [[ "$GP107_COUNT" != "1" ]]; then
    printf 'GP107 PCI matches: %s\n%s\n' "$GP107_COUNT" "$GP107_LIST" >&2
    fail "expected exactly one PCI 10de:1c82 device"
fi

BDF="$(printf '%s\n' "$GP107_LIST" | awk 'NF { print $1; exit }')"
SYSFS_DEVICE="/sys/bus/pci/devices/$BDF"
[[ -e "$SYSFS_DEVICE" ]] || fail "sysfs device missing for $BDF"

printf 'GPU: %s (10de:1c82)\n' "$BDF"
if [[ -r "$SYSFS_DEVICE/vendor" && -r "$SYSFS_DEVICE/device" ]]; then
    printf 'SYSFS_ID: vendor=%s device=%s\n' \
        "$(cat "$SYSFS_DEVICE/vendor")" "$(cat "$SYSFS_DEVICE/device")"
fi
for FIELD in subsystem_vendor subsystem_device revision; do
    if [[ -r "$SYSFS_DEVICE/$FIELD" ]]; then
        printf 'SYSFS_%s: %s\\n' "$FIELD" "$(cat "$SYSFS_DEVICE/$FIELD")"
    fi
done

DRIVER_LINK="$(readlink -f "$SYSFS_DEVICE/driver" 2>/dev/null || true)"
if [[ -n "$DRIVER_LINK" ]]; then
    printf 'CURRENT_KERNEL_DRIVER: %s\n' "$(basename "$DRIVER_LINK")"
else
    printf 'CURRENT_KERNEL_DRIVER: none (read-only observation)\n'
fi

printf '\nPREFLIGHT: READY\n'
printf 'ONE_BOOT_ARGUMENT: nouveau.debug=TOP=trace\n'
printf '%s\n' \
  'Use only in a separate rollback-capable native-Linux test boot.' \
  'Do not edit persistent GRUB/initramfs/module configuration with this script.' \
  'After boot, capture the full kernel log and keep the raw file unchanged:'
cat <<'EOF'
  journalctl -b -k -o short-monotonic --no-pager > nouveau-top-trace.log
  grep -Ei 'top:|runlist|nvkm|engine.*(GR|CE)' nouveau-top-trace.log
EOF
printf '%s\n' \
  'Accept decoded TOP records for GR and CE* only when they include engine/type/instance/runlist.' \
  'If decoded TOP rows are absent, record RUNLIST_ID_NOT_OBSERVED; do not infer a value.' \
  'This script performed read-only checks only; it did not change boot, drivers, firmware, or GPU registers.'
