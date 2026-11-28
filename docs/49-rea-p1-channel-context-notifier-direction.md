# 49 — REA P1: напрямок channel / context / notifier

Продовження [`docs/07`](07-next-research-direction.md) §E2–E4 і
[`docs/40`](40-rea-p1-gpu-info-uuid-direction.md). UUID-гілка закрита: UUID
**йде в** `nvUvmInterfaceGetGpuInfo`, а не виходить із нього. `docs/07` називає
наступним кроком channel/context/notifier через публічні `NV_ESC_RM_ALLOC` /
`NV_ESC_RM_CONTROL`.

Це **не** runtime-звіт і **не** нова гіпотеза. Це source audit уже наявних у
репозиторії артефактів: що саме про channel/context/notifier **видно** в
shipped `nvidia.ko` / `nvidia-uvm.ko` та їхніх капчурах, а що в цих артефактах
**відсутнє**. GPU не використовувався, MMIO не читався, RM-запитів не було.
Твердження нижче не підвищують жодного попереднього статусу.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | docs/23 (function-level карта channel-обгорток), docs/25 (`channel_pool_add` → `nvUvmInterfaceChannelAllocate`), docs/27–28 (`uvm_channel_manager_create`), docs/15/19 (рядковий інвентар) | не повторювати |
| `PARTIAL` | docs/15: `NONSTALL_EVENT_SUBSCRIPTION_OBSERVED`, `CHANNEL_RUNLIST_CORRELATED` — `UNPROVEN`; docs/24 §3: рядки не мають доведеного call-site | цей звіт уточнює, що саме є, а що ні |
| `UPSTREAM_EXISTS` | Nouveau/NVKM/NVK channel, TSG, runlist, GPFIFO | implementation authority, не замінює shipped-доказ |
| `UNIQUE_GAP` | ідентичність слота, у який `uvm_channel_manager_create` пише `+0x19f8`; межа тіла `_nv046796rm`; наявність/відсутність OS-event і notifier-шляху в наявному корпусі evidence | цей звіт |
| `UNPROVEN` | RM class id для channel/context, значення notifier-індексу, будь-який runtime-шлях на H170 | лишається відкритим |

Примітка про нумерацію: файл `docs/42-local-toolchain-and-remaining-targets.md`
уже існує, тому номер `42` тепер мають два документи. Перейменування —
рішення власника; тут нічого не перейменовано й не переміщено.

Pin-и v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract, ABI-pin і
asm-first контракт не змінено.

## 1. Артефакти, інструменти, мапа адрес

| Артефакт | SHA-256 |
|---|---|
| `nvidia.ko` (розпакований, R580 `580.196.11`) | `95c5fa5ab0546ee40842cda2ec20ea3ec1e196a5afee1580944ecae2ffc75bbe` |
| `nvidia-uvm.ko` (розпакований, R580 `580.196.11`) | `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` |

Парування версії модулів із пакетом — [`evidence/driver-pairing-20261128/artifact-pairing.txt`](../evidence/driver-pairing-20261128/artifact-pairing.txt)
(`nvidia-kernel-dkms 580.196.11-1`, `dkms status ... installed`).

Інструменти: REA `execute_rizin_command` (`rizin 0.9.1`, provider version
`null`), `pahole 1.32` для `.BTF`, GNU `readelf`/`objdump`
(`2.47.50.20261021`). Бази Rizin — як у [`docs/40`](40-rea-p1-gpu-info-uuid-direction.md)
§1: `nvidia.ko` = `0x080028e0 + ELF vaddr`, `nvidia-uvm.ko` =
`0x08004660 + ELF vaddr`. Усі адреси нижче — Rizin VA.

Evidence-бандли цього аудиту (усі вже в репозиторії, нових капчур не робилося):

