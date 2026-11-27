# 23 — REA P1: function-level карти memory/VA та channel/submit (R580)

Це перший звіт після прийняття owner-стратегії: REA перестає бути широким
сканером і працює як інструмент точкового дослідження приватних механізмів
R580. Стратегію прийнято з двома правками: (1) канонічний `master` уже
`9c391dd` (після `b432999` були лише benchmark-харнеси й виміри, жодного
дубля REA); (2) усі висновки function-level з xrefs/Evidence ID і статусом.

## 0. Triage перед завданням

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | GP107 NVKM dispatch (`nv137_chipset`, `gp107_gr`, `gp100_fifo`, MMU/FB), NVK/NAK, Envytools RNND, `nvdisasm` SM61 | не реверсити заново; open source — implementation authority |
| `UPSTREAM_EXISTS` | non-stall event index `0`/runlist ID patch (13.09.2026), тести на GK104/GK107/GK208B | стежити за статусом; не GP107-доказ; не винаходити патч |
| `PARTIAL` | `docs/15`, `docs/19`: string/BTF/symbol inventories | використано як входи, не повторено повний scan |
| `UNIQUE_GAP` | приватні RM/UVM wrapper-и `_nvNNNNrm`, argv-shifting, altstack, method-name tables R580 | ціль цього звіту |

## 1. Тарґет, метод, межі

| Поле | Значення |
|---|---|
| Шипований артефакт | `/lib/modules/7.2.15+kali-amd64/updates/dkms/nvidia.ko.xz`, SHA-256 `f19b0531bf269ebe715790b17173cc3110ebdccf9239f1d397ca034254953062` |
| Розпакований таргет | `/tmp/opencode/rea-nvidia/nvidia.ko`, SHA-256 `95c5fa5ab0546ee40842cda2ec20ea3ec1e196a5afee1580944ecae2ffc75bbe` |
| Інструмент | REA `execute_rizin_command`, Rizin (версія провайдером не підтверджена — `null`), без Ghidra-псевдокоду |
| Операції | `is~` (symbols), `pd N @ addr` (вузька ділянка), `ir~` (relocations як xrefs), `izz~` з `e search.str.max_region_size=0x10000000`, `px`/`ps` |
| Evidence | `evidence/rea-20261128/evidence-p1-function-maps.json`, 21 record, SHA-256 `b329b2b50d5adf755d5e561024cdfb5d63dedd33676579f3fccf93201a4d4e94` |

Повний Ghidra-автоаналіз 138 MB модуля не запускався: два попередні startup
timeouts (330 s і 600 s) лишаються підставою для адресної роботи Rizin.
Адреси нижче — provider-normalized VA з `is`/`pd`; `-` у `ir` означає
relocation addend, не довільний offset. Порожній `axt` без повного аналізу
не є absence-proof.

## 2. Карта A — memory / GPU VA / DMA / BAR1 (8 функцій + dispatched core)

