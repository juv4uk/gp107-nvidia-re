# 26 — REA P1: enum allocation у `uvm_rm_mem_alloc` і виправлення disalignment

Це вузький наступний крок після `docs/25`. Мета — не новий broad search, а
лінійна disassembly від справжніх entry-адрес і перевірка меж інструкцій через
`ao`. Одночасно виправлено помилку читання з `docs/25`: `mov eax, 0x1e0`
був артефактом старту `pd` із середини інструкції.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | `docs/23` (експортні символи в `nvidia.ko`), `docs/24` (RM dispatch window), `docs/25` (11 call-site у `nvidia-uvm.ko`) | не повторювати |
| `PARTIAL` | `docs/25`: enum у `uvm_rm_mem_alloc` і значення `[rax+0x1e0]` були `UNPROVEN` | уточнено нижче |
| `UPSTREAM_EXISTS` | Nouveau/NVKM allocation paths, NVK | implementation authority, не реверсити |
| `UNIQUE_GAP` | розгалуження AllocFB/AllocSys у shipped R580 `nvidia-uvm.ko`, вирівнювання інструкцій | ціль звіту |

Pin-и v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract, ABI-pin не змінено.

## 1. Тарґет і Evidence

| Поле | Значення |
|---|---|
| Shipped artifact | `/lib/modules/7.2.15+kali-amd64/updates/dkms/nvidia-uvm.ko.xz`, SHA-256 `80132204f76981b2373baeb936866347e3c80e8527feb118bffe03f6adc10e8f` |
| Target | `/tmp/opencode/rea-nvidia-uvm/nvidia-uvm.ko`, SHA-256 `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` |
| Tool | REA `execute_rizin_command` (Rizin), provider executable `rizin`; Ghidra-сесію закрито раніше, edits не створював |
| Команди | `pd 220 @ 0x0802d5f0`, `pd 1150 @ 0x080355c0`, `pd 34 @ 0x0802d8f0`, `pd 46 @ 0x0802dad0`, `ao 12 @ 0x0802d6db`, `ao 6 @ 0x08035e64` |
| Bundle | `evidence/rea-20261128/evidence-p1-uvm-alloc-enums.json`, 38 record (11 для цього target), SHA-256 `8fcd3b675cc616f7cf95d2c70673e4d2b9b1efae12829428f6f142a7a7e2323a` |

Evidence ID:

- `ev_6ed5921e80256eb81907caed4a52cfa5988ac2e0f897b242dcd80c8f682dc01b` —
  лінійна disassembly від entry `0x0802d5f0` і `0x080355c0`.
- `ev_72e4dd66cd45cbcb19cb304f63307f06dbdd0bad58a7df500c6d6242bfe9d1c9` —
  `ao` з розмірами інструкцій і контрольні `pd` з виправлених границь.
- `ev_7df41a5a681602340ef0e3d469d3dc4d2ced0b38347e67906a5324f897d7e2e9` —
  wrapper-функції; тут само `pdf @ 0x0802d5f0` дав `Cannot find function`,
  а `axt @ 0x0802d5f0` — порожньо. Це **не absence-proof**; прогалину
  заповнено лінійним `pd` і `ao`.

## 2. `uvm_rm_mem_alloc`: що саме доведено

Enclosing function: `uvm_rm_mem_alloc`, `0x0802d5f0`, 737 B (`is`).

| Факт | Статус |
|---|---|
| `rdi` → `rbp`, `esi` → `r13d`, `rdx` → `r12`, `rcx` і `r8` зберігаються; `__uvm_kvmalloc_zero(0x850, 0xd0, "nvidia-uvm/uvm_rm_mem.c", "uvm_rm_mem_alloc")` | `statically proven` (рядок — `string-only` шлях файлу з бінарника) |
| `cmp r13d, 0x01` (`0x0802d6a3`): якщо `!= 1` → `MemoryAllocFB` (`0x0802d6c6`), якщо `== 1` → `MemoryAllocSys` (`0x0802d78e`) | `statically proven` |
| Після FB-успіху: `[r14] = r13d`, `[r14+0x848] = r12`, `[r14+0x840] = rbp`; GPU index з `[rbp+0x80]`, перевірка `< 0x101`, `[r14+idx*8+0x30] = r12`, далі `uvm_processor_mask_set` і `rm_mem_map_gpu_proxy` | `statically proven` (`ao` підтверджує межі `0x0802d6e4` = 7 B, `0x0802d6eb` = 6 B, `0x0802d6f1` = 7 B) |
| Після Sys-успіху: `cmp eax, 0x51`, `cmp r12, 0xffff`, повтор `MemoryAllocSys` з `[rsp+0x18] = 0` | `statically proven` |
| `1` = system-memory enum, `0x51` = певний status code, `0x1908` = RM object handle | `interpretation`; жодного RM class/heap identity не доведено |

