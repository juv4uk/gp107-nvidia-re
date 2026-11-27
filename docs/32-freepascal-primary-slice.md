# 32 — Free Pascal як основна research-реалізація identity

Free Pascal 3.2.2 є основною мовою цього дослідницького зрізу для sysfs PCI
identity, inventory та capability projection. C11-зріз залишається
паралельною reference-реалізацією для перевірки layout і byte-for-byte parity.
Це не змінює меж доказів і не є ABI-рішенням.

## Що реалізовано

| Файл | Призначення |
|---|---|
| `pascal/gp107_identity.pas` | Fail-closed sysfs inventory, PCI header та driver binding; packed layout assertions |
| `pascal/gp107_capabilities.pas` | Ledger, byte-identical до C reference |
| `pascal/gp107_mmio.pas` | Публічний fail-closed API; завжди повертає `STATUS_NOT_AUTHORIZED` |
| `pascal/gp107ctl.pas` | CLI inventory, capabilities, layout і відмовний mmio-read |
| `pascal/Makefile` | FPC 3.2.2 pinned build |
| `scripts/test-capability-driver.sh` | C/Pascal identity, denial і ledger parity на synthetic sysfs |

## Фізичний MMIO

**НЕ АВТОРИЗОВАНО / НЕ ВИКОНУВАЛОСЯ.** Pascal `Read32()` не має
`resource0` open, `mmap`, pointer dereference або inline assembly. C
`gp107_mmio_read32()` має ту саму fail-closed поведінку. Прапорець
`--allow-mmio` не надає owner authorization і не змінює результату API.

## Статус доказів

| Факт | Статус |
|---|---|
| FPC 3.2.2 build та layout `32/68/140` | **очікує exact-head CI** |
| C/Pascal inventory та ledger parity на synthetic fixtures | **очікує exact-head CI** |
| CLI denial з/без `--allow-mmio` | **очікує exact-head CI** |
| Direct C/Pascal API denial | **очікує exact-head CI** |
| Host H170 inventory у цій сесії | **NOT RUN**; executor offline |
| BOOT0, BAR0 register semantics, RM/channel/runlist/fence | **UNPROVEN** |

Перевірка локального або hosted gate має використовувати:
`make -C lib clean all`, `make -C pascal gp107ctl-pascal` та
`bash scripts/test-capability-driver.sh`.

Очікуваний маркер:

`CAPABILITY-DRIVER-GATE-OK c11=yes fpc=3.2.2 layout=32/68/140 fail-closed=passed synthetic-sysfs=only pascal=parity physical-mmio=NOT-AUTHORIZED/NOT-RUN`

Це не hardware validation, не release і не зміна ABI pin.
