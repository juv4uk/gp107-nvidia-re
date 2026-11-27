# 29 — Userspace capability-identity драйвер: перший зріз коду

Це **перший виконуваний код** у напрямку «драйвер», обраний власником у цій
сесії: userspace capability-identity бібліотека C з жорсткою fail-closed
інвентаризацією sysfs. Це **не** ABI, не kernel-модуль, не RM/GPFIFO-шлях і не
заміна `nvidia.ko`. SENS, CML, `wsm-os-lisp`, ADR, target contract і ABI-pin v8
не змінено.

## 0. Межа owner-дозволу

У цій сесії власник явно дозволив MMIO для першого коду. Дозвіл реалізовано
**найвужче**:

- MMIO-сеам є окремим модулем і не активний за замовчуванням;
- потрібен явний прапорець `--allow-mmio`;
- відмова, якщо пристрій має bound kernel driver (зараз `nvidia`);
- тільки read-only mapping одного вирівняного вікна й читання 32-бітового слова;
- жодного write mapping, RM-запиту, FIFO, doorbell, firmware чи reboot.

Фізичний MMIO на цій платі **не виконувався**: поточний boot пропрієтарний,
`Kernel driver in use: nvidia`, `/proc/cmdline` без `wsm_open_driver=1`.
Перехід у `wsm_open_driver=1`, unbind/зміна драйвера або фізичний aperture-тест
потребують **окремої owner-дії**.

## 1. Що додано

| Файл | Призначення |
|---|---|
| `lib/gp107_identity.h/.c` | FAIL-CLOSED sysfs inventory: vendor/device, BDF, публічний PCI-заголовок (revision/class/header/command/BAR0-flags), driver binding, розмір resource0 |
| `lib/gp107_capabilities.h/.c` | Машиночитаний capability-ledger з явними `granted`/`deferred`/`denied` (додано у docs/30) |
| `lib/gp107_mmio.h/.c` | Опційний read-only 32-бітний aperture seam з двома воротами (opt-in + driver-unbound) |
| `lib/gp107ctl.c` | CLI `inventory`, `mmio-read`, `layout`; названі маркери помилок |
| `lib/Makefile` | C11 build з `-Wall -Wextra -Werror -pedantic` |
| `scripts/test-capability-driver.sh` | названі кроки, 5 негативних witness, firewall коду, best-effort host inventory |
| `docs/29-userspace-capability-driver.md` | цей звіт |

Публічний контракт:

```c
int gp107_inventory_scan(const char *sysfs_root, const char *expect_bdf,
                         struct gp107_inventory *out, char *err, size_t errsz);

int gp107_mmio_require_optin(int allow, char *err, size_t errsz);
int gp107_mmio_check_driver(const struct gp107_inventory *inv,
                            char *err, size_t errsz);
int gp107_mmio_read32(const char *sysfs_root, const char *bdf,
                      uint32_t offset, uint32_t *value,
                      char *err, size_t errsz);
```

Виклик `gp107ctl` друкує людиночитану S-подібну проєкцію фактів, поки не
ухвалене owner-рішення про ABI. Це не capability word у Lisp-машині.

## 2. Статус фактів

