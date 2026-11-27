# 30 — Другий зріз C-драйвера: публічний PCI-заголовок і capability-ledger

Це розширення `docs/29`: userspace capability-identity, read-only sysfs,
програмний opt-in gate, який не виконує BAR0 read. Фізичний MMIO, unbind і зміна
boot не авторизовані. Тут
**нема** RM-запитів, write mapping, GPFIFO, firmware, dispatch, reboot чи
змін ABI/pin. SENS, CML, `wsm-os-lisp`, ADR і target contract не змінено.

## 1. Що додано

1. Декодування публічного PCI config-header (Standard Configuration Header,
   тип `0x00`, offsets `0x00–0x0f`) власним C-кодом:
   `revision`, `class_code[3]`, `header_type`, `command`, сирий BAR0-dword,
   біти `space`/`width`/`prefetch` RAW-маскованої адреси BAR0.
   Джерело — публічна специфікація PCI, **не** vendor source і не REA-псевдокод.
2. `lib/gp107_capabilities.h/.c` — машиночитаний ledger з явними станами
   `deferred`, `denied` і причинами.
3. CLI `gp107ctl capabilities [--allow-mmio]`, розширені `inventory` і
   compile-time assertи: нові розкладки `32 / 68 / 140` байт.

Логіка MMIO-стану в ledger:

| Умова | Стан | Причина |
|---|---|---|
| bound kernel driver | `denied` | `driver-bound` |
| не bound, але немає `--allow-mmio` | `deferred` | `opt-in-required` |
| не bound і є `--allow-mmio` | `deferred` | `read-safe-offset-unproven` |

`--allow-mmio` не створює стану `granted`: жоден безпечний BAR0 register
offset не доведений. Ledger друкує `owner-approval=not-inferred` та
`physical-mmio=not-authorized`; ці поля не можна підвищувати за opt-in.
Public API завершується fail-closed до відкриття `resource0`, mapping чи
будь-якого register read.

## 2. Статус фактів

| # | Факт | Статус | Свідок / межа |
|---:|---|---|---|
| 1 | Розкладки `32/68/140` байт | **statically proven** | `_Static_assert`; `LAYOUT-OK identity=32 binding=68 inventory=140` |
| 2 | На RE host із sysfs: `revision=0xa1`, `class=0x030000`, `header=0x80`, `command=0x0407`, BAR0 `0xee000000`, memory / 32-bit / non-prefetch | **sysfs-observation** | `gp107ctl inventory` з host sysfs `config`; це не H170 certification |
| 3 | Інтерпретація `0x030000` як «VGA display controller» і `0x80` як «PCI-to-PCI bridge header» — половина класу | **interpretation / UNPROVEN** | Код друкує сирі байти; назва типу заголовка не використовується для жодної дії |
| 4 | I/O-прапорець BAR0 (`0x01`) декодується як `space=io`, після мутації повертається `memory` | **synthetic-fixture** | `BAR-FLAG-MUTATION-OK space=memory -> io -> memory` |
| 5 | Ledger з `nvidia` bound: software gate `denied`, owner approval `not-inferred` | **synthetic-fixture + окреме host sysfs observation** | `LEDGER-BOUND-OK`; реальний `--allow-mmio` не запускався |
| 6 | Ledger unbound без opt-in: `deferred/opt-in-required`; з opt-in: `deferred/read-safe-offset-unproven`; `granted` відсутній | **synthetic-fixture** | `LEDGER-DEFERRED-OK`, `LEDGER-SAFE-OFFSET-DEFERRED-OK`; жодного register read |
| 7 | `PCI BDF ↔ RM gpu_id`, RM class/runlist/notifier/fence, BOOT0 | **UNPROVEN** | У коді немає RM-шляху; BOOT0 не читався |
| 8 | `0x137000A1` | **string-only** | константа відсутня у коді й у виводі |
| 9 |Ledger є capability word у Lisp-машині / частина ABI | **UNPROVEN, не стверджується** | owner-рішення про ABI не ухвалено; S-вираз лише проєкція стану |

Збіг `revision=0xa1` із молодшим байтом відомого рядка лишається
**interpretation** і не підвищує BOOT0 до `runtime-proven`.

## 3. Перевірка

```bash
make test-capability-driver
```

Окрім попередніх кроків, гейт перевіряє три стани ledger, декодування
прапорців BAR0 на мутованому fixture і збереження compile-time розкладок.
Фінальний маркер:
`CAPABILITY-DRIVER-GATE-OK c11=yes fpc=3.2.2 layout=32/68/140 fail-closed=passed mmio=deferred safe-offset=unproven pascal=C-parity hardware-mmio=NOT-AUTHORIZED/NOT-RUN`.

Базовий `scripts/test-pascal-probe.sh` і `make test-valid-cards-static` не
змінено. Фізичний MMIO на цій платі не виконувався: `nvidia` лишається bound.

## 4. Найменший наступний крок

Питання без відповіді: який саме BAR0-offset безпечно читати на цій платі?
Код свідомо не містить припущення про адресу регістру й відмовляє до будь-якого
mapping. Наступний безпечний крок — source-only аудит публічних register
semantics. Фізичний тест не запускається без окремого owner approval; BOOT0
лишaється `UNPROVEN`.

Межі: жодного transfer-коду, release/tag/publish, `Tested-by`, installer-змін,
RM-запитів чи запуску PR #21.
