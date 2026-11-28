# 34 — REA P1: батьківський об'єкт `uvm_channel_manager_create` і тестовий контекст

Це вузьке продовження [`docs/28`](28-rea-p1-uvm-channel-manager-callers.md).
Там лишилося два питання: тип об'єкта в `rdi` та назва функції для області
`0x080bad…`. Тут обидва звужено **без Ghidra-pseudocode, без vendor source,
без Broad `/r` і без `izz~`**: тільки symbol table, relocation-записи й
вирівняні інструкційні вікна.

## 0. Triage перед завданням

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | docs/23–28: RM dispatch, `nvUvmInterface*` call-map, enum `uvm_rm_mem_alloc`, field aliasing, п'ять call-site `uvm_channel_manager_create` | не повторювати |
| `PARTIAL` | docs/28: `rdi = parent` і `rsi = &parent+0x19f8`, але функція для `0x080bad…` і джерело батька не були встановлені | ціль звіту |
| `UPSTREAM_EXISTS` | Nouveau/NVKM/NVK channel manager | implementation authority, не реверсити |
| `UNIQUE_GAP` | символ-власник чотирьох call-site у `0x080bad…` і шлях до батька через `g_uvm_global+0x28` у shipped R580 `nvidia-uvm.ko` | цей звіт |

Індекс docs/01–33 перевірено. Issue #3/#18/#28 і попередній triage зафіксовані
в `docs/28`; `gh api rate_limit` зараз `remaining=0`, тому нових owner-дозволів
не додано. Pin-и v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract, ABI,
asm-first контракт з `docs/33` не змінено.

## 1. Тарґет, tool, Evidence

| Поле | Значення |
|---|---|
| Shipped artifact | `/lib/modules/7.2.15+kali-amd64/updates/dkms/nvidia-uvm.ko.xz`, SHA-256 `80132204f76981b2373baeb936866347e3c80e8527feb118bffe03f6adc10e8f` |
| Target | `/tmp/opencode/rea-nvidia-uvm/nvidia-uvm.ko`, SHA-256 `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` |
| Tool | REA `execute_rizin_command`, `rizin 0.9.1 @ linux-x86-64`, provider executable `rizin`; точну версію provider REA не підтвердив |
| Bundle | `evidence/rea-20261128/evidence-p1-parent-type.json`, 79 record, 2 unknown, SHA-256 `9028f275fa6ac47c42d39acebe5dc69ba29d2ffc1c8616a85b35724f6f6ab3a0` |
| Unknown | `unk_60e2b61cc14cb5c16774bf5bc277761da2726301ae73d`, revision 2, `investigating` |

Ключові Evidence ID (усі — `confidence=observed`, `authority=shipped-artifact`,
target SHA збігається, `artifact_changed=false`, `output_truncated=false`):

| Evidence ID | Команда | Що дала |
|---|---|---|
| `ev_2536085de6aea670c0440a418538a93564d7212a1893be4788ba6043ee57610a` | `is~add_gpu` | `add_gpu @ 0x0801c120`, LOCAL FUNC, 8055 B; `__pfx_add_gpu @ 0x0801c110` |
| `ev_bf549fa2254b211903be492cd8ea8d93e74074354917cc82b22d0ecb8fe35e3c` | `pd 48 @ 0x0801c120` | пролог: `rdi→[rbp-0x118]`, `r8→r12`, `esi→r13d`, `rdx→r14`; `alloc_gpu` / `nvidia-uvm/uvm_gpu.c` |
| `ev_622048175989f633596524ccd003cc6900eba77d4559de86f2ae529a476ba598` | `pD 8055 @ 0x0801c120~rbp-0x118` | усі звернення до слоту `-0x118` у межах 8055 байт функції |
| `ev_78fdd58e2603e89d5b9bdafcaa9132c204945b864643aed8369041755f849eb8` | `pD 8055 @ 0x0801c120~g_uvm_global` | читання/записи `g_uvm_global` і `+0x28` у межах `add_gpu` |
| `ev_ee1f25225f2a6a80c0ce1b321b8b149f90bebbf348784a8129cd2ad2da4bee0c` | `pd 144 @ 0x080bac90` | шлях `g_uvm_global+0x28 → батько r14 → &r14+0x19f8` |
| `ev_91259cfe60f64609431b03851a99fb10d4cb1a11cebaafb4fbf073a1949be59b` | `is~080b` | symbol table області `0x080b…` |
| `ev_6027120f85628e655765ebfe493dcc60b5d620a528ae8734c078ff49c417b35a` | `is~uvm_test_channel_sanity` | `uvm_test_channel_sanity @ 0x080b9f50`, 6901 B; `.cold @ 0x080f320e`, 6587 B |
| `ev_ee1f25225f2a6a80c0ce1b321b8b149f90bebbf348784a8129cd2ad2da4bee0c`, `ev_2d2e178219a54b8d58ef412fdd43fb568423d5ed553bb3dc3b16467e7e5671d0` | `pd 144 @ 0x080bac90`, `pd 56 @ 0x080bad20` | вирівняні вікна чотирьох call-site |
| `ev_c045a0ca3930af4b60da95816eef5f79ff76da7dc2929e2aa7aa9ffd18ededc4`, `ev_f3f61355c84a950c49e4323c1844bd77c60ec5d93784404af7183baf5364e930` | `pd 56 @ 0x080bb180`, `pd 56 @ 0x080bb280` | call-site `0x080bb1d0` і `0x080bb2d2`, той самий слот `+0x19f8` |

