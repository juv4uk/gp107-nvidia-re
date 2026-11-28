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

check_one() {
  local m="$1"
  if is_negative_control "$m"; then
    # Субшелл: verify_manifest кличе fail -> exit, і це не має вбивати прогін.
    if ( verify_manifest "$m" ) >/dev/null 2>&1; then
      fail "негативний контроль пройшов перевірку, а не мав: $m"
    fi
    echo "MANIFEST-NEGATIVE-OK manifest=${m#$ROOT/} (очікувана відмова)"
    return 0
  fi
  verify_manifest "$m"
}

if [ "$#" -gt 0 ]; then
  for m in "$@"; do check_one "$m"; done
else
  while IFS= read -r m; do check_one "$m"; done < <(git ls-files '*99-manifest.txt')
fi