| Бандл | SHA-256 |
|---|---|
| [`evidence/rea-20261128/evidence-p1-add-gpu-call-sites.json`](../evidence/rea-20261128/evidence-p1-add-gpu-call-sites.json) | `b0c22ecfe0c05b0e918e7c16d8a6a4c7fd7ea6895476f91e83db6db1229b5dec` |
| [`evidence/rea-20261128/evidence-p1-function-maps.json`](../evidence/rea-20261128/evidence-p1-function-maps.json) | `b329b2b50d5adf755d5e561024cdfb5d63dedd33676579f3fccf93201a4d4e94` |
| [`evidence/rea-20261128/evidence-p1-dispatch-window.json`](../evidence/rea-20261128/evidence-p1-dispatch-window.json) | `a3286bdaa943704724592001da9341552c369918f554abebaf72f7ce20cf46c2` |
| [`evidence/rea-20261128/evidence-p1-uvm-manager-callers.json`](../evidence/rea-20261128/evidence-p1-uvm-manager-callers.json) | `04c47973feb8f4d7ee45cfd036bc0366a5c2ea04486114565be88d7f22678cdb` |
| [`evidence/rea-20261127/evidence-notification-boot0-raw.json`](../evidence/rea-20261127/evidence-notification-boot0-raw.json) | `c799a98f10207ad83c4cd1b44aa2066303ae140f89956e25bce3e4e1ec70ee09` |
| [`evidence/rea-20261127/evidence-boot0-and-key-strings.json`](../evidence/rea-20261127/evidence-boot0-and-key-strings.json) | `83ea4b64d809f4f496c7f830150a78a2623b69ebb38519f449c192bebe6c446f` |
| [`evidence/rea-20261127/evidence-nvidia-ko-memory-controls.json`](../evidence/rea-20261127/evidence-nvidia-ko-memory-controls.json) | `970c7a92883c6b32599e338885d925da7bd0fcb011655d03bdcb7995dd5ab38c` |
| [`evidence/rea-20261128/btf-uvm-type-layout.txt`](../evidence/rea-20261128/btf-uvm-type-layout.txt) | `b305ddcf413cdf60c7675364dfde3b7c6c18d7231ee37b20ccfef5fe90008e51` |

## 2. Новий `statically proven` факт: `+0x19f8` — це `gpu->channel_manager`

`docs/27` і `docs/28` довели, що всі п'ять call-site `uvm_channel_manager_create`
передають `rdi = parent` і `rsi = &parent+0x19f8`, і що функція виділяє
`0x890`-байтовий об'єкт. Об'єкт за `parent` там лишався неназваним.

BTF-розкладка shipped `nvidia-uvm.ko`
([`evidence/rea-20261128/btf-uvm-type-layout.txt`](../evidence/rea-20261128/btf-uvm-type-layout.txt),
`pahole -C uvm_gpu_struct`) закриває це числом:

```text
uvm_gpu_semaphore_pool_t * semaphore_pool;        /*  6632 */
uvm_gpu_semaphore_pool_t * secure_semaphore_pool; /*  6640 */
uvm_channel_manager_t *    channel_manager;       /*  6648 */   == 0x19F8
```

- `6648 = 0x19F8` точно збігається зі зсувом, який усі п'ять call-site
  передають як output-вказівник. Отже «parent» у docs/27–28 — це `uvm_gpu_t`,
  а слот — поле `channel_manager`.
- `sizeof(uvm_channel_manager_struct) = 2192 = 0x890` у тому ж файлі збігається
  з розміром об'єкта, який `uvm_channel_manager_create` виділяє (docs/27).
  Два незалежні артефакти дають одну пару «об'єкт ↔ тип».

**Статус: `statically proven`** (BTF layout + вікно аргументів). Це
ідентифікація слота, **не** доказ, що запис відбувається в нашому runtime-прогоні.

Поля `uvm_channel_manager_struct`, які стають адресними точками для
наступного кроку (той самий файл):

| Зсув | Поле |
|---:|---|
| `+0x00` | `uvm_gpu_t * gpu` |
| `+0x08` | `uvm_pushbuffer_t * pushbuffer` |
| `+0x10` | `uvm_channel_pool_t * channel_pools` |
| `+0x18` | `unsigned int num_channel_pools` |
| `+0x28` | `pool_to_use` (`default_for_type[8]`, `gpu_to_gpu[256]`) |
| `+0x868` | `procfs.channels_dir` |
| `+0x878` | `conf.num_gpfifo_entries` |
| `+0x87c` | `conf.gpfifo_loc` |
| `+0x880` | `conf.gpput_loc` |
| `+0x884` | `conf.pushbuffer_loc` |

Тобто **розмір GPFIFO і локація pushbuffer — поля channel-менеджера**, а не
RM-об'єкта. Формат записів GPFIFO з цього не випливає й лишається `UNPROVEN`.

