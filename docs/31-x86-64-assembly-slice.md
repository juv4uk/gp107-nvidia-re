# 31 — Ізольований x86-64 assembly leaf (GP107)

Цей документ описує лише крихітний інструкційний reference leaf. Він **не**
є MMIO API і не отримує BAR/resource0 pointer від production path.

## 1. Що саме є в бінарнику

`lib/gp107_mmio_asm.S` містить x86-64 SysV function:

```text
rdi = звичайний caller-provided memory pointer
movl (%rdi), %eax
lfence
ret
```

Цей leaf збережено для статичного вивчення інструкції та викликового
конвенту. Після переходу public C API на `read-safe-offset-unproven`
він **не викликається** ні C MMIO API, ні Pascal `Read32`; production code
не відкриває `resource0`, не робить mapping і не читає апертуру.

## 2. Що доведено і чого не доведено

| Факт | Статус | Межа |
|---|---|---|
| `movl (%rdi),%eax` та `lfence` присутні у reference object | **statically proven** | `objdump -d`; це не hardware access |
| C та ASM capability-ledger однакові | **synthetic-fixture** | лише inventory/ledger, не MMIO value |
| Безпечний GP107 BAR0 register offset | **UNPROVEN** | у коді немає whitelist або register read |
| BOOT0 / `0x137000A1` | **UNPROVEN / string-only** | фізично не читалося |
| Фізичний MMIO | **NOT AUTHORIZED / NOT RUN** | немає unbind, mapping або aperture access |

Наявність asm leaf, `--allow-mmio` або збірки `gp107ctl-asm` не є
owner approval і не надає жодного права на читання регістрів.

## 3. Межі

- Немає write-MMIO, BAR mapping, RM, FIFO, firmware, reboot або GPU submit.
- C11 є контрольним еталоном; Free Pascal — primary research slice.
- SENS, CML, ABI pins та WSM system configuration не змінювалися.
