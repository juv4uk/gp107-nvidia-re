# 29 — Userspace capability identity для GP107

Це C11-дослідницька бібліотека для PCI/sysfs inventory. Вона не є kernel
driver, NVIDIA RM client, GPU command path чи ABI. SENS, CML, wsm-os-lisp,
ADR, target contract і ABI pins не змінювалися.

## 0. Фізичний доступ: не авторизований

**Фізичне MMIO НЕ АВТОРИЗОВАНО / НЕ ВИКОНУВАЛОСЯ.**

- Прапорець --allow-mmio — CLI аргумент, не дозвіл власника.
- Публічний gp107_mmio_read32() безумовно повертає
  GP107_ERR_NOT_AUTHORIZED (code 21) для кожного коректного виклику.
- lib/gp107_mmio.c не відкриває resource0, не мапить BAR0 і не читає
  регістри.
- Capability ledger завжди залишає physical MMIO у not-authorized;
  granted не виводиться ні з прапорця, ні з synthetic fixture.
- Driver binding читається через закріплений fd PCI-device directory та
  readlinkat(). Тільки ENOENT саме для driver entry означає known-unbound;
  інші помилки, зникнення parent directory й обрізаний symlink дають
  fail-closed unknown.
- Немає driver unbind, зміни boot options, firmware, reboot, RM/UVM ioctl,
  GPU dispatch чи фізичного aperture test.

Можливе майбутнє фізичне дослідження вимагатиме окремого явного owner-рішення,
незалежного review та source-backed whitelist конкретного безпечного регістру.
Цей PR такого дозволу не надає.

## 1. Що містить цей зріз

| Файл | Призначення |
|---|---|
| lib/gp107_identity.h/.c | PCI vendor/device/BDF/config identity, driver binding, resource metadata з sysfs |
| lib/gp107_capabilities.h/.c | Машиночитаний ledger із розділенням inventory, software gate та owner approval |
| lib/gp107_mmio.h/.c | Стабільний fail-closed API, який відмовляє у фізичному MMIO |
| lib/gp107ctl.c | CLI inventory, capabilities, layout і відмовний mmio-read |
| scripts/test-capability-driver.sh | C11 build, synthetic sysfs negatives, direct-API/CLI denial та source firewall |

Розмір compile-time layout: identity=32, binding=68, inventory=140 байт.

## 2. Рівні доказів

| Факт | Статус | Межа |
|---|---|---|
| Layout 32/68/140 | **statically proven** | _Static_assert та C11 build |
| 10de:1c82 @ 0000:01:00.0, bar0-base=0xee000000, driver nvidia | **історичне sysfs-observation на RE host** | Не є свіжою перевіркою H170 owner-host і не дозволяє BAR access |
| Duplicate device, missing config, чужий BDF | **synthetic-fixture** | Inventory має завершуватися fail-closed |
| Invalid/truncated driver-link | **synthetic negative** | Unknown не прирівнюється до unbound |
| MMIO CLI без прапорця та з --allow-mmio | **synthetic/API denial test** | Обидва варіанти NOT_AUTHORIZED |
| Прямий C API виклик MMIO | **synthetic/API denial test** | Не відкриває шлях пристрою; повертає code 21 |
| Capability ledger | **synthetic-fixture** | Physical MMIO завжди not-authorized |
| BOOT0, BAR0 register semantics, RM class/runlist/notifier/fence | **UNPROVEN** | Фізичного читання немає |
| PCI BDF ↔ RM gpu_id | **UNPROVEN** | Потрібні окремі докази |

Історичні host facts не переносяться на H170 автоматично: підключений owner
executor зараз недоступний, тож локальне підтвердження не отримано.

## 3. Перевірка

Команди локального CI:
- make -C lib clean all
- bash scripts/test-capability-driver.sh
- make test-valid-cards-static

Гейт перевіряє C11 -Werror, layout assertions, synthetic sysfs identity,
driver-link fail-closed, відмову CLI з/без --allow-mmio, прямий C API denial,
відсутність file-open/mapping calls у MMIO implementation та узгодженість
capability ledger.

Очікуваний фінальний маркер:

CAPABILITY-DRIVER-GATE-OK c11=yes layout=32/68/140 fail-closed=passed synthetic-sysfs=only physical-mmio=NOT-AUTHORIZED/NOT-RUN

Цей маркер не означає фізичний H170 test або runtime GPU validation.

## 4. Наступна безпечна робота

Продовжити source-only дослідження:
- exact package pairing для nvidia.ko та nvidia-uvm.ko;
- bounded caller tracing для add_gpu / channel_pool_add;
- звірка GP107 Nouveau/NVK support і firmware provenance;
- кореляція PCI BDF ↔ RM gpu_id лише на підставі окремого доказу.

Не робити aperture test, unbind, reboot, firmware, RM/UVM ioctl, GPU workload
чи зміну ABI pins.
