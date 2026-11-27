#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/nvk-gp107-compute}"
BIN="$BUILD_DIR/nvk-gp107-compute"
SPV="$BUILD_DIR/vector_add.spv"
SPVASM="$BUILD_DIR/vector_add.spvasm"
SHADER="$ROOT/probes/vulkan/vector_add.comp"
SOURCE="$ROOT/probes/vulkan/nvk_gp107_compute.c"

for tool in cc pkg-config glslangValidator spirv-val spirv-dis sha256sum grep; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 2
    fi
done

if ! pkg-config --exists vulkan; then
    echo "Vulkan development package not found (pkg-config vulkan)." >&2
    exit 2
fi

# Static tripwires: hosted CI must never silently enable physical dispatch.
grep -Fq '#define GP107_FIFO_NONSTALL_REVIEW_CLEARED 0' "$SOURCE" || {
    echo "FIFO safety gate is missing or not fail-closed." >&2
    exit 3
}
grep -Fq 'test_counts[] = {257U, 1048576U}' "$SOURCE" || {
    echo "Required 257 / 1048576 compute test cases are missing." >&2
    exit 3
}
grep -Fq 'QUEUE_FAMILY: index=' "$SOURCE" || {
    echo "Queue-family enumeration output is missing." >&2
    exit 3
}
grep -Fq 'BDF-ASSERTION: PASS' "$SOURCE" || {
    echo "Exact PCI BDF assertion output is missing." >&2
    exit 3
}
grep -Fq 'vkCmdDispatch' "$SOURCE" || {
    echo "vkCmdDispatch call is missing." >&2
    exit 3
}

mkdir -p "$BUILD_DIR"

glslangValidator -V --target-env vulkan1.1 -S comp "$SHADER" -o "$SPV"
spirv-val --target-env vulkan1.1 "$SPV"
spirv-dis "$SPV" -o "$SPVASM"

# shellcheck disable=SC2046
cc -std=c11 -O2 -Wall -Wextra -Werror \
    "$SOURCE" -o "$BIN" \
    $(pkg-config --cflags --libs vulkan)

"$BIN" --help >/dev/null

printf '%s\n' 'BUILD-ONLY: PASS'
sha256sum "$BIN" "$SPV" "$SPVASM"
