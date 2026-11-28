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
    # Шлях у маніфесті може бути абсолютним (тоді достатньо basename у каталозі
    # маніфесту) або відносним до кореня експерименту, як у
    # experiments/*/artifacts-*/99-manifest.txt. Резолвимо в цьому порядку, і
    # лише потім вважаємо артефакт відсутнім.
    file=""
    for candidate in "$dir/$path" "$dir/../$path" "$dir/$name"; do
      if [ -r "$candidate" ]; then file="$candidate"; break; fi
    done
    [ -n "$file" ] || fail "нема артефакту $path для $manifest"
    got="$(sha256sum "$file" | awk '{print $1}')"
    [ "$got" = "$hash" ] || fail "SHA-256 розбіжність $name у $manifest: expected=$hash got=$got"
    count=$((count + 1))
  done <"$manifest"
  [ "$count" -gt 0 ] || fail "маніфест без перевірених артефактів: $manifest"
  echo "MANIFEST-OK manifest=${manifest#$ROOT/} files=$count"
}

# Каталог, чиє ім'я закінчується на -negative, містить контрольні маніфести, які
# ЗОБОВ'ЯЗАНІ не пройти перевірку. Раніше вони валили весь тест, тому скрипт
# не можна було запускати в CI: негативний контроль виглядав як поломка.
is_negative_control() {
  case "${1%/*}" in
    *-negative|*-negative/) return 0 ;;
    *) return 1 ;;
  esac
}

EXCEPTIONS_FILE="$ROOT/scripts/manifest-exceptions.txt"

# Записані винятки: маніфест, який сьогодні не може верифікуватися, лишається
# видимим боргом, а не тихо пропускається. Перевірка двостороння: якщо виняток
# почав верифікуватися — це помилка, рядок треба прибрати.
exception_reason() {
  [ -r "$EXCEPTIONS_FILE" ] || return 1
  awk -F'\t' -v p="$1" '$1==p {print $2; found=1} END {exit !found}' "$EXCEPTIONS_FILE"
}

OK_COUNT=0
KNOWN_BAD_COUNT=0
NEGATIVE_COUNT=0

check_one() {
  local m="$1" rel reason
  rel="${m#$ROOT/}"
  if reason="$(exception_reason "$rel")"; then
    if ( verify_manifest "$m" ) >/dev/null 2>&1; then
      fail "виняток застарів: $rel тепер верифікується — приберіть його з scripts/manifest-exceptions.txt"
    fi
    echo "MANIFEST-KNOWN-BAD manifest=$rel reason=$reason"
    KNOWN_BAD_COUNT=$((KNOWN_BAD_COUNT + 1))
    return 0
  fi
  if is_negative_control "$m"; then
    # Субшелл: verify_manifest кличе fail -> exit, і це не має вбивати прогін.
    if ( verify_manifest "$m" ) >/dev/null 2>&1; then
      fail "негативний контроль пройшов перевірку, а не мав: $m"
    fi
    echo "MANIFEST-NEGATIVE-OK manifest=${m#$ROOT/} (очікувана відмова)"
    NEGATIVE_COUNT=$((NEGATIVE_COUNT + 1))
    return 0
  fi
  verify_manifest "$m"
  OK_COUNT=$((OK_COUNT + 1))
}

if [ "$#" -gt 0 ]; then
  for m in "$@"; do check_one "$m"; done
else
  while IFS= read -r m; do check_one "$m"; done < <(git ls-files '*99-manifest.txt')
fi


# Один рядок-підсумок, щоб у логах CI було видно масштаб, а не 150 рядків.
printf 'MANIFEST-SUMMARY verified=%s known_bad=%s negative_controls=%s\n' \
  "$OK_COUNT" "$KNOWN_BAD_COUNT" "$NEGATIVE_COUNT"
