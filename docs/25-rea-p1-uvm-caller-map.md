# 25 — REA P1: caller-карта в пропрієтарному `nvidia-uvm.ko`

Це наступний найменший крок після `docs/24`: не ще один search у `nvidia.ko`,
а окремий shipped-модуль-споживач. У `docs/23` caller-ланцюг
`nvUvmInterfaceMemory*` був `UNPROVEN`, бо в `nvidia.ko` це експортовані символи
без локальних входів. Тут ті самі інтерфейси знайдено як **імпорти з конкретними
call-site**.

## 0. Triage перед завданням

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | `docs/23`, `docs/24`: 16 function-level записів у `nvidia.ko`, RM dispatch window | не повторювати |
| `PARTIAL` | `docs/02` runtime chain `NV_ESC_RM_ALLOC → NV01_MEMORY_LOCAL_USER → UVM_CREATE_EXTERNAL_RANGE → UVM_MAP_EXTERNAL_ALLOCATION` | використано як контекст, не ототожнено з цими call-site |
| `UPSTREAM_EXISTS` | Nouveau/NVKM UVM-еквіваленти, NVK/NAK | implementation authority, не реверсити |
| `UNIQUE_GAP` | імпортні call-site `nvUvmInterface*` у R580 `nvidia-uvm.ko`, GPFIFO/sec2/semaphore helper-и | ціль цього звіту |

Issue #18 лишається `RUNLIST_ID_NOT_OBSERVED`; issue #28 не змінено; pin-и v8/v9 не чіпались.

## 1. Тарґет, метод, Evidence

| Поле | Значення |
|---|---|
| Шипований артефакт | `/lib/modules/7.2.15+kali-amd64/updates/dkms/nvidia-uvm.ko.xz`, SHA-256 `80132204f76981b2373baeb936866347e3c80e8527feb118bffe03f6adc10e8f` |
| Розпакований target | `/tmp/opencode/rea-nvidia-uvm/nvidia-uvm.ko`, SHA-256 `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6`, ELF x86_64 relocatable, not stripped |
| Tool | REA `execute_rizin_command`, Rizin; provider version не підтверджено |
| Команди | `is~<prefix>`, `ir~nvUvmInterface*`, `pd N @ addr` (вузькі вікна близько викликів) |
| Bundle | `evidence/rea-20261128/evidence-p1-uvm-callers.json`, 35 record, SHA-256 `873513252f36e602190f0b0e73129ce8dd3310e1ccbee1359b6d2bdb692db33b` |

Ghidra full analysis не запускався: REA auto-route для ELF обрав Ghidra 12.2,
але зовнішній Rizin-виклик вимагає явного `close_binary`; сесію закрито без
snapshot і без edits. Усі адреси нижче — provider-normalized VA з `is`/`pd`.
Адреси в таблицях — це **інструкція `call`**; відповідний запис `ir` вказує
relocation offset на один байт далі (наприклад `call @ 0x0802d6c6` ↔
`R_X86_64_PLT32 @ 0x0802d6c7`). Bundle містить 35 retention-record загалом,
з них 8 — для цього `nvidia-uvm.ko`; решта — попереднє `nvidia.ko`-розслідування.
Порожні `axt`/`/r` не використовувались як absence-proof.

## 2. Карта A — хто викликає `nvUvmInterfaceMemory*`

