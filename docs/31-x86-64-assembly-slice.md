# 31 — Асемблерний зріз під конкретну плату (GP107 / x86-64)

Власник зазначив, що реліз збиратиметься тільки під його залізо, і що
асемблер тут природний інструмент. Це **не змінює межі доказів**: мова не
перетворює `UNPROVEN` на факт. Асемблер застосовано лише до вже доведеного
read-only примітиву, а не до невідомих регістрів чи RM-протоколу.

## 1. Що саме на асемблері

`lib/gp107_mmio_asm.S` — власний x86-64 SysV примітив; Pascal-декларація `Load32Asm()` є лише в `implementation` і не експортується з unit interface:

```text
rdi = вже змапована read-only адреса
movl (%rdi), %eax
lfence
ret
```

- один 32-бітний load і `lfence` після нього;
- жодних констант регістрів, BOOT0-адрес, vendor-послідовностей чи write;
- ASM load leaf зберігається лише як ізольований reference; C і Pascal public API
  його не викликають та не передають йому BAR/resource pointer;
- збірка `gp107ctl-asm` використовує `-DGP107_USE_ASM=1`, звичайний `gp107ctl`
  лишається C-версією для порівняння.

`make -C lib profile` друкує:
`GP107-PROFILE-OK vendor=0x10de device=0x1c82 bdf=0000:01:00.0 arch=x86_64 asm=read-only`.
Це **профіль збірки під плату власника**, а не release, tag, publish чи installer.

## 2. Статус фактів

| # | Факт | Статус | Свідок / межа |
|---:|---|---|---|
| 1 | Примітив `movl (%rdi),%eax` + `lfence` + `ret` присутній у бінарнику | **statically proven** | `objdump -d gp107ctl-asm` показує `gp107_mmio_load32_asm` і `lfence`; маркер `ASM-STATIC-OK` |
| 2 | C/ASM-linked capability ledger однаковий | **synthetic-fixture** | inventory/ledger only; no synthetic MMIO read |
| 3 | Capability-ledger однаковий для обох збірок | **synthetic-fixture** | `cmp` виводу `capabilities --allow-mmio`, без розбіжностей |
| 4 | Профіль збірки прив’язаний до `10de:1c82 @ 0000:01:00.0`, x86-64 | **design choice / statically proven** | константи в `lib/gp107_identity.h`, вивід `GP107-PROFILE-OK` |
| 5 | Фізичний read апертури на реальній GP107 | **NOT AUTHORIZED / NOT RUN** | `nvidia` bound; жодного unbind/reboot/MMIO-тесту |
| 6 | BOOT0, `0x137000A1`, RM class/runlist/notifier/fence, причина розриву NVK↔NVIDIA | **UNPROVEN / string-only** | асемблер не додає жодного нового твердження |
| 7 | Асемблерний шлях дає право запису чи dispatch | **UNPROVEN, не стверджується** | у коді немає write, RM, FIFO чи doorbell |

## 3. Виправлення межі MMIO

Попередня версія private mapper могла відобразити caller-selected BAR0 offset.
Оскільки safe register semantics не доведені, production API тепер відмовляє
до `resource0` content open або mapping:

- API перевіряє exact PCI identity через pinned dirfd, driver binding, BAR0
  memory-space, BAR size, 32-bit alignment та offset bounds.
- Після цих software gates API повертає code 21 `read-safe-offset-unproven`.
- C identity check повторно перевіряє `uevent`, `vendor/device/revision`,
  subsystem IDs та PCI config через той самий відкритий directory fd.
- Inventory використовує `stat(resource0)` лише як metadata розміру; жоден
  MMIO API не відкриває вміст `resource0`, не мапить BAR і не читає регістр.
- Synthetic regression cases перевіряють BDF/same-BDF substitution, I/O-space,
  короткий sysfs resource metadata, unaligned/out-of-window offsets та code 21.

Це **synthetic-fixture**; фізичне MMIO лишається `NOT AUTHORIZED / NOT RUN`.

## 4. Що не змінилося

- жодного release/tag/publish чи публікації артефакта;
- жодного MMIO-запису, `nva`, RM-запиту, firmware, GPFIFO чи reboot;
- SENS, CML, `wsm-os-lisp`, ADR, target contract і ABI-pin v8/v9 не змінено;
- базовий `scripts/test-pascal-probe.sh` і `make test-valid-cards-static` не послаблено;
- gp107 #33 лишається Draft без повного exact-head `make test`;
- `docs/33` підносить цей `.S`-примітив до авторитетного opcode-контракту,
  але не до релізу: Pascal і C11 лишаються обгорткою та oracle.

Фінальний маркер гейту тепер:
`CAPABILITY-DRIVER-GATE-OK c11=yes fpc=3.2.2 layout=32/68/140 fail-closed=passed mmio=deferred safe-offset=unproven pascal=C-parity hardware-mmio=NOT-AUTHORIZED/NOT-RUN`.

## 5. Питання без відповіді й найменший крок

Який BAR0-offset безпечно читати? Асемблер тут не допомагає: потрібен
source-level факт або окремий owner approval на фізичний read. Програмний
`--allow-mmio` не є цим дозволом. Фізичний тест лишається
**NOT AUTHORIZED / NOT RUN**.
