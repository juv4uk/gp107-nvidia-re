# 29 — Userspace capability-identity драйвер: перший зріз коду

Це **перший виконуваний код** у напрямку «драйвер», визначений у цій
сесії як безпечний source-only крок: userspace capability-identity бібліотека C з жорсткою fail-closed
інвентаризацією sysfs. Це **не** ABI, не kernel-модуль, не RM/GPFIFO-шлях і не
заміна `nvidia.ko`. SENS, CML, `wsm-os-lisp`, ADR, target contract і ABI-pin v8
не змінено.

## 0. Межа owner-дозволу

**Фізичний MMIO у цій координації НЕ АВТОРИЗОВАНИЙ і НЕ ВИКОНУВАВСЯ.**
Попередній текст про нібито дозвіл у цій сесії був неточним і виправлений.

- `--allow-mmio` — лише CLI-прапорець, а не owner authorization;
- `gp107_mmio_require_optin()` безумовно відмовляє до inventory або будь-якого доступу;
- `gp107_mmio_read32()` безумовно повертає `NOT_AUTHORIZED`, зокрема для прямих C callers;
- модуль більше не містить `open(resource0)`, `mmap` або фізичного читання BAR0;
- невідомий, пошкоджений чи обрізаний driver symlink завершує inventory помилкою; лише відсутній link означає known-unbound;
- жодного driver unbind, зміни boot-параметрів, RM/UVM ioctl, firmware, reboot чи GPU workload не виконується.

Будь-яке майбутнє фізичне MMIO вимагатиме **окремого явного owner-рішення**,
незалежного review і source-backed whitelist конкретного безпечного регістру.
Поточний CLI не має шляху, який може надати таке право.

## 1. Що додано

| Файл | Призначення |
|---|---|
| `lib/gp107_identity.h/.c` | FAIL-CLOSED sysfs inventory: vendor/device, BDF, публічний PCI-заголовок (revision/class/header/command/BAR0-flags), driver binding, розмір resource0 |
| `lib/gp107_capabilities.h/.c` | Машиночитаний capability-ledger з явними `granted`/`deferred`/`denied` (додано у docs/30) |
| `lib/gp107_mmio.h/.c` | Fail-closed API boundary: фізичний MMIO завжди відхиляється; жодного resource0 open/mmap |
| `lib/gp107ctl.c` | CLI `inventory`, `mmio-read`, `layout`; названі маркери помилок |
| `lib/Makefile` | C11 build з `-Wall -Wextra -Werror -pedantic` |
| `scripts/test-capability-driver.sh` | названі кроки, synthetic identity negatives, direct-API/CLI MMIO-denial checks, code firewall |
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
| 6 | MMIO без прапорця відхиляється через відсутність owner authorization | **runtime-proven (fixture)** | `MMIO-FAIL step=owner-authorization-required code=19` |
| 7 | MMIO з `--allow-mmio` усе одно відхиляється | **runtime-proven (fixture)** | `owner-authorization-required`; CLI-прапорець не надає дозволу |
| 8 | Прямий C API-виклик MMIO не відкриває і не мапить resource | **runtime-proven (synthetic direct caller)** | `NOT_AUTHORIZED`; шлях не містить `open/mmap` |
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
5. стани capability-ledger залишають фізичний MMIO у `denied` і мутація
   I/O-прапорця BAR0;
6. CLI та прямий C API відмовляють у фізичному MMIO; mapping не виконується;
7. best-effort реальний sysfs inventory (пропуск явно позначається, якщо
   пристрою немає).

Підсумковий маркер:
`CAPABILITY-DRIVER-GATE-OK c11=yes layout=32/68/140 negatives=10 mmio=physical-not-authorized hardware-mmio=NOT-RUN`.

Базовий `scripts/test-pascal-probe.sh` не змінено; він лишається
непривілейованим/детермінованим з `EACCES` на `resource0`.

## 4. Незавершене й найменший наступний крок

- Фізичний MMIO лишається **NOT AUTHORIZED / NOT RUN**. Поточна реалізація
  навмисно не має способу відкрити або відобразити BAR0, навіть із
  `--allow-mmio`.
- `BOOT0), register semantics, MMIO-safe offsets та RM/channel correlation
  лишаються `UNPROVEN). Не виводити їх із revision byte, capability ledger
  або синтетичного fixture.
- Наступна безпечна робота — source-only: уточнити PCI/Nouveau/NVK capability
  evidence та package provenance. Фізичний тест розглядати лише після окремого
  owner-рішення й незалежного підтвердження безпечного регістру.
- Мульти-GPU RM fixture для кореляції `PCI BDF ↔ RM gpu_id` не існує.

Межі: жодного transfer-коду, release/tag/publish, installer-змін, `Tested-by`,
RM-запитів, фізичного MMIO або запуску PR #21.
