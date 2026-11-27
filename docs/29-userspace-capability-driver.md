# 29 — Userspace capability-identity драйвер: перший зріз коду

Це userspace capability-identity бібліотека C з fail-closed
інвентаризацією sysfs — дослідницький кодовий зріз, а не production driver. Це **не** ABI, не kernel-модуль, не RM/GPFIFO-шлях і не
заміна `nvidia.ko`. SENS, CML, `wsm-os-lisp`, ADR, target contract і ABI-pin v8
не змінено.

## 0. Межа owner-дозволу

У цій сесії власник **не надавав дозволу на фізичне MMIO**. Прапорець
`--allow-mmio` — лише програмний opt-in для контрольованого тестового seam;
він не є owner consent і не доводить, що обраний регістр безпечно читати.

- Публічний `gp107_mmio_read32()` самостійно перевіряє opt-in, точний PCI/BDF,
  актуальний стан driver binding, memory BAR0, фактичний розмір `resource0`,
  вирівнювання та межі offset.
- Лише відсутній sysfs `driver` link (`ENOENT`) означає unbound. Пошкоджений,
  нечитабельний або неоднозначний link означає unknown і зупиняє інвентаризацію.
- Binding перевіряється перед mapping і перед читанням, але це best-effort
  recheck, не ексклюзивний lock від конкурентного bind.
- `PROT_READ` забороняє запис через mapping, але не гарантує відсутності
  read-side effects у конкретному регістрі. Жоден read-safe register offset
  для цієї плати поки не доведено.
- Фізичний статус: `PHYSICAL_MMIO=NOT_AUTHORIZED / NOT_RUN`. Не запускати
  aperture read, не робити unbind/driver switch/reboot чи firmware changes
  без окремого рішення власника.

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
int gp107_mmio_read32(const char *sysfs_root, const char *bdf, int allow_mmio,
                      uint32_t offset, uint32_t *value,
                      char *err, size_t errsz);
```

Виклик `gp107ctl` друкує людиночитану S-подібну проєкцію фактів, поки не
ухвалене owner-рішення про ABI. Це не capability word у Lisp-машині.

## 2. Статус фактів

| # | Факт | Статус | Свідок / межа |
|---:|---|---|---|
| 1 | Розкладки `gp107_pci_identity=32`, `gp107_driver_binding=68`, `gp107_inventory=140` байт | **statically proven** | `_Static_assert` у `lib/gp107_identity.h`; вивід `LAYOUT-OK identity=32 binding=68 inventory=140` (розширено у docs/30) |
| 2 | PCI/sysfs спостереження `10de:1c82 @ 0000:01:00.0` | **scope-unclassified** | Скрипт може працювати на runner або fixture; це не evidence саме власної H170-плати |
| 3 | Друга картка того самого vendor/device відхиляється | **fixture-verified** | `IDENTITY-FAIL step=card-count code=13 count=2` |
| 4 | Відсутній `config` відхиляється | **fixture-verified** | `IDENTITY-FAIL step=pci-config-read code=5 bdf=...` |
| 5 | Чужий BDF відхиляється | **fixture-verified** | `IDENTITY-FAIL step=bdf-mismatch code=14` |
| 6 | MMIO без прапорця відхиляється до будь-якого mapping | **fixture-verified** | `MMIO-FAIL step=opt-in-required code=15` |
| 7 | MMIO з bound драйвером відхиляється | **fixture-verified** | `MMIO-FAIL step=driver-bound code=16 driver=nvidia` |
| 8 | Read-only 32-бітне читання з `resource0` | **fixture-verified; physical NOT_RUN** | `MMIO-READ-OK`, `value=0x1c8210de` зі створеного тестом файлу |
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

1. shell syntax і C11 build із `-Werror`;
2. code firewall для write mapping, RM-запитів, BOOT0-констант і ABI pins;
3. synthetic sysfs positive fixture із явним `scope-unclassified`;
4. direct C API tests: відмова без opt-in і з bound driver;
5. fail-closed tests для malformed driver link, неоднозначної кількості карт,
   відсутнього PCI config та неправильного BDF;
6. MMIO tests для явного offset, вирівнювання та фактичного `resource0` size;
7. synthetic read-only fixture, який не є фізичним GPU свідком;
8. capability ledger, що залишає MMIO `deferred` навіть після software opt-in,
   доки немає owner consent і доведеного safe register;
9. best-effort runner sysfs inventory із `scope-unclassified`, не H170 PASS.

Підсумковий маркер:
`CAPABILITY-DRIVER-GATE-OK c11=yes layout=32/68/140 negatives=11 mmio=read-only-opt-in hardware-mmio=NOT-RUN`.

Базовий `scripts/test-pascal-probe.sh` не змінено; він лишається
непривілейованим/детермінованим з `EACCES` на `resource0`.

## 4. Незавершене й найменший наступний крок

- **Питання без відповіді:** який саме offset у BAR0 можна читати безпечно на
  цій платі за відсутності bound драйвера? Поточний код не містить жодного
  припущення про адресу регістру.
- **Найменший наступний крок:** спершу отримати окреме owner-рішення та
  встановити конкретний offset із документованою семантикою безпечного читання.
  Лише після цього можна планувати окремий фізичний test; до того
  `PHYSICAL_MMIO=NOT_AUTHORIZED / NOT_RUN` і BOOT0 лишається `UNPROVEN`.
- Окремо: мульти-GPU RM fixture для кореляції `PCI BDF ↔ RM gpu_id` не існує;
  цей стан не можна вивести з одного пристрою.

Межі: жодного transfer-коду, release/tag/publish, installer-змін, `Tested-by`,
new harness чи запуску PR #21. Коміт і пуш виконуються завжди.