Порожний `axt @ 0x0801c120` (`ev_cdcd086a00b00a1ea68036114fb0788c669b932d196f3c0586794f7f9a83432e`)
лишається **coverage limitation**, не absence-proof. Спроба `/c 0x0801c120`
була відхилена Rizin (`completion_status=rejected`, `/c` тут — криптопошук),
`af @ 0x080bad5a` дав синтетичний `fcn.080bad5a` розміром 240206 B без
source-proven імені; обидва результати **не використано як доказ**.

## 2. Хто викликає `uvm_channel_manager_create`

Symbol table дає `uvm_test_channel_sanity @ 0x080b9f50`, розмір 6901 B =
`0x1af5`, тобто інтервал **`0x080b9f50 … 0x080bba45`**. Усі чотири адреси з
`docs/28` лежать усередині:

| Call | Функція-власник | Статус |
|---|---|---|
| `0x080bad5a` | `uvm_test_channel_sanity` | **statically proven** (symbol range) |
| `0x080baeba` | `uvm_test_channel_sanity` | **statically proven** |
| `0x080bb1d0` | `uvm_test_channel_sanity` | **statically proven** |
| `0x080bb2d2` | `uvm_test_channel_sanity` | **statically proven** |
| `0x0801c539` | `add_gpu @ 0x0801c120` | **statically proven** (symbol range) |

Поруч у тих самих вікнах: `nvidia-uvm/uvm_channel_test.c`,
`test_conf_computing_channel_selection`, `concurrent push %u`,
`uvm_test_rc_for_gpu`, `test_iommu_stale_invalid` — **string-only / symbol-proven
контекст тесту**. Наслідок: чотири перестворення channel manager-а в
`0x080bad…` належать **self-test шляху**, а не доведеному production GPU init.
Це виправляє формулювання `docs/28`, де назва функції була `UNPROVEN`.

Caller/callee для самого `add_gpu`: прямих caller-ів не знайдено (`axt` порожньо,
релокації на локальний `add_gpu` немає). `ir~add_gpu` містить лише PLT-виклики
до **інших** функцій (`uvm_perf_heuristics_add_gpu`, `uvm_ats_add_gpu`, …) —
не до `add_gpu @ 0x0801c120`. Caller-и лишаються `UNPROVEN`.

## 3. Джерело батьківського об'єкта

`g_uvm_global @ 0x0810b0a8`, GLOBAL OBJ, 191128 B (`ev_399288286ff4a321a49e33926b342d9d94f44bf70d97b15933a0eca8fc96d57b`).
Зсув `+0x28` = `0x0810b0d0`; інструкції звертаються до тієї самої таблиці:

| Адреса | Інструкція | Статус |
|---|---|---|
| `0x0801c1cf` | `mov [r12+r13*8+0x08], rbx` — новий об'єкт записується в `parent->gpus[]` | **statically proven** (тип із BTF, див. docs/35) |
| `0x0801c1d4` | `add dword [r12+0x04], 1` — `parent->num_retained_gpus++` | **statically proven** |
| `0x0801c46d` | `mov rax, [r13*8+0x810b0d0]` | **statically proven** |
| `0x0801c484` | `mov r13, [rax+rdx*8+0x08]` — елемент `parent->gpus[]` | **statically proven** |
| `0x0801c7e6` | `mov r12, [r14*8+0x810b0d0]` | **statically proven** |
| `0x0801d4d5` | `mov [r12*8+0x810b0d0], r10` | **statically proven** |
| `0x080bacc7` | `mov rax, [r14*8+0x810b0d0]` — `parent_gpus[r14]` | **statically proven** |
| `0x080bacdc` | `mov r14, [rax+r13*8+0x08]` — `parent->gpus[r13]` = `uvm_gpu_t *` | **statically proven** |
| `0x080bacea` | `cmp qword [r14+0x78], 1` — `gpu->retained_count == 1` | **statically proven** |

