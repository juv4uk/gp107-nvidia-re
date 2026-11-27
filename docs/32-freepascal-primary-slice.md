# 32 — Free Pascal як основна мова capability-identity зрізу

Власник уточнив: писати одразу на Free Pascal, бо в нього є доступ до C-бібліотек
і зручний асемблер. Це не змінює меж доказів: мова не перетворює `UNPROVEN` на
факт. Новий Pascal-зріз є **основною реалізацією** для research-коду, а C11-зріз
лишається еталоном для байтової еквівалентності. Реліз, tag, publish, installer,
RM, firmware, reboot і фізичний MMIO не виконувалися.

## 1. Що додано

| Файл | Призначення |
|---|---|
| `pascal/gp107_identity.pas` | FAIL-CLOSED sysfs inventory; публічний PCI-заголовок; `{$packrecords 1}` + `{$if SizeOf(...)}{$fatal}` |
| `pascal/gp107_mmio.pas` | Ті самі ворота opt-in/driver-bound/size/offset; `mmap(PROT_READ\|MAP_SHARED)`; власний inline-асемблер `mov eax,[rdi]` + `lfence` |
| `pascal/gp107_capabilities.pas` | Машиночитаний capability-ledger, байтово ідентичний C-виводу |
| `pascal/gp107ctl.pas` | CLI `inventory`, `mmio-read`, `capabilities`, `layout` |
| `pascal/Makefile` | Ціль `gp107ctl-pascal` з FPC 3.2.2, `-Sh`, `-XS` |
| `scripts/test-capability-driver.sh` | Pascal/C parity для позитивних і негативних випадків |

Збірка: `make -C pascal gp107ctl-pascal`. Компілятор перевіряється через
`make -C pascal check-fpc`: очікується точно `3.2.2`.

Inline-асемблер належить цьому проєкту. Він робить **одне** 32-бітне читання
вже змапованого read-only вікна і не містить регістрних констант, BOOT0-адрес,
запису, vendor-послідовності чи RM-коду.

## 2. Статус фактів

| # | Факт | Статус | Свідок / межа |
|---:|---|---|---|
| 1 | FPC 3.2.2 компілює Pascal-зріз з `-XS` | **statically proven** | `FPC-COMPILE-OK version=3.2.2 layout=32/68/140` |
| 2 | Розкладки `32/68/140` байт | **statically proven** | `{$if SizeOf(...)<>...}{$fatal}` і `LAYOUT-OK identity=32 binding=68 inventory=140` |
| 3 | Inline `lfence` присутній у бінарнику | **statically proven** | `PASCAL-ASM-STATIC-OK primitive=movl+lfence sysv-amd64`; `objdump -d` |
| 4 | Pascal/C виводи `inventory`, `capabilities` і `mmio-read` байтово ідентичні на синтетичному sysfs | **runtime-proven (fixture)** | `PASCAL-PARITY-OK`, `PASCAL-MMIO-PARITY-OK` |
| 5 | Pascal/C негативні маркери ідентичні: card-count, config-read, bdf-mismatch, driver-binding-read, opt-in, driver-bound, resource0-size, offset | **runtime-proven (fixture)** | `cmp` stderr у кожному named step |
| 6 | Прямий виклик публічного C API не обходить opt-in і driver-bound | **runtime-proven (fixture)** | `MMIO-API-GATE-OK direct-call=guarded optin=required bound-driver=denied` |
| 7 | Ledger `deferred`/`granted` і BAR-flag mutation однакові в Pascal і C | **runtime-proven (fixture)** | `LEDGER-DEFERRED-OK`, `LEDGER-GRANTED-OK`, `BAR-FLAG-MUTATION-OK` |
| 8 | На реальному hostі Pascal inventory збігається з C | **runtime-proven** | `HOST-INVENTORY-PASS evidence=runtime-proven pascal=C`; `10de:1c82 @ 0000:01:00.0` |
| 9 | Фізичний MMIO-доступ до реальної GP107 | **NOT RUN** | `nvidia` bound; cmdline без `wsm_open_driver=1`; жодного unbind/reboot |
| 10 | BOOT0, `0x137000A1`, RM class/runlist/notifier/fence, `BDF ↔ RM gpu_id` | **UNPROVEN / string-only** | Pascal не додає жодного нового твердження; константа відсутня у коді |
| 11 | Використання Pascal як основи майбутнього релізу під плату власника | **design choice / interpretation** | owner-заява про цільове залізо; не release-рішення й не ABI-pin |

## 3. Межі

- C11-код і x86-64 `.S` лишаються в репозиторії **лише як контрольні еталони**;
  жоден з них не оголошується продукційним драйвером.
- Жодного `PROT_WRITE`, `MAP_FIXED`, `O_RDWR`, write-MMIO, RM-запиту, transfer
  коду, firmware, GPFIFO чи reboot.
- SENS, CML, `wsm-os-lisp`, ADR, target contract і ABI-pin v8/v9 не змінено.
- Базовий `scripts/test-pascal-probe.sh`, `make test-valid-cards-static` і
  старий C-гейт не послаблено.
- gp107 #33 лишається Draft, PR #21 — Draft і `NOT_RUN`.

Підсумковий маркер гейту:
`CAPABILITY-DRIVER-GATE-OK c11=yes fpc=3.2.2 layout=32/68/140 fail-closed=passed synthetic-mmio=only asm=equiv-x86_64 pascal=equiv hardware-mmio=NOT-AUTHORIZED/NOT-RUN`.

## 4. Питання без відповіді й найменший крок

Питання без відповіді: який BAR0-offset безпечно читати після unbind? Асемблер
не змінює відповідь. Найменший крок — після окремого owner-рішення запустити
`pascal/gp107ctl-pascal mmio-read --offset=0x... --allow-mmio`, зберегти
stdout/stderr як artifact з SHA-256 і позначити `runtime-proven` або fail-closed.
Без цього BOOT0 лишається `UNPROVEN`.
