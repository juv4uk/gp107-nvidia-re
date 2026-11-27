# 31 — Асемблерний зріз під конкретну плату (GP107 / x86-64)

Власник зазначив, що реліз збиратиметься тільки під його залізо, і що
асемблер тут природний інструмент. Це **не змінює межі доказів**: мова не
перетворює `UNPROVEN` на факт. Асемблер застосовано лише до вже доведеного
read-only примітиву, а не до невідомих регістрів чи RM-протоколу.

## 1. Що саме на асемблері

`lib/gp107_mmio_asm.S` — власний x86-64 SysV примітив:

```text
rdi = вже змапована read-only адреса
movl (%rdi), %eax
lfence
ret
```

- один 32-бітний load і `lfence` після нього;
- жодних констант регістрів, BOOT0-адрес, vendor-послідовностей чи write;
- ASM load викликається лише з приватного C mapper після проходження opt-in,
  identity, driver-binding, BAR-space, BAR-size, offset і відкритого resource0 size gates;
- збірка `gp107ctl-asm` використовує `-DGP107_USE_ASM=1`, звичайний `gp107ctl`
  лишається C-версією для порівняння.

`make -C lib profile` друкує:
`GP107-PROFILE-OK vendor=0x10de device=0x1c82 bdf=0000:01:00.0 arch=x86_64 asm=read-only`.
Це **профіль збірки під плату власника**, а не release, tag, publish чи installer.

## 2. Статус фактів

| # | Факт | Статус | Свідок / межа |
|---:|---|---|---|
| 1 | Примітив `movl (%rdi),%eax` + `lfence` + `ret` присутній у бінарнику | **statically proven** | `objdump -d gp107ctl-asm` показує `gp107_mmio_load32_asm` і `lfence`; маркер `ASM-STATIC-OK` |
| 2 | Aсемблерний і C-шляхи дають ідентичний результат на синтетичному `resource0` | **runtime-proven (fixture)** | `ASM-EQUIV-OK fixture-read-and-ledger identical-to-C` |
| 3 | Capability-ledger однаковий для обох збірок | **runtime-proven (fixture)** | `cmp` виводу `capabilities --allow-mmio`, без розбіжностей |
| 4 | Профіль збірки прив’язаний до `10de:1c82 @ 0000:01:00.0`, x86-64 | **design choice / statically proven** | константи в `lib/gp107_identity.h`, вивід `GP107-PROFILE-OK` |
| 5 | Фізичний read апертури на реальній GP107 | **NOT RUN** | `nvidia` bound; жодного unbind/reboot/MMIO-тесту |
| 6 | BOOT0, `0x137000A1`, RM class/runlist/notifier/fence, причина розриву NVK↔NVIDIA | **UNPROVEN / string-only** | асемблер не додає жодного нового твердження |
| 7 | Асемблерний шлях дає право запису чи dispatch | **UNPROVEN, не стверджується** | у коді немає write, RM, FIFO чи doorbell |

## 3. Виправлення межі resource0

У першій версії сеам перевіряв тільки межу сторінки (`0x1000`), але не розмір
`resource0`. Це було технічним недоліком: менший файл міг би бути змапований
як повне вікно. Виправлено:

- `gp107_mmio_read32` тепер приймає `struct gp107_inventory` і вимагає
  `bar0_size >= 4096` (`MMIO-FAIL step=bar0-size-too-small code=19`) та
  `offset + 4 <= bar0_size` (`step=offset-out-of-range`);
- додано два негативні witness: урізаний `resource0` і offset `0x1000`;
- синтетичний `resource0` збільшено до 4096 байт.

Це **runtime-proven на fixture**; на реальному GP107 розмір BAR0 зчитано з
sysfs як `0x01000000`, але самий aperture-read не виконувався.

## 4. Що не змінилося

- жодного release/tag/publish чи публікації артефакта;
- жодного MMIO-запису, `nva`, RM-запиту, firmware, GPFIFO чи reboot;
- SENS, CML, `wsm-os-lisp`, ADR, target contract і ABI-pin v8/v9 не змінено;
- базовий `scripts/test-pascal-probe.sh` і `make test-valid-cards-static` не послаблено;
- gp107 #33 лишається Draft без повного exact-head `make test`.

Фінальний маркер гейту тепер:
`CAPABILITY-DRIVER-GATE-OK c11=yes layout=32/68/140 negatives=8 mmio=read-only-opt-in asm=equiv-x86_64 hardware-mmio=NOT-RUN`.

## 5. Питання без відповіді й найменший крок

Який BAR0-offset безпечно читати? Асемблер тут не допомагає: потрібен
source-level факт або окремий owner approval на фізичний read. Програмний
`--allow-mmio` не є цим дозволом. Фізичний тест лишається
**NOT AUTHORIZED / NOT RUN**.