## 3. Channel-алокація: ланцюг доведено до перших 192 байтів RM-ядра

Ланцюг (усі ланки `statically proven`, вікна — у
[`evidence/rea-20261128/evidence-p1-add-gpu-call-sites.json`](../evidence/rea-20261128/evidence-p1-add-gpu-call-sites.json)):

| Ланка | Адреса, розмір | Що видно | Evidence |
|---|---|---|---|
| `nvUvmInterfaceChannelAllocate` | `0x08020560`, 200 B | не-altstack гілка: `rdi=0`, далі tail-jump у `rm_gpu_ops_channel_allocate` | `ev_8dfb7557c91ed0fbe32435b247cee0d9c05d3e177825163d50465b0c9ee378d0` |
| `rm_gpu_ops_channel_allocate` | `0x08da2b90`, 100 B | зсуває argv на 1, читає `qword [rbx+0x08]` до і після виклику, викликає `_nv046796rm` | той самий |
| `_nv046796rm` | `0x080df240`, **5147 B** | захоплено `pd 45` = перші 192 байти (≈3.7 %) | `ev_d17f288aafe7e45dfb3430f930316d5139c47fb88c7746ee64b1f532a4d843a1` |
| `nvUvmInterfaceChannelDestroy` | `0x08021c70`, 94 B | → `rm_gpu_ops_channel_destroy` `0x08da2c00` (92 B) → `_nv046797rm` `0x080ded60` | `ev_7fe9462c3eb725ce4bf5ba4208057adaca5f83c53a7beca43ae405c41a957030` |

У захопленому вікні `_nv046796rm` видно рівно дві речі, які варто зафіксувати:

1. **Гейт на чотири ненульові аргументи** (`test rdi/rdx/rsi/rcx`) і далі
   `eax = dword [rdi+0x10]`; `sub eax, 2`; якщо `eax-2 > 1` — перехід на
   `0x80df7f8`. Тобто значення поля `+0x10` вхідного об'єкта мусить бути
   `2` або `3`, інакше гілка відмови.
2. `_nv049654rm` і `_nv054249rm(1)` — той самий диспетчер із кроком `0xe8`,
   що й у memory-шляху (docs/24 §2.1). Індекс `1` статично доведений; **що**
   лежить у записі `1` таблиці — `UNPROVEN`.

**Сенс `+0x10 ∈ {2,3}` — `UNPROVEN`.** Це може бути тип engine/пулу або
лічильник; у наявному корпусі evidence немає жодного запису, який би це
вирішив. Не підвищую до «engine type».

Paging-варіант окремо (`statically proven`, той самий бандл):

- `nvUvmInterfacePagingChannelAllocate` `0x08022510` (393 B) →
  `rm_gpu_ops_paging_channel_allocate` `0x08da3a50`; **при `eax==0`** пише `0`
  у `qword [[r12]+0x18]`, де `r12` — третій аргумент;
- `nvUvmInterfacePagingChannelPushStream` `0x0801f490` (29 B) читає
  `qword [rdi+0x18]` і передає його першим аргументом у
  `rm_gpu_ops_paging_channel_push_stream` `0x08da3bf0` → `_nv046854rm`
  `0x080e6980`.

Те, що обидві функції торкаються `+0x18`, робить «той самий об'єкт» правдоподібним,
але **не доведеним**: у alloc базою є `[[третій аргумент]]`, у push — сам
`rdi`. Тотожність цих двох об'єктів — `interpretation`, не факт.

## 4. Context: у наявному корпусі немає жодного context-об'єкта

Що є:

- BTF `uvm_gpu_struct`: `max_subcontexts` `+6400`, `rm_address_space` `+6408`,
  `address_space_tree` `+6416` —
  [`evidence/rea-20261128/btf-uvm-type-layout.txt`](../evidence/rea-20261128/btf-uvm-type-layout.txt);
- RM-рядки `.rodata` у `nvidia.ko`: `kchannelSetEngineContextMemDesc_IMPL`
  (`0x05cbfcd0`), `channelCommitEngineContext_GM107` (`0x05cc5d30`),
  `dispchnUnbindCtxFromAllChannels_IMPL` (`0x05cb78b0`) —
  [`evidence/rea-20261127/evidence-boot0-and-key-strings.json`](../evidence/rea-20261127/evidence-boot0-and-key-strings.json),
  `ev_b5545ae0ecf22b594c27dbeab6552723831f5181203db44f5978759811766245`.

