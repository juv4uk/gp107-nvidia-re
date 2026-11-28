#!/usr/bin/env bash
# Behavioral guard: the read-only evidence collector must not initialize GPU APIs,
# and its final manifest must still verify after the collector exits.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat > "$WORK/bin/vulkaninfo" <<'STUB'
#!/usr/bin/env bash
printf 'vulkaninfo invoked\n' >> "$GPU_RUNTIME_MARKER"
exit 99
STUB
cat > "$WORK/bin/glxinfo" <<'STUB'
#!/usr/bin/env bash
printf 'glxinfo invoked\n' >> "$GPU_RUNTIME_MARKER"
exit 99
STUB
chmod +x "$WORK/bin/vulkaninfo" "$WORK/bin/glxinfo"

export GPU_RUNTIME_MARKER="$WORK/gpu-runtime-invoked"
export PATH="$WORK/bin:$PATH"
OUT="$WORK/evidence"

bash "$ROOT/scripts/collect-gp107-matrix-evidence.sh" "$OUT" > "$WORK/collector.log"

if [ -e "$GPU_RUNTIME_MARKER" ]; then
  echo "MATRIX-COLLECTOR-FAIL: GPU runtime command was invoked" >&2
  cat "$GPU_RUNTIME_MARKER" >&2
  exit 1
fi

grep -Fxq 'gpu_runtime=NOT_RUN:owner-approval-required' "$OUT/00-status.txt"
grep -Fxq 'renderer=NOT_RUN:owner-approval-required' "$OUT/00-status.txt"
grep -Fxq 'NOT_RUN: owner-approved runtime session required' "$OUT/05-gpu-runtime.txt"
grep -Fxq 'NOT_RUN: owner-approved runtime session required' "$OUT/07-renderer.txt"

# Verify from outside the collector too: no status file may mutate after hashing.
bash "$ROOT/scripts/test-evidence-manifest.sh" "$OUT/99-manifest.txt" > "$WORK/manifest.log"
grep -Fq 'MANIFEST-OK' "$WORK/manifest.log"

echo "MATRIX-COLLECTOR-OK gpu-runtime=NOT_RUN manifest=verified"
