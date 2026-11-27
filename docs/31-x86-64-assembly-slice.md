# 31 — Ізольований x86-64 assembly leaf

Асемблерний leaf залишено як окремий дослідницький артефакт. Наявність
інструкції не перетворює UNPROVEN на факт і не дозволяє фізичне читання.

## 1. Що саме зібрано

`lib/gp107_mmio_asm.S` містить x86-64 SysV leaf:

```text
rdi = const volatile void *address
movl (%rdi), %eax
lfence
ret
```

- leaf присутній у gp107ctl-asm лише для статичного огляду;
- production C path його не викликає і не має caller у цьому зрізі;
- він не відкриває, не мапить і не читає resource0;
- C API повертає read-safe-offset-unproven до будь-якого BAR access;
- немає vendor constants, BOOT0 assumptions або write sequences.

## 2. Статус фактів

| # | Факт | Статус | Свідок / межа |
|---:|---|---|---|
| 1 | `movl` + `lfence` + `ret` присутні в assembly object | **statically proven** | objdump і ASM-STATIC-OK; сам leaf не викликається |
| 2 | Production C MMIO API не викликає assembly leaf | **statically proven** | source guard: немає caller у C |
| 3 | C/asm runtime equivalence на synthetic BAR0 | **NOT RUN** | жоден шлях не читає resource0 |
| 4 | Фізичний BAR0 read на реальній GP107 | **NOT RUN** | немає read-safe offset; MMIO API fail-closed |
| 5 | BOOT0, RM class/runlist/notifier/fence, performance gap | **UNPROVEN** | assembly leaf не додає нових фактів |

## 3. Що не змінено

- немає release/tag/publish;
- немає фізичного MMIO, RM/UVM ioctl, firmware, GPFIFO, reboot або driver change;
- SENS, CML, wsm-os-lisp, ADR, target contract та ABI pins не змінені.

Підсумковий маркер:
`CAPABILITY-DRIVER-GATE-OK c11=yes layout=32/68/140 negatives=10 mmio=physical-read-deferred asm=static-only hardware-mmio=NOT-RUN`.

## 4. Наступна умова

Потрібен bounded RE/source evidence для safe BAR0 register і окрема owner
дія. До того жодного фізичного `mmio-read` не запускати навіть після unbind.
