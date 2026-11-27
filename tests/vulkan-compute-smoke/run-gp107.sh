#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -ge 1 ]; then BIN=$1; else BIN="$ROOT/gp107-vk-compute-smoke"; fi
if [ "$#" -ge 2 ]; then SPIRV=$2; else SPIRV="$ROOT/vector_add.comp.spv"; fi

command -v lspci >/dev/null 2>&1 || {
    echo "GP107-VK-COMPUTE-NOT-AVAILABLE reason=missing-pciutils" >&2
    exit 77
}

BDFS=$(lspci -Dnn -d 10de:1c82 | awk '{print $1}')
COUNT=$(printf '%s\n' "$BDFS" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

[ "$COUNT" = "1" ] || {
    echo "GP107-VK-COMPUTE-NOT-AVAILABLE reason=gpu-count-$COUNT expected=1" >&2
    exit 77
}

BDF=$(printf '%s\n' "$BDFS" | sed -n '1p')
DRI_BDF=$(printf '%s' "$BDF" | tr ':.' '__')

SYSFS_DRIVER="/sys/bus/pci/devices/$BDF/driver"
[ -L "$SYSFS_DRIVER" ] || {
    echo "GP107-VK-COMPUTE-NOT-AVAILABLE reason=nouveau-not-bound-to-target" >&2
    exit 77
}
KERNEL_DRIVER=$(basename "$(readlink -f "$SYSFS_DRIVER")")
[ "$KERNEL_DRIVER" = "nouveau" ] || {
    echo "GP107-VK-COMPUTE-NOT-AVAILABLE reason=kernel-driver-$KERNEL_DRIVER expected-nouveau" >&2
    exit 77
}

export GP107_EXPECTED_BDF="$BDF"
export DRI_PRIME="pci-$DRI_BDF!"

printf 'GP107-VK-COMPUTE-SELECT bdf=%s dri_prime=%s\n' "$GP107_EXPECTED_BDF" "$DRI_PRIME"
command -v sha256sum >/dev/null 2>&1 || {
    echo "GP107-VK-COMPUTE-NOT-AVAILABLE reason=missing-sha256sum" >&2
    exit 77
}
sha256sum "$SPIRV"
exec "$BIN" "$SPIRV"