| Інтерфейс | Call-site (VA) | Enclosing function, адреса, розмір | `statically proven` аргументи з вікна | Evidence |
|---|---|---|---|---|
| `MemoryAllocFB` | `0x0802d6c6` | `uvm_rm_mem_alloc`, `0x0802d5f0`, 737 B | `rdi = [rbp+0x1908]` (RM object), `rsi = r12`, `rdx = &rsp+8`, `rcx = &rsp+0x10`; перед тим `__uvm_kvmalloc_zero(0x850, 0xd0, "uvm_rm_mem.c", "uvm_rm_mem_alloc")` | `ev_72302848aac15c30c723f708b7e4e7caf59a7ca5c111a1338df15ae048fa4a96`, `ev_4a8915805f736e39b67a6136e93efef0a02133e2585f8131701e723985b688a2` |
| `MemoryAllocSys` | `0x0802d78e` і `0x0802d7d5` | `uvm_rm_mem_alloc`, `0x0802d5f0` | той самий argv; після першого виклику перевірка `eax == 0x51`, `r12 > 0xffff`, потім повтор із `qword [rsp+0x18] = 0` | `ev_4a8915805f736e39b67a6136e93efef0a02133e2585f8131701e723985b688a2` |
| `MemoryCpuMap` | `0x0802d16d` | `rm_mem_map_gpu_proxy`, `0x0802cc80`, 541 B | `rdi = [rbx+0x1908]`, `rsi = [r9+gpu_idx*8+0x30]`, `rdx = [r9+0x848]`, `rcx = &rsp+0x18`, `r8d = 0`; після успіху `[r9+0x30] = [rsp+0x18]` і `bts [r9+8], 0` | `ev_4a8915805f736e39b67a6136e93efef0a02133e2585f8131701e723985b688a2`, `ev_0e70e6548ceb67936cab01f22791bdc5f29a99bc6d27a2e99928b75c5a35cf8f` |
| `MemoryCpuUnMap` | `0x0802d29b` | `uvm_rm_mem_unmap_cpu`, `0x0802d260`, 95 B | `rdi = [[rdi+0x840]+0x1908]`, `rsi = [rdi+0x30]`, `rdx = &[rdi+8]`; потім `btr [rdx], 0`, `[rax+0x30] = 0` | `ev_4a8915805f736e39b67a6136e93efef0a02133e2585f8131701e723985b688a2`, `ev_d997f9af7e2f12d7a6390a437f6e4a2e8ff93bdbdc6501688b14b54d0fda1932` |
| `MemoryFree` | `0x0802cb9e` | `rm_mem_unmap_gpu`, `0x0802cae0`, 332 B | `rdi = [rbx+0x1908]`, `rsi = [rax*8+0x30]`, після виклику `btr [r12], gpu_idx`;iterator `gpu_idx < 0x101` | `ev_4a8915805f736e39b67a6136e93efef0a02133e2585f8131701e723985b688a2`, `ev_0e70e6548ceb67936cab01f22791bdc5f29a99bc6d27a2e99928b75c5a35cf8f` |

Усі п'ять interfacial call-site є **statically proven** за relocation +
disassembly. `0x101` (257) як межа індесу GPU і `0x1908` як offset RM-object
у структурі — факти інструкцій, а не доведена назва поля.

## 3. Карта B — хто викликає `nvUvmInterface*Channel*`

| Інтерфейс | Call-site | Enclosing function | `statically proven` факти | Evidence |
|---|---|---|---|---|
| `ChannelAllocate` | `0x08035a20` | `channel_pool_add`, `0x080355c0`, 4005 B | гілка `cmp edi, 0x10`; `rdi = [rsi+rax]`, `rsi = &rsp+0x30`; після виклику перевірка статусу | `ev_b7379a9859e9ebcc3785d87aeb006498f1056510b8d2da6270de5e3eb941948f`, `ev_489336181b7e63041d433c25c8562dfdf64327cc0144008df0843f217c294b3e` |
| `PagingChannelAllocate` | `0x08035e7d` | `channel_pool_add`, `0x080355c0` | `eax = 0x1e0` перед викликом, `rsi = &rsp+0x30`; після — перевірка статусу | `ev_b7379a9859e9ebcc3785d87aeb006498f1056510b8d2da6270de5e3eb941948f`, `ev_489336181b7e63041d433c25c8562dfdf64327cc0144008df0843f217c294b3e` |
| `PagingChannelsMap` | `0x0802cd79` | `rm_mem_map_gpu_proxy`, `0x0802cc80` | виклик у тому ж шляху, що й `MemoryCpuMap`; статус зберігається в `r11d` | `ev_b7379a9859e9ebcc3785d87aeb006498f1056510b8d2da6270de5e3eb941948f`, `ev_4a8915805f736e39b67a6136e93efef0a02133e2585f8131701e723985b688a2` |
| `PagingChannelsUnmap` | `0x0802cb6a` | `rm_mem_unmap_gpu`, `0x0802cae0` | `rdi = [rdx+0x1908]`, `rdx = [rax+0x1e0]`; потім `MemoryFree` | `ev_b7379a9859e9ebcc3785d87aeb006498f1056510b8d2da6270de5e3eb941948f`, `ev_489336181b7e63041d433c25c8562dfdf64327cc0144008df0843f217c294b3e` |
| `PagingChannelPushStream` | `0x08034007` | `uvm_channel_end_push`, `0x080338e0`, 3454 B | `rdi = [rax+0x130]`; виклик наприкінці push path | `ev_b7379a9859e9ebcc3785d87aeb006498f1056510b8d2da6270de5e3eb941948f`, `ev_bbd5346c854ac816ae62233360674de748af4393f30d2d0cbb562cccb9fe81a3` |
| `PagingChannelDestroy` | `0x080319d0` | `channel_destroy`, `0x08031920`, 381 B | `rdi = [rbx+0x130]`; поруч із `uvm_gpu_tracking_semaphore_free` | `ev_b7379a9859e9ebcc3785d87aeb006498f1056510b8d2da6270de5e3eb941948f`, `ev_489336181b7e63041d433c25c8562dfdf64327cc0144008df0843f217c294b3e` |

