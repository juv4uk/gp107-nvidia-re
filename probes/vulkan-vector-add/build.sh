#!/usr/bin/env bash
# Source/build-only validation. No GPU is touched here.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

: "${VULKAN_INCLUDEDIR:=/usr/include}"
: "${VULKAN_LIBDIR:=/usr/lib/x86_64-linux-gnu}"

command -v cc >/dev/null || { echo "BUILD-FAIL step=cc" >&2; exit 2; }
test -f "$VULKAN_INCLUDEDIR/vulkan/vulkan.h" || {
  echo "BUILD-FAIL step=vulkan-headers path=$VULKAN_INCLUDEDIR/vulkan/vulkan.h" >&2
  exit 2
}
test -e "$VULKAN_LIBDIR/libvulkan.so.1" || {
  echo "BUILD-FAIL step=vulkan-loader path=$VULKAN_LIBDIR/libvulkan.so.1" >&2
  exit 2
}

cc -std=c11 -O2 -Wall -Wextra -Werror \
  -I"$VULKAN_INCLUDEDIR" \
  vector_add.c -o vector_add \
  -L"$VULKAN_LIBDIR" -l:libvulkan.so.1

if command -v glslangValidator >/dev/null 2>&1; then
  glslangValidator -V --target-env vulkan1.2 vector_add.comp -o vector_add.spv
  echo "BUILD-OK spv=compiled"
else
  echo "BUILD-OK spv=NOT_COMPILED reason=glslangValidator-missing"
fi
