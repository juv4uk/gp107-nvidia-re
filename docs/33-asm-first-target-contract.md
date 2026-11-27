# 33 — asm-first target contract для збірки під залізо власника

Це **не реліз, не tag і не publish**. Це контракт, який визначає, що саме є
носієм істини для збірки під одну конкретну плату. Власник обрав асемблер не
для портативності, а для детермінованої послідовності інструкцій: ми платимо
відмовою від узагальнення й отримуємо фіксований інструкційний слід.

SENS, CML, `wsm-os-lisp`, ADR, target contract і ABI-pin v8/v9 не змінено.

## 1. Ієрархія авторитетності

| Рівень | Артефакт | Роль | Статус |
|---:|---|---|---|
| 1 | `lib/gp107_mmio_asm.S`, функція `gp107_mmio_load32_asm` | **Авторитетний інструкційний контракт**: рівно одне 32-бітне читання + `lfence` | **statically proven** |
| 2 | `build/capability-driver/gp107ctl-asm` | Контейнер, що доводить: ті самі байти злинковані у виконуваний ELF | **statically proven** |
| 3 | `pascal/gp107ctl-pascal`, `pascal/gp107_*.pas` | Fail-closed CLI-обгортка: sysfs inventory, opt-in/driver/BAR/offset ворота, synthetic parity | **runtime-proven (fixture + host sysfs)** |
| 4 | `lib/gp107_*.c` | Oracle виводу: байтова еквівалентність stdout/stderr; не джерело інструкційної істини | **runtime-proven (fixture)** |
| 5 | Цей документ | Інтерпретація, межі й статуси; не є авторитетом сам по собі | **interpretation** |

Чому рівень 1, а не Pascal inline asm: FPC 3.2.2 додає до своєї assembler-функції
пролог/епілог (`mov %esp,%ebp`, `lea -0x10(%rsp),%rsp`, …, `pop %rbp`, `ret`).
Отже Pascal-функція **не є** мінімальною послідовністю; вона лише викликає
еквівалентне читання в межах обгортки. Мінімальний слід зберігається в `.S`.

## 2. Opcode witness

| Поле | Значення |
|---|---|
| Джерело | `lib/gp107_mmio_asm.S`, `gp107_mmio_load32_asm`, рядки 15–19 |
| Символ у бінарнику | `gp107_mmio_load32_asm`, спостережено на `0x2fa3` у `gp107ctl-asm` (адреса часу лінкування, **не pin**) |
| Байти | `8b 07 0f ae e8 c3` |
| Hex | `8b070faee8c3` |
| SHA-256 | `c9f23d75c45286adc4660cab6971e4d9ecf1f864ea261a5b6d3a1c5baf7a61fc` |
| Дизасемблювання | `mov (%rdi),%eax` ; `lfence` ; `ret` |
| Caller / xref | `lib/gp107_mmio.c:180`, єдиний виклик усередині mapper-а під `GP107_USE_ASM` |
| Callee | відсутній |
| Інструмент | GNU objdump (GNU Binutils for Debian) `2.47.50.20261021`; `readelf -h`: ELF64, little-endian, UNIX System V, Advanced Micro Devices X86-64 |
| Маркер гейту | `ASM-OPCODE-OK function=gp107_mmio_load32_asm bytes=6 hex=8b070faee8c3 sha256=c9f2…a61fc mnemonic=mov,lfence,ret hardware-mmio=NOT-RUN` |
| Статус | **statically proven**: точні байти, хеш, відсутність `call`/запису/стеку. Це не доказ виконання на залізі |

Гейт звіряє не «наявність `lfence`», а рівно шість байт і їх SHA; будь-який
зайвий `call`, `push`/`pop`, робота з `%rsp` або інша інструкція ламає збірку.

## 3. Target pin, який реліз матиме право заявляти

| Факт | Значення | Статус |
|---|---|---|
| Картка | `10de:1c82 @ 0000:01:00.0`, `revision=0xa1` | **runtime-proven** (sysfs, обидва CLI) |
| BAR0 | base `0xee000000`, size `0x01000000`, memory/32-bit/non-prefetch | **runtime-proven** (sysfs), не apertura-read |
| Архітектура | x86-64 SysV, ELF64 little-endian | **statically proven** |
| FPC | `3.2.2` | **statically proven**, лише harness |
| Права | read-only, opt-in, `driver-bound`/size/offset fail-closed | **statically proven** у коді + **runtime-proven** на fixture |
| Фізичний MMIO | не виконувався | **NOT RUN** |

Це прив’язка до профілю власницького хоста, не certification іншого заліза
і не зміна authoritative ABI.

## 4. Межі доказів

- BOOT0, `0x137000A1`, RM class/runlist/notifier/fence, `BDF ↔ RM gpu_id` —
  **UNPROVEN / string-only**; асемблер не додає жодного нового твердження.
- Причина розбіжності NVK↔NVIDIA — **PARTIAL**.
- Фізичний MMIO на реальній GP107 — **NOT RUN**: `nvidia` bound, cmdline без
  `wsm_open_driver=1`, жодного unbind/reboot.
- Вимірювання продуктивності одним запуском не проводяться й не заявляються.

## 5. Що не робиться без окремої owner-дії

tag, GitHub Release/publish, installer/Guix зміни, ABI-pin, unbind або
alternate boot, RM-запити, write-MMIO, reboot, transfer-код і запуск PR #21.

## 6. Питання без відповіді й найменший крок

Невідоме: який BAR0-offset безпечно читати після unbind. Найменший крок —
після окремого owner-рішення на кваліфікованому hostі виконати read-only
операцію, зберегти stdout/stderr artifact із SHA-256 і позначити результат як
`runtime-proven` або fail-closed. Поки цього немає, BOOT0 лишається `UNPROVEN`.
