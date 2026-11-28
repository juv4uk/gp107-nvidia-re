#!/usr/bin/env bash
# Кожне посилання з docs/ на evidence/ мусить вказувати на реальний файл.
#
# Маніфести перевіряють SHA-256 артефактів (test-evidence-manifest.sh), але ніщо не
# перевіряло, що документ посилається на артефакт, який існує. Через це застаріле
# або перейменоване evidence могло лишитися в тексті як цитата-привид: документ
# виглядає обґрунтованим, а доказу за ним немає.
#
# Перевіряються лише шляхи виду evidence/<...> у docs/*.md. Каталоги дозволені
# (посилання на теку з кількома артефактами), файли — мають існувати.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "DOC-EVIDENCE-FAIL: $*" >&2; exit 2; }
note() { echo "doc-evidence: $*"; }

shopt -s nullglob
docs=(docs/*.md)
[ "${#docs[@]}" -gt 0 ] || fail "немає docs/*.md; перевірка пройшла б порожньо"

checked=0
problems=0
declare -A seen=()

for doc in "${docs[@]}"; do
  while read -r ref; do
    [ -n "$ref" ] || continue
    [ -n "${seen[$ref]:-}" ] && continue
    seen[$ref]=1
    checked=$((checked + 1))
    if [ ! -e "$ref" ]; then
      printf '%s: посилається на відсутнє %s\n' "$doc" "$ref" >&2
      problems=$((problems + 1))
    fi
  done < <(grep -o 'evidence/[A-Za-z0-9._/-]*' "$doc" | sort -u || true)
done

[ "$checked" -gt 0 ] || fail "у docs/ немає жодного посилання на evidence/; перевірка нічого не доводить"

if [ "$problems" -ne 0 ]; then
  fail "$problems посилань у docs/ ведуть на неіснуючі evidence-шляхи"
fi

note "$checked унікальних посилань на evidence/ у ${#docs[@]} документах, усі існують"
