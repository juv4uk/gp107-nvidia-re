# 24 — REA P1: вузьке вікно RM-dispatch після function-level карт

Продовження `docs/23`: не новий широкий scan, а два адресні вікна в межах уже
знайдених функцій. Мета — перевірити, чи можна зв'язати таблиці імен
(`kchannelBindToRunlist_IMPL`, `MAP_MEMORY_DMA`, `CTRL_GPFIFO_*`) із конкретним
RM-кодом, не перетворюючи константи на доведену семантику.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | Nouveau/NVKM class semantics, NVK/NAK, Envytools, `nvdisasm` SM61 | не повторювати |
| `PARTIAL` | `docs/23` — 16 function-level(map A+B) записів без RM command codes | цей звіт звужує dispatch |
| `UNIQUE_GAP` | `_nv046783rm` / `_nv046784rm` — приватні RM ядра, на які посилаються UVM→RM обгортки |тут: фактичні константи й міжпроцедурні межі |
| `UPSTREAM_EXISTS` | non-stall event index lead (13.09.2026) | лишається lead, не GP107-доказ |

## 1. Тарґет і Evidence

| Поле | Значення |
|---|---|
| Тарґет | `/tmp/opencode/rea-nvidia/nvidia.ko`, SHA-256 `95c5fa5ab0546ee40842cda2ec20ea3ec1e196a5afee1580944ecae2ffc75bbe` |
| Tool | REA `execute_rizin_command`, Rizin, provider version не підтверджено |
| Команди | `is~_nv04678[34]rm`, `pd 75 @ addr`, `pD 5200 @ 0x080df240~<addr>`, `ir~<addr>`, `e??~search.`, `iS~text` |
| Bundle | `evidence/rea-20261128/evidence-p1-dispatch-window.json`, 27 record, SHA-256 `a3286bdaa943704724592001da9341552c369918f554abebaf72f7ce20cf46c2` |

## 2. `statically proven` факти

### 2.1 Таблиця RM-диспетчера

`_nv054249rm`, `0x080cde30`, 20 B:

```
mov eax, edi
imul rax, rax, 0xe8
add  rax, <.rodata/base 0x08eb77e0>
ret
```

Тобто функція перетворює цілочисельний аргумент на адресу у таблиці з
кроком `0xe8` (232 байти). Назва таблиці, зміст записів і те, чи є цей індекс
RM class/method ID, **UNPROVEN**. Викликається з `_nv046834rm`, `_nv046783rm`,
`_nv046784rm` (останні два — нові witness у цьому звіті).
Evidence: `ev_0eb7e6e6f6f050d4d54c0b58d43f19ff0e105df6cd1d94bc2c8745b713b215a5`,
`ev_25eb64481f71ef6bb5e9ab67adfe5085d37cbdfc02f5b4ec5bec15d72f3d5bb6`.

### 2.2 `_nv046783rm`, `0x080d5c80`, 756 B

- нулює 16×8 байт локального блоку через `rep stosq`;
- викликає `_nv054249rm(1)`;
- записує `0xdeaf0004` у `qword [rbp+0x20]`;
- будує біти в `dword [rbp+0x38]`: базова маска `0x22000000`,
  `0x10000000` якщо `byte [rbx+0x18] != 0`, `0x800000` якщо
  `qword [rbx+0x08] == 0x1000`;
- перевіряє розміри `0x200000` і `(x-0x10000) & 0xfffffffffffeffff == 0`;
- враховує `byte [rbx+0x19]` і `byte [rbx+0x20]`;
- виклик через `__x86_indirect_thunk_rax` з `r8d = 0x3e` (62) і `push 0x80`.

Це **statically proven** на рівні інструкцій. Interpretation: схоже на
налаштування RM memory parameters, але без розшифрованого запису таблиці це
не доводить ані class, ані те, що шлях використовується нашим Vulkan
workload. Частина ліній у `pd` позначена `invalid` через розсинхрон
лінійного disassembly — це межа coverage, не доказ відсутності коду.
Evidence: `ev_0eb7e6e6f6f050d4d54c0b58d43f19ff0e105df6cd1d94bc2c8745b713b215a5`.

### 2.3 `_nv046784rm`, `0x080d8430`, 784 B

- викликає `_nv054249rm(1)`, потім `_nv052697rm(0x58)` (allocation 88 B);
- `dword [rbp+0x38] = 0x8080100`, `qword [rbp+0x30] = 0xdeaf0004`;
- `edx = 0x1000` як fallback, коли `qword [rcx+0x08] == 0`;
- перевірки `qword [rcx]` на `0x200000` / `0x10000` / `0x1000`;
- непрямий виклик з `r8d = 0x50a0` (20640) і `push 0x80`.