Чого немає:

- жодного рядка `ALLOC_CONTEXT_DMA`, `CONTEXT_DMA` або `ALLOC_CTX` у
  захоплених рядкових інвентарях — **`coverage limitation`**, не доказ
  відсутності (§6);
- жодного BTF-типу `uvm_*context*` — але `.BTF` у цьому корпусі знято лише
  для чотирьох структур (`uvm_global`, `uvm_parent_gpu`, `uvm_gpu`,
  `uvm_channel_manager`), тому це теж не absence-proof;
- жодного `NV_ESC_RM_ALLOC` із context-class у власних зондах: у
  `pascal/nv_rm.pas` визначено рівно три класи — `NV01_ROOT_CLIENT = 0x41`,
  `NV01_DEVICE_0 = 0x80`, `NV20_SUBDEVICE_0 = 0x2080`.

**Статус `CONTEXT_ALLOC_OBSERVED`: `UNPROVEN`.** Єдине «context»-подібне, що
видно, — `max_subcontexts` як поле GPU і `*EngineContext*` як RM-імена.
Ототожнювати `max_subcontexts` з RM-context-об'єктом не можна.

## 5. Notifier: імена є, прив'язки немає

Рядки `.rodata` у `nvidia.ko` (`izz~event`, `izz~GPFIFO`, `izz~SEMAPHORE`,
`izz~NOTIFIER`; бандли
[`evidence/rea-20261127/evidence-notification-boot0-raw.json`](../evidence/rea-20261127/evidence-notification-boot0-raw.json)
і [`evidence/rea-20261127/evidence-nvidia-ko-memory-controls.json`](../evidence/rea-20261127/evidence-nvidia-ko-memory-controls.json)):

| Рядок | Адреса | Evidence |
|---|---|---|
| `SUBDEV_EVENT_SET_NOTIFICATION` | `0x05d5d19e` | `ev_d36768e4a4a98a27a6638ca60434638b077530d663132287c17e60148b418280` |
| `REGISTER_VIRTUAL_EVENT_BUFFER` | `0x05d5d79f` | `ev_8cd0cb7618e77bb4918fbd05bf54100b3890133f996c4ef00adf794456177a05` |
| `CTRL_EVENT_BUFFER_UPDATE_GET` | `0x05d5d7bd` | `ev_d29360c7c00aa0da5291a932c654cc4084837bcc49ef299ebda8db88a29279c3` |
| `CTRL_GPFIFO_SCHEDULE` | `0x05d5d337` | `ev_b3a61f9e016151ce215097d356f42cd93c3456636762a256eb393e85dd20df31` |
| `CTRL_GPFIFO_GET_WORK_SUBMIT_TOKEN` | `0x05d5e3e8` | той самий |
| `CTRL_GPFIFO_SET_WORK_SUBMIT_TOKEN_NOTIF_INDEX` | `0x05d5e410` | той самий |
| `SEMAPHORE_SCHEDULE_CALLBACK` | `0x05d5dc03` | `ev_24a1c411f1a0e7dece9389cba86f217639cf34753a71c46ccbf1ee54fdbd9fe8` |
| `TIMED_SEMAPHORE_RELEASE` | `0x05d5dc97` | той самий |
| `ECC_NOTIFIER_WRITE_ACK` | `0x05d5d9e9` | `ev_2f1b67caa3407e32e868c1726b6ec769fce262c20b0469fd1a5a1ca7e1b06ee1` |
| `RMProcessNonStallIntrInLocklessIsr` (×2) | `0x05e74938`, `0x05e74eb8` | `ev_73b123ff8190530cfb4cf9a3d832c8da9aa3268cbca46524bf2ac3106b87d5fa` |

Символьна таблиця `nvidia.ko` дає **іншу** картину, ніж рядки:

- `is~notify` повертає лише ACPI/DRM-notifier-и: `nv_acpi_notify_event`,
  `nv_install_notifier`, `nv_uninstall_notifier.part.0`,
  `rm_request_dnotifier_state`, `rm_acpi_notify` —
  `ev_175d63f7068176551e673e62d7f93cbc0b8dcee871d8ec1bdff69ade089e026e`;