Додаткові приватні helper-и, знайдені в межах цієї ж адресної області:

- `set_gpfifo_via_sec2`, `0x0802de40`, 435 B: `uvm_push_get_single_inline_buffer`
  з аргументами `0x10`/`0x10`, `push_reserve_auth_tag`, непрямий виклик через
  `[rax+0x220]→[0x68]`, далі `uvm_conf_computing_cpu_encrypt(..., r8d=0x10)`.
- `do_semaphore_release`, `0x0802dc20`, 59 B: перевірка `dword [rcx+0x28] == 4`,
  потім непрямий callback через `[rax+0x228]→[0x10]` або `[rax+0x248]→[0x10]`.

Це **statically proven** інструкції та виклики; призначення callback-ів
та зв'язок із notifier/fence — **UNPROVEN**.

## 4. Що це змінює і чого не змінює

| Твердження | Статус |
|---|---|
| `nvUvmInterface*` мають реальні call-site у shipped `nvidia-uvm.ko` | `statically proven` (було `UNPROVEN` у `docs/23`) |
| Меморіальний шлях `alloc → cpu_map / paging_map → unmap → free` існує як код | `statically proven` |
| Channel lifecycle `allocate → push → destroy` існує як код | `statically proven` |
| `kchannelBindToRunlist_IMPL`, `MAP_MEMORY_DMA`, `CTRL_GPFIFO_*` — call-site | `string-only`, без змін |
| Який саме RM class/heap обрано для `memType=8` | `UNPROVEN` |
| `CHANNEL_RUNLIST_CORRELATED`, notifier index, fence lifecycle, BOOT0 | `UNPROVEN` |
| Причина NVK/NVIDIA performance gap | `UNPROVEN`; ця карта не є causal proof |

Рядок `nvidia-uvm/uvm_rm_mem.c` у disassembly — **string-only** шлях вихідного
файлу з бінарника; жодного vendor source чи скопійованого коду не використано.

## 5. Наступний найменший крок

1. Для `uvm_rm_mem_alloc` — обмежене disassembly тіла 737 B, щоб виділити
   enum в `esi`, `rdx` (розмір) і перевірку `0x51` як статус; без припущень про
   RM class.
2. Для `channel_pool_add` — вузьке вікно коло `0x08035e73` (`eax=0x1e0`), щоб
   з'ясувати, чи це розмір/тип каналу, і лише тоді формулювати гіпотезу.
3. Порівняти з `docs/02` runtime chain як **дві незалежні observability**;
   не оголошувати, що Vulkan `memType=8` проходить саме цим шляхом.

Не робилось: MMIO/BAR read/write, `nva`, RM-запити, reboot, GPU compute,
PR #21 executable, Ghidra-pseudocode, vendor source, transfer коду, release/tag,
зміни pin-ів/SENS/CML/`wsm-os-lisp`/ADR/target contract.

## Ukrainian one-liner

У `nvidia-uvm.ko` знайдено конкретні call-site всіх п'яти memory- і шести
channel-інтерфейсів: зв'язок UVM↔RM тепер statically proven на рівні функцій,
але runlist, notifier, RM class і причина NVK-різниці лишаються UNPROVEN.