| # | Функція, адреса, розмір | Що statically proven | Evidence |
|---:|---|---|---|
| 1 | `nvUvmInterfaceMemoryAllocFB`, `0x080202c0`, 200 B | `rm_is_altstack_in_use()`; у звичайному шляху tail-jump `rm_gpu_ops_memory_alloc_fb(0, rdi, rsi, rdx, rcx)`; в altstack-шляху `kmem_cache_alloc_noprof(nvidia_stack_t_cache, 0xcc0)` | `ev_e70e09b362e24faadf830800bd49ed1e50bae4be64eede4136587dd62bcaf79e` |
| 2 | `nvUvmInterfaceMemoryAllocSys`, `0x080203a0`, 200 B | та сама схема → `rm_gpu_ops_memory_alloc_sys(0, …)` | `ev_3c6c1645bb3a994b2cd800687b17698cea9e079f591f6bd115bf5806b2608771` |
| 3 | `nvUvmInterfaceMemoryCpuMap`, `0x08020b30`, 234 B | → `rm_gpu_ops_memory_cpu_map(0, rdi, rsi, rdx, rcx, ebx)`; `r9d` бере **нижні 32 біти** `r8` — це statically proven фактування аргументу, не припущення | `ev_3c6c1645bb3a994b2cd800687b17698cea9e079f591f6bd115bf5806b2608771` |
| 4 | `nvUvmInterfaceMemoryFree`, `0x08021a50`, 108 B | `nvUvmGetSafeStack()` → `rm_gpu_ops_memory_free(stack, rdi, rsi)`; потім умовний cleanup stack | `ev_3c6c1645bb3a994b2cd800687b17698cea9e079f591f6bd115bf5806b2608771` |
| 5 | `rm_gpu_ops_memory_alloc_fb`, `0x08da2620`, 100 B | зсуває argv на 1, бере `[rbx+8]` як RM-об'єкт, викликає `_nv046843rm`, перевіряє `[rbx+8]` після виклику, помилка → `nv_printf(4, …)`, повертає `eax` | `ev_27739f73793d386731c02a7a88c345d2d4518d963dadc7af6ed362e7686db10f` |
| 6 | `rm_gpu_ops_memory_alloc_sys`, `0x08da2700`, 100 B | та сама схема → `_nv046844rm` | `ev_27739f73793d386731c02a7a88c345d2d4518d963dadc7af6ed362e7686db10f` |
| 7 | `rm_gpu_ops_memory_cpu_map`, `0x08da29f0`, 108 B | п'ять зсунутих аргументів → `_nv046846rm` | `ev_27739f73793d386731c02a7a88c345d2d4518d963dadc7af6ed362e7686db10f` |
| 8 | `rm_gpu_ops_memory_free`, `0x08da2cd0`, 92 B | два аргументи → `_nv046848rm`; на відміну від alloc, завжди повертає `0` | `ev_27739f73793d386731c02a7a88c345d2d4518d963dadc7af6ed362e7686db10f` |

### Спільний RM-dispatch (не входить у ліміт 8 функцій)

- `_nv046843rm`, `0x080de160`, 118 B: перевіряє `rdi != 0 && rdx != 0`,
  нулює 5×8 байт локального блоку, викликає
  `_nv046834rm(rdi, 0, rsi, rdx, 0, &block)`; при невалідних аргументах
  повертає `0x1f` (31). `ev_a56392531a6332d6802553c8bcf4bc6d041142182ac877aa3e192ee21e89691d`.
- `_nv046834rm`, `0x080d9810`, 436 B: викликає `_nv054249rm(1)`, потім
  `_nv046783rm(obj+8, index, r13, &local, block)`; якщо `[block+0x1c] != 0`,
  додатково `_nv046784rm(...)`; на помилці — непрямий callback через
  `[obj+8]→[0x40]`. `ev_25eb64481f71ef6bb5e9ab67adfe5085d37cbdfc02f5b4ec5bec15d72f3d5bb6`.
  **UNPROVEN**: які саме RM command/class кодуються в `_nv046783rm` /
  `_nv046784rm` — наразі доведено лише самі виклики й форму аргументів.

### Xrefs і межі

- `R_X86_64_PLT32 rm_gpu_ops_memory_alloc_fb@plt` з `0x08020301` (tail-jmp)
  і `0x08020340` (altstack), `__ksymtab` запис на `0x08000220` —
  `ev_8e1cd107c5e95e400107cd6a76924a995b1548dc95879289026d820e2e6b363d`.
- Таблця імен методів за `0x0dd5cc80`: `ALLOC_ROOT`, `ALLOC_DEVICE`,
  `ALLOC_MEMORY`, `ALLOC_CTX_DMA`, `ALLOC_CHANNEL_DMA`, `MAP_MEMORY`,
  `BIND_CTX_DMA`, `ALLOC_OBJECT`, `FREE`, `ALLOC_VIDMEM`, `UNMAP_MEMORY`,
  `MAP_MEMORY_DMA`, `UNMAP_MEMORY_DMA`, `GET_EDID`, `ALLOC_DISP_CHANNEL` —
  `ev_753479f26fb960cac9778632e8ae96bc1b2ff0e0067f8075449ab439c138b747`.
  **statically proven** наявність і сусідство в таблиці; **не доведено**, що
  якийсь із цих методів викликається для нашого workload.