- `is~notifier` і `is~GPFIFO` у таблиці символів нічого GPU-подієвого не дають:
  `ev_9ba627a62286b27b05766bcf9bded599f4395ee5d55455bf99fde1eb5e87630b`;
- event-інфраструктура ядра модуля є: `nv_get_event` `0x08008340` (272 B),
  `nv_post_event`, `nv_uvm_event_interrupt` `0x08022c80` (46 B),
  `g_pNvUvmEvents` `0x08eb1a48`, `g_pNvUvmEventsLock` `0x08eb1a30`,
  `rm_init_event_locks` / `rm_destroy_event_locks` —
  `ev_41ba59bdb7d209ea361591e08fb50023938299f69ad0348f0d83e2530f3a1d86`;
- `os_alloc_semaphore` `0x08018cc0` (134 B) є, але **жодного**
  `os_alloc_os_event` / `nv_alloc_os_event` у захоплених символьних вибірках
  немає, і в усьому корпусі evidence немає жодного запису з
  `NV_ESC_ALLOC_OS_EVENT` (`nr 206`) або `ALLOC_OS_EVENT`.

Отже: **нотифікаційний шлях RM у shipped-артефактах видно як набір імен, і
тільки.** Прив'язка `SUBDEV_EVENT_SET_NOTIFICATION` / `REGISTER_VIRTUAL_EVENT_BUFFER`
до конкретного тіла коду, до індексу notifier-а і до fd події ОС —
`UNPROVEN`. `NONSTALL_EVENT_SUBSCRIPTION_OBSERVED` лишається `UNPROVEN`
(без змін від docs/15).

## 6. Аудит методу: чому «не знайдено» тут не означає «немає»

Це головне методологічне уточнення, і воно змінює вагу кількох негативних
результатів у docs/15.

1. **Однаковий пошук, різний результат.** `izz~kchannelBindToRunlist_IMPL`
   без префікса `e search.str.max_region_size=0x10000000` повернув порожньо
   (`ev_972ec967ca1d71c356efe4ef3ecedcfa19f98e47793b84be911045b01b5ee983`),
   а той самий набір шаблонів із префіксом знайшов усі чотири рядки
   (`ev_cc1bb8a59a60d5c28de2c0a84cf18619468ce7d46da871386f0ce680e0d38e7f`:
   `kchannelBindToRunlist_IMPL`, `CTRL_GPFIFO_SET_WORK_SUBMIT_TOKEN_NOTIF_INDEX`,
   `MAP_MEMORY_DMA`, `UNMAP_MEMORY_DMA`). Порожній результат — артефакт
   відсутнього ключа, не відсутність рядка.
2. **Ключ не знімає попередження.** Навіть у записі, який повернув чотири
   рядки, `stderr` містить три `bin_file_strings: search interval size ...
   exceeds max region size (0xa00000), skipping it` (інтервали `0xea7dda`,
   `0x4ef2792`, `0xe5ef60`). Тобто рядкове покриття модуля лишається
   **частковим** у всіх наявних записах, попри ключ.
3. **Регістр має значення.** `izz~NON_STALL` порожній
   (`ev_0d2a1438bb23d2befa7cf0c1dc429bde0da8edf9f0726f87bf3567ed9ea3c06f`),
   а `izz~nonstall` знаходить два `RMProcessNonStallIntrInLocklessIsr`
   (`ev_73b123ff…`). Рядок `NON_STALL` у файлі не існує — це збіг шаблону,
   а не властивість артефакта.

**Наслідок для статусів:** усі «порожні» рядкові/символьні результати цього
корпусу (включно з `izz~boot0`, `izz~NOTIFIER`, `is~GPFIFO`, `is~notifier`)
слід читати як `coverage limitation`. Вони **не** доводять відсутності
notifier-шляху, але й не дають права його припускати.

## 7. Runtime: єдиний channel-witness у репозиторії — Nouveau, не RM

У корпусі є рівно один runtime-слід виділення каналу, і він належить
**відкритому** стеку:

