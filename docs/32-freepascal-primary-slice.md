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
| `pascal/gp107_mmio.pas` | Opt-in/driver/BAR/offset checks; returns code 21; no `FpOpen`/`FpMMap` path |
| `pascal/gp107_capabilities.pas` | Машиночитаний capability-ledger, байтово ідентичний C-виводу |
| `pascal/gp107ctl.pas` | CLI `inventory`, `mmio-read`, `capabilities`, `layout` |
| `pascal/Makefile` | Ціль `gp107ctl-pascal` з FPC 3.2.2, `-Sh`, `-XS` |
| `scripts/test-capability-driver.sh` | Pascal/C parity для позитивних і негативних випадків |

Збірка: `make -C pascal gp107ctl-pascal`. Компілятор перевіряється через
`make -C pascal check-fpc`: очікується точно `3.2.2`.

`Load32Asm` лишається приватним implementation-only instruction-reference leaf для статичної
перевірки `mov eax,[rdi]` + `lfence`; після #55 він більше не експортується з public unit interface.
`Read32` не викликає його. Public API не відкриває `resource0`, не мапить BAR і не читає register.

## 2. Статус фактів

| # | Факт | Статус | Свідок / межа |
|---:|---|---|---|
| 1 | FPC 3.2.2 компілює Pascal-зріз з `-XS` | **statically proven** | `FPC-COMPILE-OK version=3.2.2 layout=32/68/140` |
| 2 | Розкладки `32/68/140` байт | **statically proven** | `{$if SizeOf(...)<>...}{$fatal}` і `LAYOUT-OK identity=32 binding=68 inventory=140` |
| 3 | Inline `lfence` присутній у бінарнику | **statically proven** | `PASCAL-ASM-STATIC-OK primitive=movl+lfence sysv-amd64`; `objdump -d` |
| 4 | Pascal/C inventory, ledger та safe-offset error байтово ідентичні на fixture | **synthetic-fixture** | `PASCAL-PARITY-OK`, `NEGATIVE-SAFE-OFFSET-UNPROVEN-OK` |
| 5 | Pascal/C негативні маркери ідентичні: card-count, config-read, bdf mismatch, opt-in, bound-driver, BAR0 size, alignment, offset bounds та safe-offset | **synthetic-fixture** | `cmp` stderr у кожному named step |
| 6 | Прямий виклик публічного C API не обходить opt-in і driver-bound | **runtime-proven (fixture)** | `MMIO-API-GATE-OK direct-call=guarded optin=required bound-driver=denied` |
| 7 | Ledger `denied`/`deferred` та BAR-flag mutation однакові в Pascal і C; `granted` відсутній | **synthetic-fixture** | `LEDGER-SAFE-OFFSET-DEFERRED-OK`, `BAR-FLAG-MUTATION-OK` |
| 8 | На реальному hostі Pascal inventory збігається з C | **runtime-proven** | `HOST-INVENTORY-PASS evidence=runtime-proven pascal=C`; `10de:1c82 @ 0000:01:00.0` |
| 9 | Фізичний MMIO-доступ до реальної GP107 | **NOT RUN** | `nvidia` bound; cmdline без `wsm_open_driver=1`; жодного unbind/reboot |
| 10 | BOOT0, `0x137000A1`, RM class/runlist/notifier/fence, `BDF ↔ RM gpu_id` | **UNPROVEN / string-only** | Pascal не додає жодного нового твердження; константа відсутня у коді |
| 11 | Використання Pascal як основи майбутнього релізу під плату власника | **design choice / interpretation** | owner-заява про цільове залізо; не release-рішення й не ABI-pin |
| 12 | C і Pascal повторно звіряють PCI identity та driver binding через один pinned PCI directory fd | **source + compile + synthetic-fixture PASS** | GP107 PR #56 exact-head `df73a0a5cb17a58e899ea25ad680c54ebaa8a88c`; FPC 3.2.2 compile, C11 fail-closed gate і Pascal/C parity пройшли у CI run #46087161680; code 21 лишається кінцевим safe-offset gate |
| 13 | Pascal pinned-dirfd negatives: bound/unbound, invalid driver entry, BDF symlink swap та same-BDF wrong-device swap | **synthetic-fixture PASS** | п’ять сценаріїв у `scripts/test-capability-driver.sh` пройшли в exact-head CI #46087161680; це fixture evidence, не тест фізичного hotplug або kernel remove/re-add race |

## 3. Межі

- Exact-head CI run [#46087161680](https://github.com/juv4uk/gp107-nvidia-re/actions/runs/46087161680) passed on PR head `df73a0a5cb17a58e899ea25ad680c54ebaa8a88c`: static guard, FPC 3.2.2 compilation, C11 fail-closed gate and Pascal/C fixture parity. The runner reported `HOST-INVENTORY-SKIP reason=GP107-absent`; no probe executable or physical GPU operation was run.

- Після `docs/33` авторитетним інструкційним контрактом є саме x86-64 `.S`
  (`gp107_mmio_load32_asm`, 6 байт); Pascal і C11 лишаються, відповідно,
  fail-closed обгорткою та oracle байтової еквівалентності. Жоден з них не
  оголошується продукційним драйвером чи релізом.
- Жодного `PROT_WRITE`, `MAP_FIXED`, `O_RDWR`, write-MMIO, RM-запиту, transfer
  коду, firmware, GPFIFO чи reboot.
- SENS, CML, `wsm-os-lisp`, ADR, target contract і ABI-pin v8/v9 не змінено.
- Базовий `scripts/test-pascal-probe.sh`, `make test-valid-cards-static` і
  старий C-гейт не послаблено.
- gp107 #33 лишається Draft, PR #21 — Draft і `NOT_RUN`.

Підсумковий маркер гейту:
`CAPABILITY-DRIVER-GATE-OK c11=yes fpc=3.2.2 layout=32/68/140 fail-closed=passed mmio=deferred safe-offset=unproven pascal=C-parity hardware-mmio=NOT-AUTHORIZED/NOT-RUN`.

## 4. Питання без відповіді й найменший крок

Питання без відповіді: який BAR0-offset безпечно читати? Найменший наступний
крок — source-only audit register semantics та exact kernel/source pairing.
Не запускати `mmio-read` на фізичному пристрої: API навмисно відмовляє до
mapping, а BOOT0 лишається `UNPROVEN`.