- `nvUvmInterface*` — експортовані символи (`__ksymtab`/`__kstrtab`,
  `ev_74903c09bf8a01e333f3b802fe409bf84691f8144ba9bd43086d9455a5636120`).
  У цьому модулі вхідних xrefs на них немає: споживач — інший shipped-модуль
  (`nvidia-uvm.ko`), тому повний ланцюг caller тут **UNPROVEN**.

## 3. Карта B — channel / context / GPFIFO / notifier / fence (8 функцій)

| # | Функція, адреса, розмір | Що statically proven | Evidence |
|---:|---|---|---|
| 1 | `nvUvmInterfaceChannelAllocate`, `0x08020560`, 200 B | tail-jump `rm_gpu_ops_channel_allocate(0, …)`; altstack через `nvidia_stack_t_cache` | `ev_8dfb7557c91ed0fbe32435b247cee0d9c05d3e177825163d50465b0c9ee378d0` |
| 2 | `rm_gpu_ops_channel_allocate`, `0x08da2b90`, 100 B | argv-zсув, `[rbx+8]` як RM-об'єкт → `_nv046796rm`; returns `eax` | `ev_8dfb7557c91ed0fbe32435b247cee0d9c05d3e177825163d50465b0c9ee378d0` |
| 3 | `_nv046796rm`, `0x080df240`, 5147 B | перший блок: 4 аргументи ненульові; `dword [rdi+0x10] - 2 <= 1` (тобто значення 2 або 3); виклики `_nv049654rm`, `_nv054249rm`. Решта тіла **не розібрана**; смисл поля `+0x10` **UNPROVEN** | `ev_d17f288aafe7e45dfb3430f930316d5139c47fb88c7746ee64b1f532a4d843a1` |
| 4 | `nvUvmInterfacePagingChannelAllocate`, `0x08022510`, 393 B | дві перевірки altstack → `rm_gpu_ops_paging_channel_allocate(0, …)`; при успіху записує `0` у `qword [[rdx]+0x18]`; повертає статус | `ev_7fe9462c3eb725ce4bf5ba4208057adaca5f83c53a7beca43ae405c41a957030` |
| 5 | `nvUvmInterfacePagingChannelsMap`, `0x08020640`, 200 B | tail-jump `rm_gpu_ops_paging_channels_map(0, …)` | `ev_7fe9462c3eb725ce4bf5ba4208057adaca5f83c53a7beca43ae405c41a957030` |
| 6 | `nvUvmInterfacePagingChannelPushStream` `0x0801f490`, 29 B → `rm_gpu_ops_paging_channel_push_stream` `0x08da3bf0` | бере `[rdi+0x18]` як RM ops object, зсуває argv, викликає `_nv046854rm` | `ev_8dfb7557c91ed0fbe32435b247cee0d9c05d3e177825163d50465b0c9ee378d0`, `ev_d17f288aafe7e45dfb3430f930316d5139c47fb88c7746ee64b1f532a4d843a1` |
| 7 | `rm_gpu_ops_channel_destroy`, `0x08da2c00`, 92 B | один зсунутий аргумент → `_nv046797rm`; повертає `0` | `ev_7fe9462c3eb725ce4bf5ba4208057adaca5f83c53a7beca43ae405c41a957030` |
| 8 | `nvUvmInterfacePagingChannelsUnmap`, `0x08022410`, 108 B | `nvUvmGetSafeStack()` → `rm_gpu_ops_paging_channels_unmap(stack, …)` | `ev_7fe9462c3eb725ce4bf5ba4208057adaca5f83c53a7beca43ae405c41a957030` |

### Чому lifecycle runlist/notifier/fence лишається UNPROVEN