```text
ioctl(3, DRM_IOCTL_NOUVEAU_CHANNEL_ALLOC, 0x7ffde0a1bd30) = 0
ioctl(3, DRM_IOCTL_NOUVEAU_CHANNEL_FREE,  0x7ffde0a1be8c) = 0
ioctl(7, DRM_IOCTL_NOUVEAU_CHANNEL_ALLOC, 0x7ffde0a1dc90) = 0
```

— [`evidence/nouveau-20261127/10-ioctl.txt`](../evidence/nouveau-20261127/10-ioctl.txt)
(strace Vulkan-процесу, три `CHANNEL_ALLOC` з `= 0`). У тому ж трейсі немає
жодного `NOUVEAU_NOTIFIER_*`/`NOUVEAU_EVENT_*` виклику — notifier навіть на
відкритому стеку не спостережений.

Це доводить лише те, що канал **можна** виділити на цій машині через
DRM/Nouveau. До пропрієтарного RM-шляху (`NV_ESC_RM_ALLOC`, `NV_ESC_RM_CONTROL`,
`NV_ESC_ALLOC_OS_EVENT`) це не має відношення й **не** є доказом для R580.

## 8. Відкрите читання: `rdi = 0` і `[rdi+0x08]`

Усі `rm_gpu_ops_*`-обгортки в захоплених вікнах мають однакову форму: обгортка
`nvUvmInterface*` робить `xor edi, edi` і tail-jump, а тіло одразу виконує
`mov rbx, rdi` → `mov rax, qword [rbx+0x08]`. За буквального читання `rdi = 0`
дало б `[0x08]`. Це суперечність між двома вікнами, і **жоден наявний запис її
не вирішує**:

- (а) у altstack-гілці обгортка виділяє `nvidia_stack_t` (`nvidia_stack_t_cache`,
  `0xcc0` байтів) і, найімовірніше, передає його як `rdi`; тоді `[rbx+0x08]`
  — поле стека, а `cmp [rbx+0x08], rbp` до/після виклику є перевіркою
  балансу стека. Вікно обривається на `test rax, rax` (`0x080205b9`), тому
  самого `mov rdi, rax` **не видно**;
- (б) `rdi = 0` — реальний sentinel, а `[rbx+0x08]` читається лише на шляху,
  який у цих вікнах не зустрівся.

`docs/23` описує `[rbx+8]` як «RM-об'єкт». Цей звіт **не** скасовує того
читання, але фіксує, що воно не єдине: **`statically proven`** тут лише самі
інструкції, а семантика `rdi` і `[rbx+0x08]` — `UNPROVEN`.

## 9. Статуси й межі

