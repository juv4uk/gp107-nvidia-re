#!/usr/bin/env bash
# Перевірка evidence-маніфестів за SHA-256, а не лише за текстовими маркерами.
# Кожен рядок маніфесту "sha256  absolute/path" звіряється з файлом із тим самим
#.basename у каталозі маніфесту. Рядок self-hash 99-manifest.txt пропускається:
# у репозиторії це копія, а не вихідний шлях знімання.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "MANIFEST-FAIL: $*" >&2; exit 2; }

verify_manifest() {
  local manifest="$1" dir name file got count=0
  case "$manifest" in
    /*) ;;
    *) manifest="$ROOT/$manifest" ;;
  esac
  [ -r "$manifest" ] || fail "маніфест недоступний: $manifest"
  dir="${manifest%/*}"
  while read -r hash path _rest; do
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || continue
    name="${path##*/}"
    [ "$name" = "99-manifest.txt" ] && continue
    file="$dir/$name"
    [ -r "$file" ] || fail "нема артефакту $name для $manifest"
    got="$(sha256sum "$file" | awk '{print $1}')"
    [ "$got" = "$hash" ] || fail "SHA-256 розбіжність $name у $manifest: expected=$hash got=$got"
    count=$((count + 1))
  done <"$manifest"
  [ "$count" -gt 0 ] || fail "маніфест без перевірених артефактів: $manifest"
  echo "MANIFEST-OK manifest=${manifest#$ROOT/} files=$count"
}

if [ "$#" -gt 0 ]; then
  for m in "$@"; do verify_manifest "$m"; done
else
  while IFS= read -r m; do verify_manifest "$m"; done < <(git ls-files '*99-manifest.txt')
fi