Спільний маркер `0xdeaf0004` у 2.2 і 2.3 статично доведений; його сенс
**UNPROVEN**. Evidence:
`ev_0eb7e6e6f6f050d4d54c0b58d43f19ff0e105df6cd1d94bc2c8745b713b215a5`.

### 2.4 Додаткові адреси RM-ядер

`_nv046846rm` = `0x080de7f0` (529 B), `_nv046848rm` = `0x080deb10` (372 B),
`_nv046847rm` = `0x080dea10` (253 B) — це ядра, на які вже посилаються
`rm_gpu_ops_memory_cpu_map` і `rm_gpu_ops_memory_free` з `docs/23`.
Тут лише зафіксовано адреси/розміри; тіла не розібрані.
Evidence: `ev_aec1126f1cb156f8768e705aefda625efe74cdf7e0b34c7c204be3f574bf5878`.

## 3. Спроба зв'язати runlist/notifier з рядками — результат

- `ir~0x0dcbfd40`, `ir~0x0dd5e410`, `ir~0x0dd5cd5f` — порожньо:
  `ev_c9efaaa9a8a2ae888555c6c3dcd49ebcc762d6b96e9eec7ea986a5cf0ec12782`.
  Порожній результат relocation-inventory **не є absence-proof**: у `pd`
  earlier видно, що Rizin резолвить такі посилання як `.rodata + addend`.
- `pD 5200 @ 0x080df240~0dcbfd40` (і для `0dd5e410`, `0dd5cd5f`) — порожньо
  в межах `_nv046796rm`: `ev_aec1126f1cb156f8768e705aefda625efe74cdf7e0b34c7c204be3f574bf5878`.
  Coverage обмежений одним 5147-байтовим ядром, не всім модулем.
- `e search.range.from/to` у цій збірці Rizin не існує
  (`ev_4e276e8d5064a9dc851307e8b355f59d54a7b5c3abdfd2b88f8790a2297af3a1`);
  доступний лише `search.in` (`ev_e2396ae1ff7bad31e36df123cf5c3450565cdb3a4e137cc802fcaaf5f2e5e51e`).
  Необмежений `/r` раніше перевищив транспортний бюджет 10 MiB
  (`ev_c557f86e8d4e25b45381cb219980fc0677226ca5658c3f3c66146365bb0c4ecc`).

Отже `kchannelBindToRunlist_IMPL` лишається **string-only**,
`CHANNEL_RUNLIST_CORRELATED` — **UNPROVEN**. Цього разу не робився новий
широкий `/r`, не запускався Ghidra full analysis.

## 4. Статуси

| Твердження | Статус |
|---|---|
| Адреси, розміри, константи, виклики `_nv054249rm(1)`, непрямі виклики | `statically proven` |
| Крок таблиці `0xe8` | `statically proven`; призначення таблиці — `UNPROVEN` |
| `0xdeaf0004`, `0x8080100`, `r8d=0x3e`, `r8d=0x50a0` як RM class/method | `UNPROVEN` (interpretation не піднято до факту) |
| Зв'язок `_nv046783rm` із memory path нашого benchmark | `UNPROVEN` |
| Runlist/notifier/fence lifecycle | `UNPROVEN/PARTIAL` |
| Причина NVK/NVIDIA performance gap, BOOT0 | `UNPROVEN`, без змін |

## 5. Наступний найменший крок

Не повторювати `izz~...`. Потрібен або (a) прицільний reference search по
`.text` з іншим механізмом обмеження (не `/r` на весь модуль), або (b) окремий
proprietary `nvidia-uvm.ko` як target для caller-ланцюга
`nvUvmInterfaceMemory*`. Обидва — окремі завдання з новим Evidence bundle.

Не робилось: MMIO/BAR read/write, `nva`, RM-запити, reboot, firmware/driver /
boot зміни, PR #21 executable, Ghidra-pseudocode, vendor source, transfer коду,
release/tag, зміни pin-ів/SENS/CML/`wsm-os-lisp`/ADR/target contract.

## Ukrainian one-liner

Вузькі вікна показали RM-таблицю з кроком `0xe8` і два маркери в приватних
ядрах, але рядки `kchannelBindToRunlist_IMPL` і `MAP_MEMORY_DMA` досі не мають
доведеного call-site: далі треба обмежений reference tool або окремий
`nvidia-uvm.ko`, а не ще один широкий scan.
