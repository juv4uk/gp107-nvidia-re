# 30 — PCI config-header і capability ledger GP107

Документ описує sysfs PCI inventory та його машиночитану проєкцію. Він не
надає права на BAR0 і не є частиною системного ABI.

## PCI identity

C11 inventory читає через sysfs vendor/device/BDF, public PCI configuration
header, revision, class code, header type, command, BAR0 raw flags/address,
resource metadata та driver binding. Ці значення — inventory facts, а не
доказ NVIDIA-specific register semantics, BOOT0, RM object або runlist.

## Незмінна межа MMIO

**Physical MMIO: NOT AUTHORIZED / NOT RUN.**

| Умова | Software gate | Фізичний доступ |
|---|---|---|
| Kernel driver bound | `denied` (`driver-bound`) | `not-authorized` |
| Driver absent, без `--allow-mmio` | `denied` (`owner-authorization-required`) | `not-authorized` |
| Driver absent, з `--allow-mmio` | `denied` (`owner-authorization-required`) | `not-authorized` |

`--allow-mmio` — програмний аргумент, не owner approval. C
`gp107_mmio_read32()` і Pascal `Read32()` завжди відмовляють; вони не
відкривають `resource0`, не маплять BAR0 та не читають регістри. Стану
`granted` або `deferred` для фізичного MMIO в поточному ledger немає.

## Capability projection

Ledger показує:
- `pci-inventory=observed`;
- `mmio-read-software-gate=denied`;
- `owner-approval=not-inferred`;
- `physical-mmio=not-authorized`;
- `rm-identity=deferred`;
- `boot0=unproven`.

Ні sysfs inventory, ні CLI прапорець, ні synthetic fixture не підвищують
фізичні права.

## Докази

| Факт | Статус |
|---|---|
| Layout `32/68/140` | **statically proven** |
| Попередні PCI config values із RE host | **historical sysfs observation** |
| Driver-link negative handling | **synthetic negative test** |
| CLI і direct C/Pascal API denial | **synthetic/API negative tests** |
| BOOT0, безпечний MMIO offset, PCI BDF ↔ RM gpu_id | **UNPROVEN** |
| Runlist, notifier, fence, GPFIFO/dispatch | **UNPROVEN** |

Збіг revision byte `0xa1` із молодшим байтом рядка `0x137000A1` не доводить
BOOT0. Це лишається interpretation/string-only.

Перевірка: `make test-capability-driver`. Гейт перевіряє synthetic sysfs,
driver-link errors, CLI/direct API denial і byte-for-byte C/Pascal ledger parity.
Фізичний MMIO не запускається; SENS/CML/ABI pins не змінюються.
