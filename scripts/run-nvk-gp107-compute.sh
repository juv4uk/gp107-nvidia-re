#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/nvk-gp107-compute}"
BIN="$BUILD_DIR/nvk-gp107-compute"
SPV="$BUILD_DIR/vector_add.spv"
GATE="$ROOT/probes/vulkan/GP107-FIFO-RISK-CLEARED"

# No enumeration or dispatch before issue #18 has been resolved with exact
# GR/compute TOP runlist evidence and a reviewed decision.
if [[ ! -s "$GATE" ]]; then
    echo "GPU-HARNESS-BLOCKED: resolve GP107 FIFO non-stall issue #18 first." >&2
    echo "Required gate file: $GATE" >&2
    exit 78
fi

"$ROOT/scripts/build-nvk-gp107-compute.sh"

for tool in lspci awk readlink find basename tr sort head; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing runtime tool: $tool" >&2
        exit 2
    fi
done

GP107_LIST="$(lspci -Dnn -d 10de:1c82 | awk '{print $1}')"
GP107_COUNT="$(printf '%s\n' "$GP107_LIST" | awk 'NF { n++ } END { print n+0 }')"
if [[ "$GP107_COUNT" != "1" ]]; then
    echo "Expected exactly one PCI 10de:1c82 device; found $GP107_COUNT." >&2
    printf '%s\n' "$GP107_LIST" >&2
    exit 3
fi

BDF="$(printf '%s\n' "$GP107_LIST" | awk 'NF { print $1; exit }')"
SYSFS_DEVICE="/sys/bus/pci/devices/$BDF"
if [[ ! -e "$SYSFS_DEVICE" ]]; then
    echo "sysfs entry missing for GP107 BDF $BDF." >&2
    exit 3
fi

DRIVER_LINK="$(readlink -f "$SYSFS_DEVICE/driver" 2>/dev/null || true)"
if [[ -n "$DRIVER_LINK" ]]; then
    DRIVER_NAME="$(basename "$DRIVER_LINK")"
else
    DRIVER_NAME="none"
fi
if [[ "$DRIVER_NAME" != "nouveau" ]]; then
    echo "GP107 $BDF is not bound to Nouveau (found: ${DRIVER_NAME:-none})." >&2
    echo "This script will not unbind or replace an active driver." >&2
    exit 4
fi

ICD_LIST=""
for ICD_DIR in /usr/share/vulkan/icd.d /etc/vulkan/icd.d /usr/local/share/vulkan/icd.d; do
    if [[ -d "$ICD_DIR" ]]; then
        while IFS= read -r ICD_PATH; do
            ICD_LIST="$ICD_LIST$ICD_PATH"$'\n'
        done < <(find "$ICD_DIR" -maxdepth 1 -type f -name 'nouveau_icd*.json' -print)
    fi
done

ICD_COUNT="$(printf '%s' "$ICD_LIST" | awk 'NF { n++ } END { print n+0 }')"
if [[ "$ICD_COUNT" != "1" ]]; then
    echo "Expected exactly one Mesa Nouveau Vulkan ICD JSON; found $ICD_COUNT." >&2
    printf '%s\n' "$ICD_LIST" >&2
    exit 5
fi
ICD_FILE="$(printf '%s' "$ICD_LIST" | awk 'NF { print; exit }')"

DRI_BDF="$(printf '%s' "$BDF" | tr ':.' '__')"
export DRI_PRIME="pci-$DRI_BDF!"
export VK_DRIVER_FILES="$ICD_FILE"

printf 'TARGET: %s (10de:1c82), kernel-driver=nouveau\n' "$BDF"
printf 'ICD: %s\n' "$VK_DRIVER_FILES"

STANDARD_STATUS=0
"$BIN" --bdf "$BDF" --enumerate-only || STANDARD_STATUS=$?

case "$STANDARD_STATUS" in
    0)
        # The C binary has its own compile-time fail-closed guard and returns
        # 78 until the FIFO review is explicitly cleared in source.
        exec "$BIN" --bdf "$BDF" --dispatch --spirv "$SPV"
        ;;
    10)
        echo "STANDARD_ENUMERATION: GP107 not exposed; retrying enumeration only with developer override." >&2
        export NVK_I_WANT_A_BROKEN_VULKAN_DRIVER=1
        "$BIN" --bdf "$BDF" --experimental-enumeration-only
        ;;
    *)
        echo "STANDARD_ENUMERATION: failed with exit code $STANDARD_STATUS; no experimental retry." >&2
        exit "$STANDARD_STATUS"
        ;;
esac
