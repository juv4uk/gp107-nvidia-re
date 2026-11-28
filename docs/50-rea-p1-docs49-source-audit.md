# 50 — Аудит `docs/49`: чи випливає кожне твердження з названого артефакту

[`docs/49`](49-rea-p1-channel-context-notifier-direction.md) змержено без
перевірки «твердження ↔ артефакт». Цей документ — та перевірка, зроблена
постфактум. Він **не** переписує `docs/49`: змержений документ виправляють
наступним документом, який каже, що саме змінилося і чому.

Це **не** runtime-звіт і не нова гіпотеза. GPU не використовувався, MMIO не
читався, `ioctl` не викликався, драйвер не завантажувався, RM-запитів не було.
Перевірялися лише артефакти, які вже лежать у репозиторії. Жоден статус
`docs/05` цим документом не змінюється.

Що саме перевірено: `docs/49` робить 38 різних тверджень, кожне з яких
посилається на конкретний `evidence/`-артефакт або на конкретний
`ev_<sha256>`-запис. Для кожного відкрито названий артефакт, і питання було
одне: **чи показує цей артефакт саме те, що сказано** — а не «чи не
суперечить».

## 0. Метод і його межі

- Джерело тверджень: текст `docs/49` (351 рядок), прочитаний повністю;
  нумерація `C01…C38` — цього документа, не `docs/49`.
- Перевірка: JSON-бандли в `evidence/rea-20261127` і `evidence/rea-20261128`,
  `evidence/rea-20261128/btf-uvm-type-layout.txt`,
  `evidence/driver-pairing-20261128/artifact-pairing.txt`,
  `evidence/nouveau-20261127/10-ioctl.txt`, `docs/24`, `docs/27`, `docs/28`,
  `docs/35`, `pascal/nv_rm.pas`, `docs/ioctl-map.md`.
- Читання великих JSON — вибіркове: `json.load`, далі `records[i]
  ['parameters']['command']`, `records[i]['normalized_result']['stdout']`,
  `records[i]['normalized_result']['stderr']`. Розмір корпусу записів: 273
  унікальні `evidence_id` у семи бандлах `evidence/rea-20261127` і `evidence/rea-20261128`; усі 273
  `stdout` вивантажено в робочу теку і далі шукано `grep`-ом за конкретним
  рядком/адресою. Жоден файл не виведено цілком.
- Роздільність `stdout`/`stderr` збережено: порожній `stdout` **не**
  трактується як «рядка немає», якщо в тому ж записі `stderr` містить
  `bin_file_strings: search interval size … skipping it`.
- Адреси — Rizin VA, як у `docs/49`: `nvidia.ko` = `0x080028e0 + ELF vaddr`,
  `nvidia-uvm.ko` = `0x08004660 + ELF vaddr`. Перевірено на трьох незалежних
  символах (`_nv046783rm` ELF `0xd5c80` → `0x080d5c80`; `_nv046796rm` ELF
  `0xdf240` → `0x080df240`; `add_gpu` ELF `0x17ac0` → `0x0801c120`).
- Самих `nvidia.ko` / `nvidia-uvm.ko` у репозиторії **немає** — тільки їхні
  SHA-256 і зняті з них записи. Тому «артефакт» тут завжди означає запис у
  бандлі, а не бінарник. Це межа всього аудиту і причина, чому три знахідки
  нижче — не «дрібні неточності», а помилки, які видно тільки при
  звірянні з записом.
- Вердикти: **supported** (артефакт показує це), **overstated** (артефакт
  показує слабше — сказано, що саме), **unsupported** (артефакт цього не
  показує взагалі), **unverifiable** (артефакту в репозиторії немає).

## 1. Таблиця тверджень і вердиктів

