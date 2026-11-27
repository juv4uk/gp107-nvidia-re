# 29 — Userspace capability-identity драйвер: перший зріз коду

Це перший userspace capability-identity зріз у C: бібліотека з fail-closed
інвентаризацією sysfs. Це **не** ABI, не kernel-модуль, не RM/GPFIFO-шлях і не
заміна `nvidia.ko`. Наявність opt-in MMIO API не є дозволом на фізичний доступ. SENS, CML, `wsm-os-lisp`, ADR, target contract і ABI-pin v8
не змінено.

## 0. Межа owner-дозволу

У цій координації **не надано дозволу на фізичний MMIO**, unbind драйвера,
перехід на `wsm_open_driver=1`, зміну boot parameters або інший GPU boot.
`--allow-mmio` — лише програмний opt-in gate, а не owner approval.

- MMIO-сеам існує лише як окремий експериментальний модуль.
- API самостійно вимагає opt-in, успішну PCI identity inventory, підтверджений
  unbound driver state та відомий BAR0 розмір щонайменше 4 KiB.
- Будь-яка невідома/помилкова помилка читання driver link блокує операцію.
- Фізичні `resource0` mapping/read, driver unbind і Nouveau boot тут не
  виконувалися й не авторизовані.
- Синтетичний fixture доводить лише поведінку коду на звичайному файлі.

Фізичне MMIO лишається **NOT AUTHORIZED / NOT RUN** до окремого явного рішення
власника. Наявність у коді функції `mmio-read` не змінює цю межу.

## 1. Що додано

| Файл | Призначення |
|---|---|
| `lib/gp107_identity.h/.c` | FAIL-CLOSED sysfs inventory: vendor/device, BDF, BAR0 з config, driver binding, розмір resource0 |
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
| 1 | Розкладки `gp107_pci_identity=20`, `gp107_driver_binding=68`, `gp107_inventory=128` байт | **statically proven** | `_Static_assert` у `lib/gp107_identity.h`; вивід `LAYOUT-OK identity=20 binding=68 inventory=128` |
| 2 | На RE host було виявлено одну картку `10de:1c82 @ 0000:01:00.0`, `bar0-base=0xee000000`, driver `nvidia` | **runtime-proven лише для того host inventory** | `gp107ctl inventory` через host `/sys`; це не H170 certification і не доказ про офлайн-плату власника |
| 3 | Друга картка того самого vendor/device відхиляється | **runtime-proven (fixture)** | `IDENTITY-FAIL step=card-count code=13 count=2` |
| 4 | Відсутній `config` відхиляється | **runtime-proven (fixture)** | `IDENTITY-FAIL step=pci-config-read code=5 bdf=...` |
| 5 | Чужий BDF відхиляється | **runtime-proven (fixture)** | `IDENTITY-FAIL step=bdf-mismatch code=14` |
| 6 | MMIO без прапорця відхиляється до будь-якого mapping | **runtime-proven (fixture)** | `MMIO-FAIL step=opt-in-required code=15` |
| 7 | MMIO з bound драйвером відхиляється | **runtime-proven (fixture)** | `MMIO-FAIL step=driver-bound code=16 driver=nvidia` |
| 8 | Read-only 32-бітне читання з `resource0` | **software runtime на synthetic fixture; physical MMIO NOT AUTHORIZED / NOT RUN** | `MMIO-READ-OK`, `value=0x1c8210de` зі створеного тестом звичайного файлу |
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
5. MMIO direct-C API: opt-in і bound-driver gates не можна обійти повз CLI;
6. невідомий/некоректний driver link відхиляється, а не трактується як unbound;
7. short BAR0 та offset поза вікном дають fail-closed;
8. read-only позитив виконується лише на синтетичному `resource0` файлі;
9. best-effort host sysfs inventory (пропуск явно позначається, якщо
   пристрою немає); цей результат не приписується H170.

Підсумковий маркер:
`CAPABILITY-DRIVER-GATE-OK c11=yes layout=20/68/128 fail-closed=passed synthetic-mmio=only hardware-mmio=NOT-AUTHORIZED/NOT-RUN`.

Базовий `scripts/test-pascal-probe.sh` не змінено; він лишається
непривілейованим/детермінованим з `EACCES` на `resource0`.

## 4. Незавершене й найменший наступний крок

- **Невідповідне питання:** чи існує BAR0 offset, який можна читати безпечно?
  Ні адреса, ні семантика регістру тут не встановлювалися.
- **Наступний крок без апаратного доступу:** продовжити source-only перевірку
  документації Nouveau/NVKM/RM та PCI BAR semantics. Фізичний aperture test
  не є автоматичним наступним кроком і потребує окремого явного owner approval.
  Без такого рішення BOOT0 і будь-яке значення регістру лишаються `UNPROVEN`.
- Окремо: мульти-GPU RM fixture для кореляції `PCI BDF ↔ RM gpu_id` не існує;
  цей стан не можна вивести з одного пристрою.

Межі: жодного transfer-коду, release/tag/publish, installer-змін, `Tested-by`,
new harness чи запуску PR #21. Коміт і пуш виконуються завжди.
