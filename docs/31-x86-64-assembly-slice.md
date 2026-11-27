# 31 — Історичний x86-64 assembly load experiment

У попередньому експерименті був x86-64 SysV load primitive для вже
відображеної адреси. Наявність `movl` / `lfence` не доводить безпечність
регістру та не створює дозволу на фізичний доступ.

У поточному зрізі assembly loader **вилучено з активного build target**:
`lib/gp107_mmio_asm.S` не лінкується, `gp107ctl-asm` не створюється, а
Pascal `gp107_mmio.pas` не має inline-assembly reader. C11 та Pascal
залишаються реалізаціями inventory/report і fail-closed API, а не апертурного
читання.

| Факт | Статус |
|---|---|
| Попередній source містив `movl (%rdi),%eax; lfence; ret` | **historical source fact** |
| Попередня C/ASM equivalence на synthetic file | **historical synthetic fixture only** |
| Активний assembly MMIO path у build/API | **retired / not built** |
| Фізичний MMIO | **NOT AUTHORIZED / NOT RUN** |
| BOOT0, register semantics, RM/runlist/notifier/fence | **UNPROVEN** |

Для H170 / GTX 1050 Ti залишаються read-only sysfs inventory та статичний
source RE. Немає BAR0 mapping, device register read, DMA або GPU dispatch.
Повернення aperture reader потребуватиме окремого owner-рішення,
source-backed register whitelist та незалежного review.
