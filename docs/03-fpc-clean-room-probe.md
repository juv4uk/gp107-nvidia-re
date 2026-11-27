# 03 — FPC як субстрат для clean-room probe

Цей документ фіксує, що саме доведено для Pascal-гілки репозиторію, а що — ні.
Практика ведення таблиці фактів і механічного gate позичена з
`juv4uk/wsm-lazarus` (`docs/toolchain.md`, `docs/mechanism-budget.md`,
`scripts/test.sh`, `scripts/check-no-lcl.sh`, `src/wsm.elfwriteguard.pas`).

## Межі повноважень

- SENS володіє семантикою мови; CML — admission/IR.
- `wsm-os-lisp` володіє target ABI, boot runtime і платформною політикою; його
  ADR-004 (Pure Lisp + x86-64 assembly, RUST = 0) не змінюється цим репозиторієм.
- `wsm-lazarus` — нативна реалізація SENS на FPC; тут ми беремо лише інженерну
  дисципліну, а не мовні рішення.
- Цей репо — **неавторитетний протокольний довідник**. FPC тут означає
  інструмент research-пробника, а не нову основу Lisp-машини.

## Таблиця фактів за станом доказу

| Факт | Стан | Свідок |
|---|---|---|
| `SizeOf(Tnv_pci_info) = 12`, `SizeOf(Tnv_card_info) = 72` | **статично, компілятором** | `TAssertPciInfo12` / `TAssertCardInfo72` у `pascal/nv_abi.pas`: хибний розклад дає `array[0..-1]` і падіння збірки. Гейт додатково робить negative witness (підміна `minor_number` на `QWord`) і вимагає саме `Upper bound of range is less than lower bound` |
| `NV_IOC_CARD_INFO=$c90046c8`, `NV_IOC_SYS_PARAMS=$c00846d6`, `NV_IOC_REGISTER_FD=$c00446c9` | **статично + self-check** | ті самі значення обчислюються `NvIOC_RDWR()`, звіряються перед будь-яким ioctl |
| `BaseUnix` імпортує `FPC_SYSC_IOCTL` / `FPC_SYSC_MMAP` | **статично** | `ppudump /usr/lib/x86_64-linux-gnu/fpc/3.2.2/units/x86_64-linux/rtl/baseunix.ppu` |
| Бінарник STATIC, без `DT_NEEDED` | **статично, ELF** | `file` → `statically linked`; `readelf -d` → немає `NEEDED`; перевіряється гейтом |
| `block_size_bytes = 0x08000000` (134217728) | **runtime** | sysfs, прочитаний через `FpOpen`/`FpRead`; потім прийнято `NV_ESC_SYS_PARAMS` |
| `10de:1c82 @ 0000:01:00.0`, `minor=0`, BAR0 `0xee000000+0x1000000`, FB `0xd0000000+0x10000000` | **runtime** | `NV_ESC_CARD_INFO`, той самий результат, що й у C-пробі |
| `NV_ESC_REGISTER_FD` на gpu fd з control fd як 4-байтовим аргументом | **runtime** | probe відкриває `/dev/nvidia0`, виконує ioctl; помилка друкується, але не приховується |
| `FpMMap` працює для BAR0 | **не перевірено** | наступний мікро-крок (G1), тут не використовується |
| Bare-metal GPU драйвер у Lisp-машині | **не перевірено / не існує** | у `wsm-os-lisp` GPU все ще належить hosted `wsm-cuda` |

## Чому ELF-перевірка важливіша за назву юніта

Поширене спрощення «BaseUnix = завжди syscall, отже без libc» хибне.
У `wsm-lazarus/src/wsm.elfpublish.pas:17` прямо зафіксовано, що FPC 3.2.2
**не експортує `fpFChmod`** — там POSIX `fchmod` іде через libc. Тому ми не
робимо висновок з імені модуля, а перевіряємо **готовий артефакт**: статичний
ELF без `DT_NEEDED`. Для конкретних `FpOpen`, `FpIOCtl`, `FpRead`, `FpClose`
у `baseunix.ppu` присутні імпорти `FPC_SYSC_*`, тобто вони справді йдуть
напряму через syscall ABI.

## Pin інструментарію

- База evidence: **FPC 3.2.2** (`fpc -iV`), Kali package
  `3.2.2+dfsg-51`. Гейт падає, якщо версія інша; `FPC_EXPECTED` можна
  перевизначити лише явним рішенням з новим вимірюванням.
- З `docs/toolchain.md` `wsm-lazarus`: 3.2.4 має upstream source-tag
  `release_3_2_4`, але дистрибутивні пакети ще не синхронізовані; 3.3.1
  x86_64-embedded — окремий development snapshot для UEFI/embedded P0.
  Ці бази не змішуються.
- `-XS` у `pascal/Makefile` вимагає статичного лінку; гейт це перевіряє.

## Відтворення

```bash
bash scripts/test-pascal-probe.sh
```

Очікуваний фінальний рядок:

```text
PASCAL-PROBE-GATE-OK fpc=3.2.2 static=yes no-libc=yes gpu=10de:1c82
```

Гейт передає три стани окремо: збірка (compile-time ABI-доказ), runtime
(witness на реальному GPU), бінарник (відсутність динамічних залежностей).
Жоден із них не доводить роботу GPU в bare-metal Lisp-машині.

## Наступний мікро-крок

`02_bar_identity.pas`: read-only `FpMMap` на
`/sys/bus/pci/devices/0000:01:00.0/resource0`, звірення vendor/device з
NV_ESC_CARD_INFO, і fail-closed відмова при будь-якій спробі запису в BAR0.
Це дасть G0/G1 witness, який можна буде перенести в `wsm-os-lisp` як
обмежену `PciConfig`/`Mmio` capability — але лише після owner-рішення
про GPU-capability та звірки ABI v8→v9 у `wsm-target-contract`.
