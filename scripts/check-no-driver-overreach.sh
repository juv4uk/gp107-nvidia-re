#!/usr/bin/env bash
# check-no-driver-overreach.sh — межа research-контракту відкритого драйвера.
#
# За зразком wsm-lazarus/scripts/check-no-lcl.sh: заборона перевіряє КОД,
# а не текст пояснень у коментарях. Цей firewall не додає нових прав і не
# змінює authoritative ABI. Він лише гарантує, що research-контракт не
# виходить за межу identity-свідка в MMIO/BAR0.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

strip_pascal_comments() {
  awk '
  {
    line = $0
    while (match(line, /\{[^\}]*\}/))
      line = substr(line, 1, RSTART - 1) substr(line, RSTART + RLENGTH)
    sub(/\/\/.*$/, "", line)
    print line
  }' "$@"
}

# 1) Заборонені операції в КОДІ нового еміттера. Старі RM-зонди вже мають
#    власний firewall у scripts/test-pascal-probe.sh; тут ми не послаблюємо
#    і не подвоюємо його, а перевіряємо межу саме research-контракту.
emit=pascal/04_capability_identity.pas
if [ -f "$emit" ]; then
  strip_pascal_comments "$emit" \
    | grep -nHE '\b(PROT_WRITE|MAP_FIXED|FpWrite|pwrite|nva)\b' >>"$tmp" || true
fi
if [ -s "$tmp" ]; then
  echo 'DRIVER-FIREWALL-FAIL banned-ops:' >&2
  cat "$tmp" >&2
  fail=1
fi

# 2) Заборонені твердження в коді еміттера: гіпотеза BOOT0 і атестація.
: >"$tmp"
if [ -f "$emit" ]; then
  strip_pascal_comments "$emit" | grep -nHE '137000A1|Tested-by' >>"$tmp" || true
fi
if [ -s "$tmp" ]; then
  echo 'DRIVER-FIREWALL-FAIL banned-claims:' >&2
  cat "$tmp" >&2
  fail=1
fi

# 3) Документ не може бути ABI-авторитетом: у research-репо не має бути
#    жодного pin-файлу target-контракту.
if git ls-files | grep -E '(^|/)(target-abi-pin\.lisp|wsm-target-contract)' >/dev/null; then
  echo 'DRIVER-FIREWALL-FAIL authoritative-pin-file-tracked' >&2
  fail=1
fi

if [ "$fail" -eq 1 ]; then
  echo 'DRIVER-FIREWALL-FAIL: research-контракт вийшов за identity-межу.' >&2
  exit 1
fi
echo 'DRIVER-FIREWALL-OK banned-ops=absent boot0-value=absent attestation=absent pin-file=absent'