- `kchannelBindToRunlist_IMPL` знайдено за `0x0dcbfd40` у таблиці імен
  поруч із `kchannelSetEngineContextMemDesc_IMPL` і
  `kchannelCtrlCmdGpFifoSchedule_IMPL`:
  `ev_cc1bb8a59a60d5c28de2c0a84cf18619468ce7d46da871386f0ce680e0d38e7f`,
  `ev_d9e58a8d10e9a3687b1b73d09e3e4757e1b1cab0166b8ee5618610f72a04f65f`.
  `CTRL_GPFIFO_SET_WORK_SUBMIT_TOKEN_NOTIF_INDEX` за `0x0dd5e410` лежить у
  таблиці `CTRL_*` імен. Це **string-only / statically proven table entry**,
  не виклик і не зв'язок із конкретним каналом.
- У symbol table цього модуля немає ані `runlist`, ані `notifier`-функцій
  (`ev_9ba627a62286b27b05766bcf9bded599f4395ee5d55455bf99fde1eb5e87630b`);
  `axt` на адреси рядків порожній (`ev_e698229946f34171902d436d49604c92a123b78925009c8fee1b3031fa8fd0cf`).
- Пошук `/r` reference перевищив бюджет транспорту MCP (10 MiB,
  `ev_c557f86e8d4e25b45381cb219980fc0677226ca5658c3f3c66146365bb0c4ecc`);
  це **причина відсутності функціонального зв'язку**, не доказ, що зв'язку немає.
- Отже `CHANNEL_RUNLIST_CORRELATED` і призначення notifier index лишаються
  **UNPROVEN/PARTIAL**; non-stall patch відомого upstream lead не є GP107-тестом.

## 4. Статуси й висновки

| Твердження | Статус |
|---|---|
| Адреси, розміри, argv-zсув, виклики, перевірки аргументів, таблиці імен | `statically proven` (`pd`/`is`/`ir`/`px`/`izz`) |
| `kchannelBindToRunlist_IMPL`, `MAP_MEMORY_DMA`, `CTRL_GPFIFO_*` як рядки в таблицях | `string-only` |
| Те, що exported UVM-інтерфейси споживаються поза цим модулем | `interpretation` з `__ksymtab`/`__kstrtab` |
| Вибір RM memory class для `memType=8` / `heap=1` з `docs/22`, CPU↔GPU VA mapping, BAR1 PDE/PTE, notifier/fence lifecycle | `UNPROVEN` |
| Причина NVK/NVIDIA gap | `UNPROVEN`; REA не змінює цей статус |
| `BOOT0` | `UNPROVEN`, без нових спроб; `0x137000A1` — `string-only` з kernel-log |

`memType=8` лишається лише **opaque Vulkan property tuple**
(`HOST_VISIBLE|HOST_COHERENT`), не доведеним фізичним розміщенням і не
RM-класом. Порівняння memory path-ів NVK і R580 потребує окремого runtime
witness або `nvidia-uvm.ko`; з одного пропрієтарного модуля це не виводиться.

## 5. Наступні найменші кроки (без широких сканів)

1. Address-window `pd` для `_nv046783rm` / `_nv046784rm`, щоб ідентифікувати
   RM command/code; тільки після гіпотези про конкретний control.
2. Обмежений reference search для `0x0dcbfd40` з `search.range.from/to`
   у межах `.text`, замість `/r` на весь 138 MB модуль.
3. Окремий target `nvidia-uvm.ko` для caller-ланцюга `nvUvmInterfaceMemory*`;
   не плутати з вже зробленим у `docs/02` runtime trace.
4. Стежити за upstream-статусом non-stall patch; не подавати `Tested-by`.

Не робилось: MMIO read/write, `nva`, RM-запити, reboot, зміни boot/firmware,
PR #21 executable, Ghidra-pseudocode, копіювання vendor source чи коду NVIDIA,
зміни pin-ів/SENS/CML/`wsm-os-lisp`/ADR/target contract. PR #21 лишається
`NOT_RUN`; коміт і пуш цієї документації — окрема звичайна дія проєкту.

## Ukrainian one-liner

R580-обгортки UVM→RM доведено на рівні функцій і аргументів, але ланцюг
runlist→notifier→fence і вибір RM memory class для нашого benchmark лишаються
UNPROVEN: далі треба вузькі вікна disassembly та окремий `nvidia-uvm.ko`, не
черговий `izz~MEMORY`.
