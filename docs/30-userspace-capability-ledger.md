# 30 — PCI config-header і capability ledger GP107

Цей документ фіксує sysfs PCI inventory та його машиночитану проєкцію. Він не
надає права на BAR0 і не є частиною системного ABI.

## 1. PCI identity

C11 inventory зчитує через sysfs:
- vendor/device та BDF;
- 32-байтовий public PCI configuration header;
- revision, class code, header type, command;
- BAR0 raw flags/address та resource metadata;
- driver binding.

Значення є inventory facts, а не доказом семантики NVIDIA-specific регістрів,
BOOT0, RM object, runlist чи GPU command stream.

## 2. Незмінна межа MMIO

**Physical MMIO: NOT AUTHORIZED / NOT RUN.**

| Умова | Software gate | Фізичний доступ |
|---|---|---|
| Kernel driver bound | denied (driver-bound) | not-authorized |
| Driver absent, без --allow-mmio | denied (owner-authorization-required) | not-authorized |
| Driver absent, з --allow-mmio | denied (owner-authorization-required) | not-authorized |

--allow-mmio є програмним аргументом і не дорівнює owner approval.
gp107_mmio_read32() завжди відмовляє; API не відкриває resource0,
не викликає mapping і не читає фізичний BAR0. Немає жодного granted стану
для фізичного MMIO.

## 3. Capability projection

Ledger окремо показує:
- pci-inventory=observed;
- mmio-read-software-gate=denied;
- owner-approval=not-inferred;
- physical-mmio=not-authorized;
- rm-identity=deferred;
- boot0=unproven.

Ні sysfs inventory, ні CLI прапорець, ні synthetic fixture не підвищують
фізичні права.

## 4. Свідки та невідоме

| Факт | Статус |
|---|---|
| Layout 32/68/140 | **statically proven** |
| PCI config values із попереднього RE-host inventory | **historical sysfs observation** |
| Driver-link unknown handling | **synthetic negative** |
| CLI/API MMIO denial | **synthetic/API denial tests** |
| BOOT0, безпечний MMIO offset, PCI BDF ↔ RM gpu_id | **UNPROVEN** |
| Runlist, notifier, fence, GPFIFO/dispatch | **UNPROVEN** |

Збіг revision byte 0xa1 з молодшим байтом рядка 0x137000A1 не доводить
BOOT0. Це лишається interpretation/string-only.

## 5. Перевірка

Команда: make test-capability-driver

Гейт перевіряє synthetic sysfs inventory, driver-link errors, прямий C API
denial, CLI denial незалежно від --allow-mmio і ledger physical-mmio
not-authorized. Фізичний MMIO не запускається.

SENS/CML/ABI pins, firmware, driver binding і boot configuration не змінюються.
Публікація артефактів чи release цим документом не авторизується.