Важливо: `pd 220 @ 0x0802d5f0` на ділянці `0x0802d6eb..0x0802d6f8` показує
`invalid/popfq`, але `ao 12 @ 0x0802d6db` і `pd 20 @ 0x0802d6d5` дають
узгоджені інструкції. Тому висновок про `cmp rbx, 0x101` базується на
**targeted re-synchronization**, а не на сліпій вірі Одній лінійній
disassembly. Це межа методу, не новий факт про RM.

## 3. Обгортки й call-site з enum = 1

| Функція | Адреса, розмір | Що викликає | Статус |
|---|---|---|---|
| `uvm_rm_mem_alloc_and_map_cpu` | `0x0802d8f0`, 123 B | `uvm_rm_mem_alloc` → `uvm_rm_mem_map_cpu`; при помилці `uvm_rm_mem_free` | `statically proven` |
| `uvm_rm_mem_alloc_and_map_all` | `0x0802dad0`, 179 B | `uvm_rm_mem_alloc` → `uvm_rm_mem_map_cpu` → `uvm_rm_mem_map_all_gpus`; при помилці `uvm_rm_mem_free` | `statically proven` |
| Call-site в `channel_pool_add` | `0x08036339` | `esi = 1`, `ecx = 0x20`, `edx = r12d*0x1a0`, output `[r15+0x68]` | `statically proven` |
| Другий call-site | `0x080363ad` | `esi = 1`, `ecx = 0`, `edx = (r12d<<3)`, output `[r15+0x70]` | `statically proven` |

Обидва call-site передають `esi = 1`, тобто проходять гілкою `AllocSys`.
Це підтримує `interpretation` з попереднього розділу, але не доводить,
який саме RM heap class або фізичне розміщення використовується.

## 4. `channel_pool_add`: виправлення зсуву

Лінійна disassembly від справжнього entry `0x080355c0` дає:

- `0x08035e64`: `cmp byte [rax+0xc16d], 0x00`, `jnz 0x8036132`;
- `0x08035e71`: `mov rdi, qword [rax+0x1e0]`;
- `0x08035e78`: `lea rsi, [rsp+0x30]`;
- `0x08035e7d`: `call nvUvmInterfacePagingChannelAllocate`.

Парне читання зі стартом `pd` коло `0x08035e66` давало `mov eax, 0x1e0`
за адресою `0x08035e73`; `ao 6 @ 0x08035e64` підтверджує, що це був
неправильний зсув, а не окрема інструкція. Статус: `statically proven`
для `rdi = [rax+0x1e0]`, `string-only` для `"Proxy %u CE %u"`,
`UNPROVEN` для типу об'єкта за цим покажчиком.

Той самий вираз `rdi = [rax+0x1e0]` зустрічається в `0x08036717` перед
`nvUvmInterfaceQueryCopyEnginesCaps`. Припущення «це RM handle» лишається
`interpretation`; доводити його треба окремим store-site аналізом, а не
назвою поля.

## 5. Межі

| Твердження | Статус |
|---|---|
| `nvUvmInterface*` мають call-site; enum 1 веде до AllocSys; обгортки мають cleanup-on-error | `statically proven` |
| `0x1e0`, `0xc16d`, `0x1908`, `0x101`, `0x51`, `0x1a0` — константи інструкцій, не доведені RM-класи/поля | `statically proven` як інструкції; семантика `interpretation`/`UNPROVEN` |
| `memType=8` (Vulkan tuple) проходить саме цим шляхом; runlist/notifier/fence; BOOT0; NVK↔NVIDIA performance gap | `UNPROVEN` |
| Порожній `axt` і помилка `pdf` | coverage limitation, `UNPROVEN` не absence-proof |

Не робилось: MMIO/BAR read/write, `nva`, RM-запити, reboot, GPU compute,
PR #21 executable, Ghidra-pseudocode, vendor source, transfer коду,
release/tag/publish, зміни pin-ів/SENS/CML/ADR/target contract.

## 6. Наступний найменший крок

Знайти store в `[+0x1e0]` і `[+0xc16d]` у межах уже відкритої лінійної
disassembly `channel_pool_add` (без `/r`, без `izz~`), щоб з'ясувати, який
об'єкт ініціює ці поля. Після цього — окремий small-window `-h` аналіз
`nvUvmInterfacePagingChannelAllocate`call site, не змішуючи з runlist.

## Ukrainian one-liner

Лінійна disassembly і `ao` підтвердили enum-розгалуження `uvm_rm_mem_alloc`
та виправили зсув у `channel_pool_add`; семантика RM-полів, runlist і BOOT0
лишаються UNPROVEN.