| # | Факт | Статус | Свідок / межа |
|---:|---|---|---|
| 1 | Розкладки `gp107_pci_identity=32`, `gp107_driver_binding=68`, `gp107_inventory=140` байт | **statically proven** | `_Static_assert` у `lib/gp107_identity.h`; вивід `LAYOUT-OK identity=32 binding=68 inventory=140` (розширено у docs/30) |
| 2 | На hostі рівно одна картка `10de:1c82 @ 0000:01:00.0`, `bar0-base=0xee000000`, driver `nvidia` | **runtime-proven** | `gp107ctl inventory` через sysfs; маркер `HOST-INVENTORY-PASS evidence=runtime-proven` |
| 3 | Друга картка того самого vendor/device відхиляється | **runtime-proven (fixture)** | `IDENTITY-FAIL step=card-count code=13 count=2` |
| 4 | Відсутній `config` відхиляється | **runtime-proven (fixture)** | `IDENTITY-FAIL step=pci-config-read code=5 bdf=...` |
| 5 | Чужий BDF відхиляється | **runtime-proven (fixture)** | `IDENTITY-FAIL step=bdf-mismatch code=14` |
| 6 | MMIO без прапорця відхиляється до будь-якого mapping | **runtime-proven (fixture)** | `MMIO-FAIL step=opt-in-required code=15` |
| 7 | MMIO з bound драйвером відхиляється | **runtime-proven (fixture)** | `MMIO-FAIL step=driver-bound code=16 driver=nvidia` |
| 8 | Read-only 32-бітне читання з `resource0` | **runtime-proven (синтетичний файл), hardware NOT_RUN** | `MMIO-READ-OK`, `value=0x1c8210de` зі створеного тестом файлу |
| 9 | BOOT0 та будь-яке значення регістру на реальній платі | **UNPROVEN** | фізичний MMIO не виконувався |
| 10 | `0x137000A1` | **string-only** | константа відсутня у коді; не є адресою чи фактом |
| 11 | `PCI BDF ↔ RM gpu_id`, RM class, runlist, notifier, fence, GPFIFO, firmware, dispatch | **UNPROVEN / не реалізовано** | цей зріз не містить RM чи черг |
| 12 | Причина будь-якої відмови ядра / ексклюзивне володіння BAR | **UNPROVEN** | код друкує errno як число, не інтерпретує причину |

Висновок про продуктивність чи «працюючий драйвер» з цього зрізу **не
випливає**: тут немає жодного GPU-завдання.

## 3. Що перевіряє гейт

```bash
make -C lib clean all
bash scripts/test-capability-driver.sh
make test-valid-cards-static   # старий базовий гейт не послаблено
```

`scripts/test-capability-driver.sh` виконує:

1. `bash -n` обох нових/сусідніх gating-скриптів;
2. firewall **коду** `lib/*.c`, `lib/*.h`: заборонені write mapping, RM-імена,
   BOOT0-константа, атестація й authoritative pin;
3. C11 compile з `-Werror` і перевірку трьох compile-time розкладок;
4. синтетичний sysfs fixture: позитив і три identity-негативи;
5. три стани capability-ledger (`denied`/`deferred`/`granted`) і мутація
   I/O-прапорця BAR0;
6. два MMIO-негативи й один read-only позитив на синтетичному `resource0`;
7. best-effort реальний sysfs inventory (пропуск явно позначається, якщо
   пристрою немає).

Підсумковий маркер:
`CAPABILITY-DRIVER-GATE-OK c11=yes layout=32/68/140 negatives=6 mmio=read-only-opt-in asm=equiv-x86_64 hardware-mmio=NOT-RUN`.

Базовий `scripts/test-pascal-probe.sh` не змінено; він лишається
непривілейованим/детермінованим з `EACCES` на `resource0`.

## 4. Незавершене й найменший наступний крок

- **Питання без відповіді:** який саме offset у BAR0 можна читати безпечно на
  цій платі за відсутності bound драйвера? Поточний код не містить жодного
  припущення про адресу регістру.
- **Найменший крок:** після окремого owner-рішення про unbind/boot — повторити
  той самий `mmio-read` на реальному пристрої з явним `--offset`, записавши
  stdout/stderr як artifact з SHA-256 і позначивши результат як
  `runtime-proven` або fail-closed. Без цього BOOT0 лишається `UNPROVEN`.
- Окремо: мульти-GPU RM fixture для кореляції `PCI BDF ↔ RM gpu_id` не існує;
  цей стан не можна вивести з одного пристрою.

Межі: жодного transfer-коду, release/tag/publish, installer-змін, `Tested-by`,
new harness чи запуску PR #21. Коміт і пуш виконуються завжди.
