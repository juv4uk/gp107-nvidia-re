# 31 — Історичний x86-64 assembly load experiment

У попередньому експерименті був x86-64 SysV load primitive для вже
відображеної адреси. Саме існування movl/lfence не доводить безпечність
регістру й не створює дозволу на фізичний доступ.

У цій гілці assembly loader вилучено з build target і більше не є частиною
публічного MMIO API. Звичайний gp107ctl збирається лише з C11 sources;
ніякий gp107ctl-asm не створюється.

| Факт | Статус |
|---|---|
| Історичний source містив movl (%rdi),%eax; lfence; ret | **historical source fact** |
| Попередня C/ASM equivalence на synthetic file | **historical synthetic fixture only** |
| Активний assembly MMIO path у поточній збірці | **retired / not built** |
| Physical MMIO | **NOT AUTHORIZED / NOT RUN** |
| BOOT0, register semantics, RM/runlist/notifier/fence | **UNPROVEN** |

Під профіль H170 / GTX 1050 Ti лишаються read-only sysfs inventory та
source-level RE. Тут немає BAR0 mapping, device register read, DMA чи
GPU dispatch. Повернення будь-якого aperture reader вимагатиме окремого
owner-рішення, source-backed whitelist і незалежного review.