| # | Твердження `docs/49` | Названий артефакт | Вердикт |
|---|---|---|---|
| C01 | `nvidia.ko` = `95c5fa5a…`, `nvidia-uvm.ko` = `81b21527…`; пакет `nvidia-kernel-dkms 580.196.11-1`, `dkms status … installed` | `evidence/driver-pairing-20261128/artifact-pairing.txt` | **supported** — обидва дайджести рядок-у-рядок, обидва `dpkg-query -W` і `dkms status` |
| C02 | SHA-256 восьми evidence-бандлів | самі бандли | **supported** — усі 8 `sha256sum` збігаються |
| C03 | Rizin `0.9.1`, provider version `null`; `pahole 1.32`; binutils `2.47.50.20261021` | бандли + `btf-uvm-type-layout.txt` + `artifact-pairing.txt` | **supported** — `providers[].version = null` у всіх rizin-бандлах; `tool=pahole 1.32` у шапці BTF; `GNU readelf (GNU Binutils for Debian) 2.47.50.20261021` у pairing |
| C04 | Бази Rizin `0x080028e0` / `0x08004660` | `docs/40` §1 + бандли | **supported** — збігається з `add-gpu-call-sites.txt` («`Rizin = 0x08004660 + ELF vaddr`») і з трьома символами |
| C05 | BTF: `channel_manager` @ `6648` = `0x19F8`; `sizeof(uvm_channel_manager_struct) = 2192 = 0x890` | `evidence/rea-20261128/btf-uvm-type-layout.txt` | **supported** — `channel_manager; /* 6648 8 */`, `/* size: 2192 … */` |
| C06 | 10 полів менеджера: `+0x00 gpu`, `+0x08 pushbuffer`, `+0x10 channel_pools`, `+0x18 num_channel_pools`, `+0x28 pool_to_use`, `+0x868 procfs.channels_dir`, `+0x878 num_gpfifo_entries`, `+0x87c gpfifo_loc`, `+0x880 gpput_loc`, `+0x884 pushbuffer_loc` | той самий BTF-файл | **supported** — усі 10 збігаються до байта (40=0x28, 2152=0x868, 2168=0x878, 2172=0x87c, 2176=0x880, 2180=0x884) |
| C07 | Це «**новий** `statically proven` факт»: «об'єкт за `parent` там лишався **неназваним**» (про docs/27–28) | `docs/27`, `docs/28`, `docs/35` | **overstated** — див. §2.1 |
| C08 | П'ять call-site `uvm_channel_manager_create` передають `rdi = parent`, `rsi = &parent+0x19f8` | `docs/28` §3 | **supported** — таблиця з п'яти адрес `0x0801c539`, `0x080bad5a`, `0x080baeba`, `0x080bb1d0`, `0x080bb2d2` |
| C09 | Ланцюг `nvUvmInterfaceChannelAllocate` `0x08020560`/200 B → `rm_gpu_ops_channel_allocate` `0x08da2b90`/100 B → `_nv046796rm` `0x080df240`/**5147 B** | `ev_8dfb7557…`, `ev_d17f288a…` | **supported** — релокації tail-jump, `GLOBAL FUNC 100`, `LOCAL FUNC 5147` |
| C10 | `pd 45` = «перші 192 байти (≈3.7 %)»; решта — 4955 байтів | `ev_d17f288a…` | **supported (наближено)** — вікно закінчується на інструкції `0x080df2ff`, тобто 45 інструкцій = 192–196 байтів; «4955» — оцінка, а не точна арифметика (див. §2.8) |
| C11 | `nvUvmInterfaceChannelDestroy` `0x08021c70`/94 B → `rm_gpu_ops_channel_destroy` `0x08da2c00`/92 B → `_nv046797rm` `0x080ded60` | `ev_7fe9462c…` | **overstated** — названий запис показує тільки хвіст ланцюга (§2.2) |
| C12 | Гейт: `test rdi/rdx/rsi/rcx`, `eax = dword [rdi+0x10]`, `sub eax, 2`, при `> 1` → `0x80df7f8`; отже `+0x10 ∈ {2,3}` | `ev_d17f288a…` | **supported** — `cmp eax, 0x01` / `jnbe 0x80df7f8` (unsigned), тобто `{2,3}` |
| C13 | «`_nv049654rm` і `_nv054249rm(1)` — той самий диспетчер із кроком `0xe8`» | `ev_d17f288a…`, `ev_0eb7e6e6…` | **overstated** — половина про `_nv054249rm(1)` доведена, половина про `_nv049654rm` не показана ніде (§2.3) |
| C14 | `nvUvmInterfacePagingChannelAllocate` `0x08022510`/393 B → `0x08da3a50`; при `eax==0` пише `0` у `qword [[r12]+0x18]`, `r12` — третій аргумент | `ev_7fe9462c…` | **supported** — `mov r12, rdx`; `mov rax, qword [r12]`; `mov qword [rax+0x18], r10` (`r10 = 0`) |
| C15 | `nvUvmInterfacePagingChannelPushStream` `0x0801f490`/29 B читає `qword [rdi+0x18]` → `0x08da3bf0` → `_nv046854rm` `0x080e6980` | `ev_8dfb7557…`, `ev_d17f288a…` | **supported** — обидва записи збігаються |
| C16 | BTF `uvm_gpu_struct`: `max_subcontexts` `+6400`, `rm_address_space` `+6408`, `address_space_tree` `+6416` | `btf-uvm-type-layout.txt` | **supported** — `/* 6400 4 */`, `/* 6408 8 */`, `/* 6416 208 */` |
| C17 | Три `.rodata`-рядки: `kchannelSetEngineContextMemDesc_IMPL` `0x05cbfcd0`, `channelCommitEngineContext_GM107` `0x05cc5d30`, `dispchnUnbindCtxFromAllChannels_IMPL` `0x05cb78b0` | `ev_b5545ae0…` (`izz~channel`) | **supported**, але неповно — у тому ж записі є ще `channelDeleteSubchannelContextEntry_IMPL` `0x05cc5130` (§2.7) |
| C18 | «жодного рядка `ALLOC_CONTEXT_DMA`, `CONTEXT_DMA` або `ALLOC_CTX` у захоплених рядкових інвентарях» | рядкові інвентарі `evidence/rea-20261127` і `evidence/rea-20261128` | **unsupported** — `ALLOC_CTX_DMA` і `BIND_CTX_DMA` лежать у репозиторії (§2.4) |
| C19 | `.BTF` у корпусі знято лише для чотирьох структур | `btf-uvm-type-layout.txt` | **supported** — рівно чотири секції: `uvm_global`, `uvm_parent_gpu`, `uvm_gpu`, `uvm_channel_manager` |
| C20 | `pascal/nv_rm.pas` визначає рівно три класи: `0x41`, `0x80`, `0x2080` | `pascal/nv_rm.pas` | **supported** — рядки 40–42 |
| C21 | Таблиця з 10 notifier/event-рядків з адресами й `ev_`-посиланнями | `ev_d36768e4…`, `ev_8cd0cb76…`, `ev_d29360c7…`, `ev_b3a61f9e…`, `ev_24a1c411…`, `ev_2f1b67ca…`, `ev_73b123ff…` | **supported** — усі 10 адрес збігаються до байта, включно з двома `RMProcessNonStallIntrInLocklessIsr` |
| C22 | `is~notify` повертає «**лише** ACPI/DRM-notifier-и: `nv_acpi_notify_event`, `nv_install_notifier`, `nv_uninstall_notifier.part.0`, `rm_request_dnotifier_state`, `rm_acpi_notify`» | `ev_175d63f7…` | **overstated** — п'ять названих символів є, але запис повертає 15 рядків (§2.5) |
| C23 | `is~notifier` і `is~GPFIFO` не дають нічого GPU-подієвого | `ev_9ba627a6…` | **supported** — 0 рядків `GPFIFO`; усі `notifier`-збіги — ACPI |
| C24 | Event-інфраструктура: `nv_get_event` `0x08008340`/272 B, `nv_post_event`, `nv_uvm_event_interrupt` `0x08022c80`/46 B, `g_pNvUvmEvents` `0x08eb1a48`, `g_pNvUvmEventsLock` `0x08eb1a30`, `rm_init_event_locks`/`rm_destroy_event_locks`, **`os_alloc_semaphore` `0x08018cc0`/134 B** | `ev_41ba59bd…` (`is~event`) | **overstated** — усе, крім `os_alloc_semaphore`, є в названому записі; `os_alloc_semaphore` там немає (§2.6) |
| C25 | Жодного `os_alloc_os_event` / `nv_alloc_os_event` у символьних вибірках і жодного запису з `NV_ESC_ALLOC_OS_EVENT` (`nr 206`) / `ALLOC_OS_EVENT` у корпусі | весь корпус | **supported** — 0 збігів у 273 записах; `docs/ioctl-map.md` рядок 43 дає `206 = NV_ESC_ALLOC_OS_EVENT`, тобто номер узято правильно |
| C26 | `izz~kchannelBindToRunlist_IMPL` без ключа `search.str.max_region_size` порожній, з ключем — чотири рядки | `ev_972ec967…`, `ev_cc1bb8a5…` | **supported** — порожній `stdout` + `ERROR: … Failed to generate interval list`; з ключем — 4 рядки (§2.9 про «той самий набір») |
| C27 | Навіть у записі з чотирма рядками `stderr` має три `bin_file_strings … skipping it` (інтервали `0xea7dda`, `0x4ef2792`, `0xe5ef60`) | `ev_cc1bb8a5…` | **supported** — рівно три різні інтервали (шість рядків: по два на інтервал) |
| C28 | `izz~NON_STALL` порожній, `izz~nonstall` дає два; «рядок `NON_STALL` у файлі **не існує**» | `ev_0d2a1438…`, `ev_73b123ff…` | **overstated** — пара результатів підтверджує чутливість до регістру, але «не існує» — це absence-claim із пошуку, який сам пропустив три регіони (§2.10) |
| C29 | У `10-ioctl.txt` — «**три** `CHANNEL_ALLOC` з `= 0`» (цитата з трьох рядків) | `evidence/nouveau-20261127/10-ioctl.txt` | **unsupported** — у трейсі **чотири** `CHANNEL_ALLOC`, усі `= 0` (§2.11) |
| C30 | У тому ж трейсі немає жодного `NOUVEAU_NOTIFIER_*`/`NOUVEAU_EVENT_*` | той самий файл | **supported** — 0 збігів на 115 рядків |
| C31 | «**Усі** `rm_gpu_ops_*`-обгортки в захоплених вікнах мають однакову форму: `xor edi, edi` + tail-jump, тіло `mov rbx, rdi` → `mov rax, [rbx+0x08]`» | `ev_8dfb7557…`, `ev_7fe9462c…` | **overstated** — `nvUvmInterfacePagingChannelPushStream` має іншу форму (§2.12) |
| C32 | «Вікно обривається на `test rax, rax` (`0x080205b9`), тому самого `mov rdi, rax` **не видно**» | `ev_8dfb7557…` | **unsupported** — `mov rdi, rax` видно, `0x080205b6` (§2.13) |
| C33 | altstack-гілка бере `nvidia_stack_t` з `nvidia_stack_t_cache`, `0xcc0` байтів | `ev_8dfb7557…` | **supported** — `mov esi, 0xcc0 ; 3264` перед `kmem_cache_alloc_noprof` |
| C34 | Єдиний runtime-слід виділення каналу в корпусі належить Nouveau, не RM | `10-ioctl.txt`, `11-drm-ioctl.txt` | **supported** — `DRM_IOCTL_NOUVEAU_CHANNEL_ALLOC` лише в цих двох файлах однієї strace-сесії; жодного `NV_ESC_*` у корпусі |
| C35 | `docs/42-local-toolchain-and-remaining-targets.md` уже існує, тому номер `42` мають два документи | `docs/` | **supported**, але неповно: файл має номер `49` у назві й `42` у H1 — розбіжність, яку документ не називає (§2.14) |
| C36 | Triage-посилання на docs/15, 19, 23, 24, 25, 27, 28 (що саме там уже доведено) | відповідні `docs/*.md` | **supported** — docs/15 §64/§71 `UNPROVEN`; docs/24 §3 «string-only»; docs/25 `channel_pool_add`; docs/23 рядок 1 = `nvUvmInterfaceChannelAllocate 0x08020560, 200 B` |
| C37 | `ALLOC_CHANNEL_DMA` `0x05d5cd05` — рядок, не доведений шлях | `ev_b5545ae0…` | **supported** — `0x05d5cd05 … .rodata ascii ALLOC_CHANNEL_DMA`, і статус у документі саме `string-only` + `UNPROVEN` |
| C38 | У корпусі трасовано лише `0x25` (userspace-бік) | `evidence/rea-20261128/libcuda-uuid-to-uvm-ioctl.txt` | **supported** — «The ONLY ioctl call with request `0x25` … yielded exactly one match: `0x449faf`»; `docs/ioctl-map.md` дає `0x25 = UVM_REGISTER_GPU`, `0x1b = UVM_REGISTER_CHANNEL` |

Підсумок: **28 supported, 7 overstated, 3 unsupported, 0 unverifiable.**

## 2. Корекції: що саме не так і чим це доведено

### 2.1 C07 — «новий факт» не новий

`docs/49` §2: «`docs/27` і `docs/28` довели … **Об'єкт за `parent` там лишався
неназваним**», і заголовок §2 — «Новий `statically proven` факт».

Це неправда вже на рівні репозиторію:

- [`docs/35`](35-rea-p1-btf-type-proof.md) рядок 70: «`uvm_gpu_struct` …
  `channel_manager` @ 6648 (`0x19f8`), тип `uvm_channel_manager_t *`», і рядок
  140: «`gpu+0x19f8` = `channel_manager` … **statically proven** (BTF + REA)»;
- [`docs/28`](28-rea-p1-uvm-channel-manager-callers.md) рядок 136 уже пише
  «`+0x19f8` = `channel_manager` за BTF (docs/35)».

Тобто `docs/49` §2 повторює `docs/35` і подає це як закриття прогалини, якої на
момент merge не було. **Що залишається правильним:** числа `6648` і `2192`
справді є в BTF-файлі (C05), і зв'язка «вікно аргументів ↔ поле BTF» справді
коректна. **Що треба змінити:** прибрати «новий» і «лишався неназваним»;
правильне формулювання — «підтверджує BTF-ідентифікацію з `docs/35` на тому
самому артефакті й додає таблицю полів».

Додатково: `docs/49` §2 називає BTF-файл і дизасемблювання «двома незалежними
артефактами». Вони не незалежні: обидва зняті з того самого
`nvidia-uvm.ko` (`81b21527…`), один із секції `.BTF`, другий із `.text`. Два
незалежні *види* доказу з одного бінарника — так, два незалежні артефакти — ні.

### 2.2 C11 — evidence-покажчик покриває лише хвіст рядка

`docs/49` §3, рядок таблиці про destroy, посилається на
`ev_7fe9462c3eb725ce4bf5ba4208057adaca5f83c53a7beca43ae405c41a957030`. Команда
цього запису: `pd 55 @ 0x08022510; pd 30 @ 0x08020640; pd 22 @ 0x08da2c00;
pd 18 @ 0x08022410`. У ньому **немає** ані `0x08021c70`, ані розмірів 94 B /
92 B; є тільки `0x08da2c00 → call sym._nv046797rm … @ 0x080ded60`.

Адреса й розміри справжні, але лежать в іншому записі —
`ev_d34f8c8a0c53fc42be81922b67a1b8fe875b59cbd219959cbe9c084e4b922af5`
(`is~channel`): `62937 0x00021c70 0x08021c70 GLOBAL FUNC 94
nvUvmInterfaceChannelDestroy`, `63330 0x00da2c00 0x08da2c00 GLOBAL FUNC 92
rm_gpu_ops_channel_destroy`. Ланка `0x08021c70 → 0x08da2c00` дизасемблюванням не
показана взагалі: у корпусі немає жодного `pd` з `0x08021c70`.

**Корекція:** додати `ev_d34f8c8a…` як джерело адреси й розмірів, а перехід
`nvUvmInterfaceChannelDestroy → rm_gpu_ops_channel_destroy` знизити до
`interpretation` (адреса сусідня, форма обгортки вгадується, але самого
tail-jump не захоплено).

### 2.3 C13 — `_nv049654rm` названо тим самим диспетчером без жодного його байта

`docs/49` §3: «`_nv049654rm` і `_nv054249rm(1)` — той самий диспетчер із кроком
`0xe8`, що й у memory-шляху».

- Про `_nv054249rm(1)` — усе правильно: `mov edi, 0x01` перед `call
  sym._nv054249rm` (`0x080df2c9`/`0x080df2d1`), а тіло `0x080cde30` справді
  `mov eax, edi; imul rax, rax, 0xe8; add rax, reloc..rodata.8eb77e0; ret`
  (`ev_0eb7e6e6…`). Індекс `1` → запис `0x08eb77e0 + 0xe8`.
- Про `_nv049654rm` — у корпусі є **лише** рядок виклику:
  `0x080df2c4 call sym._nv049654rm ; RELOC 32 _nv049654rm @ 0x08d8a560`.
  Тіла `0x08d8a560` немає ні в одному з 273 записів, і в жодному символьному
  дампі корпусу `_nv049654rm` не з'являється — тільки як ціль релокації. Твердження, що це той самий
  `0xe8`-диспетчер, нічим не підкріплене.

**Корекція:** `_nv049654rm` — виклик зафіксований (`statically proven`), його
тіло і семантика — `UNPROVEN`; «той самий диспетчер» лишити тільки за
`_nv054249rm`.

Побічно: `docs/49` §10 називає базу таблиці `.rodata` `0x08eb77e0`. Артефакт
каже `RELOC 32 .bss @ 0x08eaa6c0 + 0xd120`, тобто **`.bss`**, не `.rodata`.
Для `docs/49` це не головне, але за house-rule «рядки в `.rodata` — це імена,
не шляхи коду» різниця суттєва: `.bss`-таблиця заповнюється в рантаймі, а
`.rodata` — ні. `docs/24` §2.1 має ту саму помилку в підписі.

### 2.4 C18 — «жодного `ALLOC_CTX`» хибне: рядок є в репозиторії

`docs/49` §4, «Чого немає»: «жодного рядка `ALLOC_CONTEXT_DMA`, `CONTEXT_DMA`
або `ALLOC_CTX` у захоплених рядкових інвентарях».

Артефакт `ev_753479f26fb960cac9778632e8ae96bc1b2ff0e0067f8075449ab439c138b747`
(`px 320 @ 0x0dd5cc80`, бандл `evidence/rea-20261128/evidence-p1-add-gpu-call-sites.json`)
показує суцільну `.rodata`-таблицю RM-імен:

```text
0x0dd5ccc0  4755 4553 545f 5359 5354 454d 5f49 4e46  GUEST_SYSTEM_INF
0x0dd5ccd0  4f00 414c 4c4f 435f 524f 4f54 0041 4c4c  O.ALLOC_ROOT.ALL
0x0dd5cce0  4f43 5f44 4556 4943 4500 414c 4c4f 435f  OC_DEVICE.ALLOC_
0x0dd5ccf0  4d45 4d4f 5259 0041 4c4c 4f43 5f43 5458  MEMORY.ALLOC_CTX
0x0dd5cd00  5f44 4d41 0041 4c4c 4f43 5f43 4841 4e4e  _DMA.ALLOC_CHANN
0x0dd5cd10  454c 5f44 4d41 004d 4150 5f4d 454d 4f52  EL_DMA.MAP_MEMOR
0x0dd5cd20  5900 4249 4e44 5f43 5458 5f44 4d41 0041  Y.BIND_CTX_DMA.A
```

Щоб адреси не були на око: `ALLOC_CHANNEL_DMA` у цій же таблиці починається
на `0x05d5cd05` (рядок 5), що збігається з `docs/49` §9 — отже зсув рядків
ураховано правильно. Тобто в захопленому артефакті є **`ALLOC_CTX_DMA`** (Rizin VA `0x05d5ccf7`) і
**`BIND_CTX_DMA`** (`0x05d5cd22`) — обидва містять рядок `ALLOC_CTX`/`CTX`,
який документ оголошує відсутнім. Це не «coverage limitation»: рядок у
корпусі є, і саме в тому бандлі, з якого `docs/49` бере свій channel-ланцюг.

Застереження, яке треба зберегти: `px` — це hex-дамп, а не `izz`-інвентар,
тому формально «рядкові інвентарі» (`izz~…`) `ALLOC_CTX` не містять; але
висновок, який робить документ («цього рядка немає в наявному корпусі»),
хибний — рядок є, і він лежить між `ALLOC_MEMORY` і `ALLOC_CHANNEL_DMA` у
тій самій таблиці імен методів.

**Корекція:** замінити «жодного рядка» на «рядок `ALLOC_CTX_DMA` є
(`0x05d5ccf7`), прив'язки до тіла коду немає»; статус
`CONTEXT_ALLOC_OBSERVED` при цьому **не** змінюється — імені без call-site
недостатньо, і документ правильно відмовляється підвищувати його.

### 2.5 C22 — `is~notify` повертає не «лише» ACPI/DRM

`docs/49` §5: «`is~notify` повертає лише ACPI/DRM-notifier-и: …».

Запис `ev_175d63f7068176551e673e62d7f93cbc0b8dcee871d8ec1bdff69ade089e026e`
повертає 15 рядків. П'ять названих у документі справді там є
(`nv_acpi_notify_event`, `nv_install_notifier`, `nv_uninstall_notifier.part.0`,
`rm_request_dnotifier_state`, `rm_acpi_notify`), але крім них:

```text
63425 0x00dc6640 0x08dc6640 GLOBAL FUNC      144     nvswitch_lib_notify_client_events
63581 0x00d970e0 0x08d970e0 GLOBAL FUNC       92     rm_notify_gpu_removal
63597 0x00d97080 0x08d97080 GLOBAL FUNC       92     rm_notify_gpu_addition
63243 0x00022b40 0x08022b40 GLOBAL FUNC      129     nv_uvm_notify_start_device
63575 0x00022be0 0x08022be0 GLOBAL FUNC      129     nv_uvm_notify_stop_device
64042 0x00d96f90 0x08d96f90 GLOBAL FUNC      225     rm_acpi_nvpcf_notify
```

`nvswitch_lib_notify_client_events`, `rm_notify_gpu_removal/addition` і
`nv_uvm_notify_start/stop_device` — не ACPI і не DRM. Слово «лише» робить
перелік хибним; сам висновок («GPU-подієвого notifier-а в таблиці символів
немає») від цього не падає, бо жоден із 15 символів не є
notifier/event-GPFIFO-функцією.

**Корекція:** прибрати «лише», перелічити 15 (або прямо сказати «серед них»).

### 2.6 C24 — `os_alloc_semaphore` приписано запису, у якому його немає

`docs/49` §5 приписує `os_alloc_semaphore` `0x08018cc0` (134 B) запису
`ev_41ba59bdb7d209ea361591e08fb50023938299f69ad0348f0d83e2530f3a1d86`
(`is~event`). У цьому записі `os_alloc_semaphore` **немає** — там є
`g_pNvUvmEventsLock`, `g_pNvUvmEvents`, `nv_get_event`, `nv_post_event`,
`nv_uvm_event_interrupt`, `rm_init_event_locks`, `rm_destroy_event_locks`, і
все. `os_alloc_semaphore 0x00018cc0 GLOBAL FUNC 134` лежить у
`ev_9ba627a62286b27b05766bcf9bded599f4395ee5d55455bf99fde1eb5e87630b`
(`is~notifier`/`is~GPFIFO`/`is~semaphore`).

**Корекція:** переставити покажчик. Сам факт (адреса, розмір, наявність)
правильний.

### 2.7 C17 — три context-рядки, а в тому ж записі їх чотири

`docs/49` §4 перелічує три `.rodata`-рядки як «що є». У тому самому записі
`ev_b5545ae0…` (`izz~channel`) є ще один:

```text
0x05cc5130 0x0dcc5130   40   41 .rodata                   ascii   channelDeleteSubchannelContextEntry_IMPL
```

Документ не заявляє перелік вичерпним, тому це не помилка статусу, але при
аргументі «context-об'єкта немає, є лише імена» чотири імені краще за три.
**Корекція:** додати четвертий рядок.

### 2.8 C10 — «192 байти» і «4955» — оцінки, а не арифметика

Вікно `pd 45 @ 0x080df240` закінчується інструкцією `0x080df2ff` (45-та).
Отже покрито 45 інструкцій від `0x080df240` до `0x080df303` включно, тобто
192–196 байтів залежно від довжини останньої інструкції; «≈3.7 %» правильне
в будь-якому разі, а «решта 4955 байтів» — це `5147 − 192`, тобто оцінка з
точністю до кількох байтів. Формулювання «захоплено 192 із 5147» краще
замінити на «45 інструкцій від початку функції (≈0xc0 байтів із 5147)».

### 2.9 C26 — «той самий набір шаблонів» — не той самий

`docs/49` §6.1 каже, що «той самий набір шаблонів із префіксом знайшов усі
чотири рядки». Фактично keyed-запис
`ev_cc1bb8a59a60d5c28de2c0a84cf18619468ce7d46da871386f0ce680e0d38e7f` має
**три** шаблони (`izz~kchannelBindToRunlist_IMPL`,
`izz~CTRL_GPFIFO_SET_WORK_SUBMIT_TOKEN_NOTIF_INDEX`,
`izz~MAP_MEMORY_DMA`), а четвертий рядок, `UNMAP_MEMORY_DMA`
(`0x05d5cd6e`), збігся як підрядок третього шаблону. Тобто «чотири рядки» — це
три шаблони й один підрядковий збіг. Висновок §6.1 (порожній результат — це
артефакт відсутнього ключа) від цього не змінюється.

### 2.10 C28 — «рядок не існує» — це той самий absence-claim, від якого застерігає §6

`docs/49` §6.3: «Рядок `NON_STALL` у файлі **не існує**». Обидва запити
(`ev_0d2a1438…`, `ev_73b123ff…`) мають у `stderr` той самий набір
`WARNING: bin_file_strings: search interval size (0xea7dda | 0x4ef2792 |
0xe5ef60) exceeds max region size (0xa00000), skipping it`, тобто ≈0x63 MB
модуля в пошуку не брали участі. За правилом самого `docs/49` §6.2
коректне формулювання — «рядок `NON_STALL` не знайдено в переглянутих
регіонах», а не «не існує».

Що **справді** доводить пара записів: у цій збірці Rizin `izz~` чутливий до
регістру (`NON_STALL` → 0, `nonstall` → 2). Це підтверджено й фіксується без
змін.

### 2.11 C29 — `CHANNEL_ALLOC` у трейсі чотири, не три

`docs/49` §7 цитує три рядки й пише «три `CHANNEL_ALLOC` з `= 0`». У
`evidence/nouveau-20261127/10-ioctl.txt` їх **чотири**:

```text
13:1749  ioctl(3, DRM_IOCTL_NOUVEAU_CHANNEL_ALLOC, 0x7ffde0a1bd30) = 0
44:1749  ioctl(7, DRM_IOCTL_NOUVEAU_CHANNEL_ALLOC, 0x7ffde0a1dc90) = 0
58:1749  ioctl(7, DRM_IOCTL_NOUVEAU_CHANNEL_ALLOC, 0x7ffde0a1dd80) = 0
74:1749  ioctl(7, DRM_IOCTL_NOUVEAU_CHANNEL_ALLOC, 0x7ffde0a1dd60) = 0
```

Чотири `CHANNEL_ALLOC` і чотири `CHANNEL_FREE`: один `ALLOC` і один `FREE`
на fd `3`, три `ALLOC` і три `FREE` на fd `7`. Цитовані три рядки — дослівно правильні; хибне саме число й те,
що цитата подана як повний перелік. Другий файл тієї самої сесії,
`11-drm-ioctl.txt`, дає ті самі чотири рядки (рядки 10, 32, 40, 54).

**Корекція:** «чотири `CHANNEL_ALLOC` (два fd, по два)». Висновок §7 — що це
єдиний runtime-слід і що він належить Nouveau — не змінюється.

### 2.12 C31 — «усі обгортки однакової форми» — ні

`docs/49` §8: «Усі `rm_gpu_ops_*`-обгортки в захоплених вікнах мають однакову
форму: обгортка `nvUvmInterface*` робить `xor edi, edi` і tail-jump».

У тому самому записі, на який §8 спирається (`ev_8dfb7557…`), є контрприклад:

```text
            ;-- nvUvmInterfacePagingChannelPushStream:
            0x0801f490      endbr64
            0x0801f494      call  reloc.target.__fentry
            0x0801f499      mov   rax, qword [rdi+0x18]
            0x0801f49d      mov   ecx, edx
            0x0801f49f      mov   rdx, rsi
            0x0801f4a2      mov   rsi, rdi
            0x0801f4a5      mov   rdi, rax
            0x0801f4a8      jmp   sym.rm_gpu_ops_paging_channel_push_stream
```

Тут немає ні `rm_is_altstack_in_use`, ні `xor edi, edi`, ні виділення
`nvidia_stack_t`: обгортка передає далі **вказівник, прочитаний із `[rdi+0x18]`**.
А `rm_gpu_ops_paging_channel_push_stream` (`0x08da3bf0`) одразу робить
`mov rbx, rdi; mov rax, qword [rbx+0x08]` — ту саму пару інструкцій, що §8
тлумачить як «читання стека». Отже форма «`xor edi,edi` + `[rbx+0x08]`» не є
ані загальною, ані єдиною, і гіпотеза §8(a) («`[rbx+0x08]` — поле стека») не
випливає з однаковості обгорток: щонайменше в одній обгортці `rdi` — реальний
об'єкт.

**Корекція:** звузити до «обгортки alloc/map/destroy у захоплених вікнах», а
`push_stream` назвати окремо як обгортку іншої форми. Семантика
`[rbx+0x08]` усе одно лишається `UNPROVEN` — але тепер із двох боків, а не з
одного.

### 2.13 C32 — `mov rdi, rax` видно; вікно не там обривається

`docs/49` §8: «Вікно обривається на `test rax, rax` (`0x080205b9`), тому самого
`mov rdi, rax` **не видно**».

У записі `ev_8dfb7557c91ed0fbe32435b247cee0d9c05d3e177825163d50465b0c9ee378d0`
видно рівно це:

```text
       |`-> 0x080205a5      mov   rdi, qword [obj.nvidia_stack_t_cache]
       |    0x080205ac      mov   esi, 0xcc0                           ; 3264
       |    0x080205b1      call  reloc.target.kmem_cache_alloc_noprof
       |    0x080205b6      mov   rdi, rax
       |    0x080205b9      test  rax, rax
```

`mov rdi, rax` — на `0x080205b6`, за одну інструкцію до `test rax, rax`, у
межах того самого `pd 30`. Вікно обривається **після** цієї інструкції, а не
перед нею.

**Корекція:** пункт §8(а) не «найімовірніше», а показаний: у altstack-гілці
`rdi` — щойно виділений `nvidia_stack_t`. Не показаний лише **сам виклик**
`rm_gpu_ops_channel_allocate` з цим `rdi` (наступна інструкція після
`test rax, rax` у вікно не потрапила). Це підсилює гіпотезу (а) і послаблює
(б) для altstack-гілки; для не-altstack гілки (`xor edi, edi`) питання
`[0x08]` лишається відкритим і далі.

### 2.14 C35 — нумерація: у файлі `49`, у заголовку `42`

`docs/49` §0 пише примітку про те, що номер `42` тепер мають два документи
(`docs/42-local-toolchain-and-remaining-targets.md` і цей). Примітка
правильна, але неповна: файл називається `49-rea-p1-channel-context-notifier-direction.md`,
а H1 у ньому — `# 42 — REA P1: напрямок channel / context / notifier`.
За house-rule «номери документів послідовні й вільні» H1 має читатися `# 49`.
Цей документ (`docs/50`) номер `49` не займає і `docs/49` не перейменовує —
рішення про перейменування лишається за власником.

## 3. Що лишається неверифікованим

- **0 тверджень із 38** не вдалося перевірити: усі 17 `ev_<sha256>`-посилань
  `docs/49` резолвляться в наявні записи, усі 10 `evidence/`-шляхів існують
  (`scripts/test-doc-evidence-links.sh` для `docs/49` чистий).
- Межа, яку треба назвати: самих `nvidia.ko` / `nvidia-uvm.ko` у репозиторії
  немає. Усе, що не потрапило в запис, тут **неперевірюване в принципі** —
  саме тому три знахідки (§2.4, §2.11, §2.13) мають вагу: вони показують, що
  «не потрапило в запис» і «немає в артефакті» — різні речі, і `docs/49` в
  одному місці їх змішує.
- Не перевірялося й далі `UNPROVEN`: RM class id і control code для
  channel/context; вміст запису `1` таблиці `0xe8`; сенс `+0x10 ∈ {2,3}`;
  решта тіла `_nv046796rm`; notifier-індекс; fd події ОС; будь-який runtime-
  крок на H170. Цей документ жодного з них не підвищує.
- Не робився новий широкий `/r`, не запускався Ghidra full analysis, не
  знімалися нові капчури. Аудит — це перечитування того, що вже лежить у
  репозиторії.

## 4. Статуси після аудиту

| Що | Було в `docs/49` | Після аудиту |
|---|---|---|
| `uvm_gpu_struct.channel_manager` на `+0x19f8`, `sizeof = 0x890` | `statically proven` | **без змін** (BTF, `docs/35`) |
| Поля `uvm_channel_manager_struct` (10 зсувів) | `statically proven` | **без змін** |
| Ланцюг `ChannelAllocate → rm_gpu_ops_channel_allocate → _nv046796rm` | `statically proven` | **без змін** |
| Гейт `[rdi+0x10] ∈ {2,3}`, `_nv054249rm(1)` | `statically proven` | **без змін** |
| `_nv049654rm` як «той самий `0xe8`-диспетчер» | `statically proven` (у тексті §3) | **`UNPROVEN`** — тіла немає в корпусі |
| `nvUvmInterfaceChannelDestroy → rm_gpu_ops_channel_destroy` | `statically proven` | **`interpretation`** — перехід не захоплено; адреси й розміри `statically proven` з `ev_d34f8c8a…` |
| «`ALLOC_CTX` у корпусі немає» | `coverage limitation` | **хибно** — рядок є (`0x05d5ccf7`); прив'язки немає, `CONTEXT_ALLOC_OBSERVED` лишається `UNPROVEN` |
| `os_alloc_semaphore` `0x08018cc0`/134 B | `statically proven` з `ev_41ba59bd` | **без змін по суті**, покажчик → `ev_9ba627a6…` |
| `is~notify` = «лише ACPI/DRM» | — | **хибно як перелік**; висновок (немає GPU-подієвого notifier-символу) без змін |
| Чотири/три `CHANNEL_ALLOC` у Nouveau-трейсі | «три» | **чотири** |
| `mov rdi, rax` «не видно» | `UNPROVEN` | **видно** (`0x080205b6`); семантика `[rbx+0x08]` усе ще `UNPROVEN` |
| `NON_STALL` «не існує у файлі» | — | **«не знайдено в переглянутих регіонах»** |
| RM class id / control code, notifier-індекс, fd події ОС, runtime | `UNPROVEN` / `NOT RUN` | **без змін** |

## 5. Дрібний ремонт гейта, зроблений разом з цим документом

`bash scripts/test-doc-evidence-links.sh` на `master` **падав** не через
`docs/49`, а через [`docs/48`](48-gp107-open-stack-status-2026-11.md) рядок 146:
там стояв шлях-шаблон із датою-заглушкою (`suspend-` + `YYYYMMDD`), якого не
існує. Рядок переписано на «теку `evidence/` з іменем `suspend-<YYYYMMDD>/`»,
щоб гейт перевіряв реальні посилання, а не шаблон. Це єдина правка поза новим
документом; `docs/49` не змінено ні на байт.

## Ukrainian one-liner

Із 38 тверджень `docs/49` **28 підтверджено** артефактами, **7 перебільшено**
(«новий факт» насправді з `docs/35`; `_nv049654rm` названо диспетчером без
жодного його байта; `is~notify` — не «лише ACPI/DRM»; `os_alloc_semaphore`
приписано не тому запису; `NON_STALL` «не існує» — це absence-claim із
часткового пошуку; «усі обгортки однакової форми» — ні; destroy-ланка
покажчиком не покрита), **3 хибні** (`ALLOC_CTX` у корпусі є; `CHANNEL_ALLOC`
у трейсі чотири, не три; `mov rdi, rax` видно на `0x080205b6`), і **0**
неперевірюваних. Жоден статус `docs/05` не змінено; RM class id, notifier-індекс
і будь-який runtime-шлях на H170 лишаються `UNPROVEN`.
