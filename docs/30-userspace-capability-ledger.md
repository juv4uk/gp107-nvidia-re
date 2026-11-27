# 30 — Другий зріз C-драйвера: PCI config-header і capability-ledger

Цей документ описує userspace PCI identity та машиночитаний ledger.
**Фізичний MMIO НЕ АВТОРИЗОВАНИЙ / НЕ ВИКОНУВАВСЯ.** Наявність CLI-прапорця
не є дозволом власника. SENS, CML, `wsm-os-lisp`, ADR, target contract і
ABI-pin не змінено.

## 1. Що додано

1. Декодування публічного PCI config-header (Standard Configuration Header,
   тип `0x00`, offsets `0x00–0x0f`) власним C-кодом:
   `revision`, `class_code[3]`, `header_type`, `command`, сирий BAR0-dword,
   біти `space`/`width`/`prefetch` і маскована BAR0-адреса.
   Джерело — публічна специфікація PCI, **не** vendor source і не REA-псевдокод.
2. `lib/gp107_capabilities.h/.c` — машиночитаний ledger, який не підвищує
   inventory facts до прав на апертурний доступ.
3. CLI `gp107ctl capabilities`, розширені `inventory` та compile-time
   layout assertions: `32 / 68 / 140` байт.

## 2. Правило capability-ledger

| Умова | Стан MMIO | Причина |
|---|---|---|
| kernel driver bound | `denied` | `driver-bound` |
| driver unbound, без CLI-прапорця | `denied` | `owner-authorization-required` |
| driver unbound, із `--allow-mmio` | `denied` | `owner-authorization-required` |

**Жодного стану `granted` для фізичного MMIO немає.** Прапорець
`--allow-mmio` не є owner authorization. API `gp107_mmio_read32()`
безумовно повертає `NOT_AUTHORIZED`, не відкриває `resource0` і не викликає
`mmap`; це стосується як CLI, так і прямого C caller.

## 3. Статус фактів

| # | Факт | Статус | Свідок / межа |
|---:|---|---|---|
| 1 | Розкладки `32/68/140` байт | **statically proven** | `_Static_assert`; `LAYOUT-OK identity=32 binding=68 inventory=140` |
| 2 | На дослідному host: `revision=0xa1`, `class=0x030000`, `header=0x80`, `command=0x0407`, BAR0 `0xee000000`, memory / 32-bit / non-prefetch | **runtime-proven** | `gp107ctl inventory` через sysfs config |
| 3 | Назва `0x030000) як VGA display controller та інтерпретація `header=0x80) | **interpretation / UNPROVEN** | Код виводить сирі байти; семантика не керує діями |
| 4 | I/O-прапорець BAR0 (`0x01`) декодується як `space=io`, потім відновлюється | **runtime-proven (fixture)** | `BAR-FLAG-MUTATION-OK space=memory -> io -> memory` |
| 5 | Ledger з `nvidia` bound відмовляє в MMIO | **runtime-proven (fixture + host inventory)** | `mmio-read=denied reason=driver-bound` |
| 6 | Ledger з unbound fixture відмовляє і без, і з `--allow-mmio` | **runtime-proven (fixture)** | `owner-authorization-required`; прапорець не змінює стан |
| 7 | Невалідний або обрізаний `driver` symlink не прирівнюється до unbound | **runtime-proven (fixture)** | `driver-link-unknown` / `driver-link-invalid` |
| 8 | Прямий C API виклик не відкриває і не мапить ресурс | **runtime-proven (synthetic direct caller)** | `NOT_AUTHORIZED`; у `gp107_mmio.c` немає mapping call |
| 9 | `PCI BDF ↔ RM gpu_id`, RM class/runlist/notifier/fence, BOOT0 | **UNPROVEN** | У цьому кодовому зрізі немає RM-шляху; BOOT0 не читався |
| 10 | `0x137000A1) | **string-only** | Константа відсутня у коді й у виводі |
| 11 | Ledger є capability word у Lisp-машині / частина ABI | **UNPROVEN, не стверджується** | Owner-рішення про ABI не ухвалено; S-вираз лише проєкція стану |

Збіг `revision=0xa1` із молодшим байтом відомого рядка лишається
**interpretation** і не підвищує BOOT0 до `runtime-proven`.

## 4. Перевірка

```bash
make test-capability-driver
```

Гейт компілює C11 із `-Werror`, перевіряє layout assertions, synthetic sysfs
identity positives/negatives, malformed driver-link handling, capability
ledger та неможливість обійти MMIO denial через CLI або прямий C API.

Очікуваний підсумковий маркер:

`CAPABILITY-DRIVER-GATE-OK c11=yes layout=32/68/140 negatives=10 mmio=physical-not-authorized hardware-mmio=NOT-RUN`.

Фізичне читання BAR0 не виконується. `--allow-mmio) не змінює цього статусу.

## 5. Межі та наступний крок

`PCI BDF ↔ RM gpu_id`, RM class/runlist, notifier/fence, BOOT0 і безпечні
BAR0 offsets лишаються `UNPROVEN). Поточний API не містить шляху до фізичного
MMIO. Подальша робота має бути source-only: exact package provenance, bounded
REA caller tracing і звірка відкритого Nouveau/NVK source. Фізичне дослідження
можна переглядати лише після окремого owner-рішення та незалежного review
конкретного безпечного регістру.

Межі: жодного ABI/SENS/CML change, transfer-коду, release/tag/publish,
installer-змін, RM/UVM ioctl, firmware, driver unbind, reboot, GPU workload
чи запуску PR #21.