BTF того ж shipped-артефакта (`docs/35`) робить типи **`statically proven`**:
`g_uvm_global+0x28` = `uvm_global_struct.parent_gpus[32]` (`uvm_parent_gpu_t *`),
`parent+0x08` = `uvm_parent_gpu_struct.gpus[8]` (`uvm_gpu_t *`), а
`gpu+0x19f8` = `uvm_gpu_struct.channel_manager` (`uvm_channel_manager_t *`).
Отже батько для `uvm_channel_manager_create` — **`uvm_gpu_t *`**, з проміжним
ланцюгом `parent_gpus[] → uvm_parent_gpu_t → gpus[] → uvm_gpu_t`.

## 4. Перший аргумент `add_gpu`

У пролозі `rdi` зберігається в `[rbp-0x118]` (`0x0801c151`). У межах 8055 байт
функції (`pD`, не `pd`!) цей самий стековий слот перезаписується вже на
`0x0801c263` (`mov [rbp-0x118], r10`), а перше читання — `0x0801c26f`. У гілці
`r8 != 0` початкове `rdi` не читається з цього слоту до перезапису; у гілці
`r8 == 0` («`alloc_parent_gpu`», `0x0801c871`) слот читається як `rsi` на
`0x0801c899` для `uvm_uuid_copy` з `rdi = &parent->uuid` (`+0x50` за BTF).
Отже:

- `mov [rbp-0x118], rdi`, перезапис і порядок читань — **statically proven**;
- у гілці `r8==0` перший аргумент є UUID-джерелом для `parent->uuid` —
  **statically proven** (BTF + `uvm_uuid_copy`);
- у гілці `r8!=0` перший аргумент не використовується до перезапису слоту —
  **statically proven**;
- повний прототип `add_gpu` і його caller-и — **`UNPROVEN`**.

Паралельно **statically proven** з того самого вікна: `rdi` для
`nvUvmInterfaceDeviceCreate` на `0x0801c248` береться з `g_uvm_global+0x128`
(`0x0810b1d0`, BTF: `rm_session_handle`), а не з першого аргументу; `bts
[g_uvm_global], rax` на `0x0801c776` — бітовий масив у тій самій глобальній
структурі.

## 5. Статуси й межі

| Твердження | Статус |
|---|---|
| 5 call-site, `rdi=uvm_gpu_t *`, `rsi=&gpu+0x19f8`, перевірка `eax` | **statically proven** (docs/28, 34, 35) |
| Чотири call-site в `0x080bad…` належать `uvm_test_channel_sanity` | **statically proven** (symbol range) |
| Ланцюг `+0x28 → parent → +0x08 → gpu → +0x19f8 → manager` | **statically proven** (BTF + REA) |
| Розміри 0x1d98/0xc228 = `uvm_gpu_t`/`uvm_parent_gpu_t` | **statically proven** (BTF) |
| RM handle `+0x1e0`, RM class/runlist/notifier/fence | **`interpretation`/`UNPROVEN`** |
| Caller-и `add_gpu` з source-proven іменами | **`UNPROVEN`** (`axt` порожньо) |
| Порожний `axt`, відхилений `/c`, синтетичний `af`, хит у `patchable_function_entries` | **coverage limitation / rejected observation**, не absence-proof |
| BOOT0, `0x137000A1`, `BDF ↔ RM gpu_id`, причина NVK↔NVIDIA | **`UNPROVEN` / `string-only` / `PARTIAL`** без змін |
| Фізичний MMIO, RM-запити, compute, PR #21 | **`NOT RUN`** |

Не робилось: MMIO/BAR read/write, `nva`, RM-ioctl, reboot, GPU compute,
запуск PR #21 executable, Ghidra-pseudocode, vendor source, transfer-код,
release/tag/publish, зміни pin-ів/SENS/CML/ADR/target contract/asm-first ABI.

## 6. Питання без відповіді й найменший крок

`unk_60e2b61cc14cb5c16774bf5bc277761da2726301ae73d05373cf6d060b104e92`
закрито на revision 4 (`resolved`) у частині типу й ролі `rdi` для `r8==0`.
Лишається `UNPROVEN`: прямий caller `add_gpu` і повний прототип. Найменший
крок — цільові Rizin-вікна в межах відомих symbol-range, без broad `/r`,
з подальшою перевіркою першого аргументу безпосередньо на `call`-site.

## Ukrainian one-liner

Чотири виклики `uvm_channel_manager_create` в області `0x080bad…` належать
`uvm_test_channel_sanity`; BTF доводить ланцюг `parent_gpus[] →
uvm_parent_gpu_t → gpus[] → uvm_gpu_t → channel_manager`, а роль першого
аргументу `add_gpu` у гілці `r8==0` — UUID-джерело. Caller-и лишаються
`UNPROVEN`.