| Твердження | Статус |
|---|---|
| `uvm_gpu_struct.channel_manager` на `+0x19f8` (6648); `sizeof(uvm_channel_manager_struct)=0x890` | **`statically proven`** (BTF) |
| «parent» у docs/27–28 = `uvm_gpu_t`; output-слот = `gpu->channel_manager` | **`statically proven`** |
| Поля channel-менеджера: `pushbuffer+0x08`, `channel_pools+0x10`, `num_gpfifo_entries+0x878`, `gpfifo_loc+0x87c`, `pushbuffer_loc+0x884` | **`statically proven`** (BTF) |
| Ланцюг `nvUvmInterfaceChannelAllocate → rm_gpu_ops_channel_allocate → _nv046796rm` | **`statically proven`** (docs/23, підтверджено тут) |
| Гейт `dword [rdi+0x10] - 2 <= 1` у `_nv046796rm`; виклик `_nv054249rm(1)` | **`statically proven`** |
| Решта 4955 байтів `_nv046796rm`; сенс `+0x10 ∈ {2,3}`; вміст запису `1` таблиці `0xe8` | **`UNPROVEN`** |
| RM class id / control code для channel і context | **`UNPROVEN`** |
| `ALLOC_CHANNEL_DMA` (`0x05d5cd05`) як шлях саме цього виклику | **`string-only`** + `UNPROVEN` |
| `+0x18` у paging-channel alloc і push — той самий об'єкт | `interpretation`, **`UNPROVEN`** |
| `CONTEXT_ALLOC_OBSERVED` | **`UNPROVEN`** (немає ні об'єкта, ні рядка, ні класу) |
| Наявність notifier/event-імен у `.rodata` `nvidia.ko` | **`statically proven`** |
| Прив'язка цих імен до тіла коду, notifier-індексу, fd події ОС | **`UNPROVEN`** |
| `NONSTALL_EVENT_SUBSCRIPTION_OBSERVED`, `CHANNEL_RUNLIST_CORRELATED` | **`UNPROVEN`** (без змін від docs/15) |
| Runtime channel на цій машині | **`NOT RUN`** для RM; є лише `DRM_IOCTL_NOUVEAU_CHANNEL_ALLOC=0` |
| MMIO/BAR0, DMA/GVA, GR firmware start-up, `NV_PMC_BOOT_0` | **`UNPROVEN` / `NOT RUN`** (без змін) |

## 10. Наступне найменше спостереження й потрібні артефакти

**Unanswered:** який RM class і який control-код використовує `_nv046796rm`
для алокації channel, і чи існує в R580 окремий context-об'єкт понад
`uvm_channel_manager_t`.

**Найменший крок (статичний, без GPU і без RM-запитів):** дочитати решту
`_nv046796rm` (`0x080df240`+`0x00c0`…`0x080df240`+5147) і знайти в ньому
(а) завантаження адреси `.rodata`-рядка як імені методу, (б) числовий class id
у параметрах алокації, (в) місце, де `+0x10` вхідного об'єкта перевіряється.
Далі — резолв запису `1` таблиці з кроком `0xe8` (база `.rodata` `0x08eb77e0`,
docs/24 §2.1) і звірка з рядком `ALLOC_CHANNEL_DMA`.

Які артефакти треба зняти, щоб це стало доказом:

| Артефакт | Навіщо | Чого не вистачає зараз |
|---|---|---|
| `nvidia.ko`, повне тіло `_nv046796rm` + `_nv046797rm` + `_nv046854rm` (адресні вікна, не `/r` на модуль) | class id, method name, поля параметрів | захоплено 192 із 5147 байтів |
| `.rodata`-таблиця `0x08eb77e0`, записи `0`…`n` кроком `0xe8` | чи є це таблицею класів/методів | таблиця не вивантажена |
| `nvidia-uvm.ko` `.BTF` для `uvm_channel_t`, `uvm_channel_pool_t`, `uvm_pushbuffer_t`, `uvm_gpu_semaphore_pool_t` | формат GPFIFO-записів, поля notifier-а | у корпусі лише 4 структури |
| `libcuda`/`libnvidia-*`: call-site `ioctl(fd, 0x1b, …)` = `UVM_REGISTER_CHANNEL` і будь-який виклик для `NV_ESC_ALLOC_OS_EVENT` (`nr 206`) | userspace-бік channel і notifier-fd | у корпусі трасовано лише `0x25` |
| strace реального `cuCtxCreate`/`cuStreamCreate` на H170 (потрібен власник і дозвіл) | послідовність ioctl для context/channel/notifier | **`NOT RUN`**, і це не можна замінити статикою |

Доки цих артефактів немає, жоден рядок вище не можна переносити в
`docs/05` як capability.

## 11. Чого цей звіт свідомо не робить

- Не стверджує жодного runtime-результату: GPU не використовувався.
- Не називає числовий RM class id для channel або context.
- Не підвищує `ALLOC_CHANNEL_DMA`, `SUBDEV_EVENT_SET_NOTIFICATION`,
  `REGISTER_VIRTUAL_EVENT_BUFFER` до «доведеного шляху» — це рядки.
- Не трактує порожні рядкові/символьні результати як доказ відсутності.
- Не змінює `docs/05`, `docs/07`, pin-и, SENS, CML, `wsm-os-lisp`, ADR,
  target contract чи ABI-pin, і не перейменовує наявний `docs/42`.

## Ukrainian one-liner

У shipped-артефактах доведено, що `uvm_channel_manager_create` пише саме в
`uvm_gpu_t.channel_manager` (`+0x19f8`, `sizeof = 0x890`), а channel-алокація
йде ланцюгом `nvUvmInterfaceChannelAllocate → rm_gpu_ops_channel_allocate →
_nv046796rm`, де видно гейт `[rdi+0x10] ∈ {2,3}` і `_nv054249rm(1)`; context
і notifier лишаються набором RM-імен без прив'язки, а RM class id, notifier-індекс
і будь-який runtime-шлях на H170 — `UNPROVEN`.
