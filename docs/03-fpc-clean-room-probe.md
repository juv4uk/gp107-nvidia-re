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
| Відсутність `PT_INTERP`, `.dynamic`, `PT_DYNAMIC`, libc-символів | **статично, ELF** | окремі кроки `binary proof 1/3`, `2/3`, `3/3`; маркер `BINARY-PROOF-OK elf-static=yes no-dynamic-deps=yes libc-dynamic=no` |
| Профіль хоста R580/GP107/`0000:01:00.0` | **runtime, preflight** | `HOST-PROFILE-OK ...`; несумісність дає `PASCAL-PROBE-UNSUPPORTED reason=...`, exit 3 |
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

Очікувані рядки:

```text
HOST-PROFILE-OK bdf=0000:01:00.0 driver=580.196.11 block=8000000 bar0=0x00000000ee000000
BINARY-PROOF-OK elf-static=yes no-dynamic-deps=yes libc-dynamic=no
PASCAL-PROBE-GATE-OK fpc=3.2.2 static=yes no-libc=yes gpu=10de:1c82 bar0=fail-closed rmarch=runtime-proven boot0=unproven
```

**Розділені бінарні твердження.** Раніше `static=yes no-libc=yes` було одним
рядком перевірки. Тепер окремо перевіряються: (1) STATIC ELF без `PT_INTERP`;
(2) відсутність `.dynamic`, `PT_DYNAMIC` і `DT_NEEDED`; (3) відсутність
`libc.so`, `GLIBC_*`, `__libc_start_main` у символах і тілі бінарника.
Статичний бінарник зі вбудованим libc провалив би саме третю перевірку,
тож `no-libc=yes` означає **відсутність libc-залежності**, а не відсутність
будь-якого бібліотечного коду FPC RTL.

**Environment gate.** Перед будь-яким runtime-викликом гейт перевіряє
FPC 3.2.2/x86_64/linux, наявність інструментів, унікальну картку
`10de:1c82`, BDF `0000:01:00.0`, драйвер `580.196.11`, `block_size_bytes`,
BAR0 з sysfs і `/dev/nvidiactl`. Несумісне середовище дає
`PASCAL-PROBE-UNSUPPORTED reason=...` і код виходу **3**. Це не зелений
результат: гейт лишається fail-closed, але не видає хибний `FAIL` там, де
змінилася конфігурація хоста. Негативний приклад:

```bash
FPC_EXPECTED=9.9.9 bash scripts/test-pascal-probe.sh
# PASCAL-PROBE-UNSUPPORTED reason=fpc-version=3.2.2 expected=9.9.9 ; exit 3
```

Гейт передає три стани окремо: збірка (compile-time ABI-доказ), runtime
(witness на реальному GPU), бінарник (відсутність динамічних залежностей).
Жоден із них не доводить роботу GPU в bare-metal Lisp-машині.

## Наступний мікро-крок (виконано)

`02_bar_identity.pas` зробив read-only `FpMMap` на
`/sys/bus/pci/devices/0000:01:00.0/resource0`, звірив vendor/device з
NV_ESC_CARD_INFO і fail-closed відмовляється при будь-якій спробі запису в BAR0.
Це дало G0/G1 witness. Пізніше додано `03_rm_arch_info.pas` — окремий RM-канал
arch/implementation, який **не** є BOOT0 і не надає права на MMIO.
Перенесення в `wsm-os-lisp` як обмеженої `PciConfig`/`Mmio` capability
лишається за owner-рішенням та звіркою ABI v8→v9 у `wsm-target-contract`.

## Lifecycle RM-обʼєктів (G3)

`03_rm_arch_info.pas` більше не покладається на закриття fd як на механізм
звільнення RM-обʼєктів. Після успішного або частково успішного створення
ланцюжка `NV01_ROOT_CLIENT` → `NV01_DEVICE_0` → `NV20_SUBDEVICE_0` виконавець
робить явний `NV_ESC_RM_FREE` (`NVOS00_PARAMETERS`, 16 байт) у зворотному
порядку: subdevice → device → root client. Якщо `ioctl` або `status` схибив,
друкується `RM-FREE-FAIL`, `RM-CLEANUP-FAIL`, і гейт падає; твердження
«fd close звільняє все» тут **не стверджується**.

Для перевірки часткових шляхів гейт інʼєктує змінну
`WSM_RM_FAIL_STEP=after_alloc_client|after_alloc_device|after_alloc_subdev`
окремо від звичайного прогону. Очікувані результати: 1, 2 або 3 успішних
звільнення відповідно, `RM-CLEANUP-COMPLETE`, ненульовий код виходу та
маркер `RM-ARCH-FAIL step=INJECT-...`. У звичайному прогоні змінна
видаляється через `env -u`.

| Факт | Стан | Свідок |
|---|---|---|
| `SizeOf(Tnvos00)=16` | **статично, компілятором** | `TAssertNvos00`; хибний розклад ламає збірку |
| `NV_ESC_RM_FREE` з `h_root/h_parent/h_old/status` звільняє створені обʼєкти з `status=0` | **runtime-proven** на R580/GP107 | маркери `RM-FREE-OK object=... status=0`, `RM-CLEANUP-COMPLETE objects=3` |
| Зворотний порядок звільнення | **runtime-proven + firewalls** | вивід трьох `RM-FREE-OK` у порядку subdev → device → client; gate перевіряє порядок у коді |
| Cleanup після часткової відмови | **runtime-proven через інʼєкцію** | три окремі прогони з 1/2/3 звільненнями |
| Причина будь-якого `NV_ERR_*` або внутрішня поведінка RM при звільненні | **UNPROVEN** | тут перевірено лише спостережувані `ioctl`/`status`, не вихідний код RM |
