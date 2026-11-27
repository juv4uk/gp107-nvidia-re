# 29 — Userspace capability identity для GP107

Цей C11-зріз читає PCI identity та driver binding через sysfs. Він не є
kernel driver, NVIDIA RM client, GPU command path чи системним ABI. Паралельна
Free Pascal реалізація описана в docs/32.

## Фізичний доступ

**Фізичне MMIO НЕ АВТОРИЗОВАНО / НЕ ВИКОНУВАЛОСЯ.**

- `--allow-mmio` є лише програмним CLI-прапорцем, а не дозволом власника.
- `gp107_mmio_read32()` завжди повертає `GP107_ERR_NOT_AUTHORIZED` (code 21)
  для коректного виклику — незалежно від прапорця, offset чи caller.
- `lib/gp107_mmio.c` не відкриває `resource0`, не викликає `mmap` і не
  читає регістри.
- Capability ledger завжди позначає software gate як `denied`,
  `owner-approval=not-inferred`, `physical-mmio=not-authorized`.
- Немає BAR aperture mapping, driver unbind, firmware, reboot, RM/UVM ioctl,
  GPU dispatch чи інших апаратних дій.

Будь-яке майбутнє фізичне дослідження вимагатиме окремого явного owner-рішення,
source-backed whitelist конкретного безпечного регістру та незалежного review.
Цей код такого дозволу не надає.

## Що залишається в цьому зрізі

| Компонент | Межа |
|---|---|
| `lib/gp107_identity.h/.c` | PCI vendor/device/BDF/config identity, driver binding, sysfs resource metadata |
| `lib/gp107_capabilities.h/.c` | Ledger, що відділяє спостереження від апаратних прав |
| `lib/gp107_mmio.h/.c` | Стабільний fail-closed API; фізичне читання завжди відхиляється |
| `lib/gp107ctl.c` | CLI inventory, capabilities, layout і відмовний mmio-read |
| `scripts/test-capability-driver.sh` | C11 build, synthetic sysfs, direct API та CLI denial |

Compile-time layout: `identity=32`, `binding=68`, `inventory=140` байт.

## Докази та межі

| Факт | Статус |
|---|---|
| Layout `32/68/140` | **statically proven** |
| GP107 `10de:1c82 @ 0000:01:00.0` з попереднього host inventory | **historical sysfs observation**; не є свіжим H170 тестом |
| Identity, duplicate card, invalid driver-link | **synthetic sysfs fixture** |
| CLI та direct C API відмова від фізичного MMIO | **synthetic/API negative tests** |
| BOOT0, BAR0 register semantics, RM object/runlist/notifier/fence | **UNPROVEN** |
| PCI BDF ↔ RM gpu_id | **UNPROVEN** |

Гейт перевіряє C11 `-Werror`, layout assertions, synthetic sysfs та відмову
обох рівнів API. Він не виконує позитивного читання з `resource0`.

Очікуваний підсумковий маркер:

`CAPABILITY-DRIVER-GATE-OK c11=yes fpc=3.2.2 layout=32/68/140 fail-closed=passed synthetic-sysfs=only pascal=parity physical-mmio=NOT-AUTHORIZED/NOT-RUN`

