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

export GP107_EXPECTED_BDF="$BDF"
export DRI_PRIME="pci-$DRI_BDF!"

printf 'GP107-VK-COMPUTE-SELECT bdf=%s dri_prime=%s\n' "$GP107_EXPECTED_BDF" "$DRI_PRIME"
exec "$BIN" "$SPIRV"
