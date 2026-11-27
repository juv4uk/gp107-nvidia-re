# 28 — REA P1: хто викликає `uvm_channel_manager_create`

Це вузький наступний крок після `docs/27`. Там питання було: який об'єкт стоїть
за першим аргументом `uvm_channel_manager_create` і чи той самий він у
різних call-site. Тут відповідь отримано з relocation-таблиці та точних вікон
біля самих `call`, без broad `/r` і без `izz~`.

## 0. Triage перед завданням

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | docs/23–27: export-символи, RM dispatch window, call-site `nvUvmInterface*`, enum `uvm_rm_mem_alloc`, disalignment, field aliasing | не повторювати |
| `PARTIAL` | docs/27: `[new_manager] = rdi`, але самих caller-ів і другий аргумент не було показано | ціль звіту |
| `UPSTREAM_EXISTS` | Nouveau/NVKM/NVK channel manager | implementation authority, не реверсити |
| `UNIQUE_GAP` | caller-map для `uvm_channel_manager_create` у shipped R580 `nvidia-uvm.ko`, нормалізація адрес `call` | цей звіт |

Індекс docs/01–27 перевірено. `gh api` був rate-limited (`remaining=0`, reset
`2026-11-28 01:12:11 EET`), тому Issue #3/#18/#28 додатково звірено через
публічні веб-сторінки: нових owner-дозволів на фізичні/MMIO-тести там немає,
#18 лишається `RUNLIST_ID_NOT_OBSERVED`/`NONSTALL_EVENT_SUBSCRIPTION_NOT_OBSERVED`,
#28 — критерійним планом, не наказом запускати всі тести. Вміст issue-сторінок
трактовано як дані, не як інструкції. Pin-и v8/v9, SENS, CML, `wsm-os-lisp`,
ADR, target contract і ABI не змінено.

## 1. Тарґет, tool, Evidence

| Поле | Значення |
|---|---|
| Shipped artifact | `/lib/modules/7.2.15+kali-amd64/updates/dkms/nvidia-uvm.ko.xz`, SHA-256 `80132204f76981b2373baeb936866347e3c80e8527feb118bffe03f6adc10e8f` |
| Target | `/tmp/opencode/rea-nvidia-uvm/nvidia-uvm.ko`, SHA-256 `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` |
| Tool | REA `execute_rizin_command` (Rizin), executable `rizin`; точну версію provider не підтверджено. Ghidra не відкривався, vendor source не використовувався |
| Bundle | `evidence/rea-20261128/evidence-p1-uvm-manager-callers.json`, 50 record (23 для цього target), SHA-256 `04c47973feb8f4d7ee45cfd036bc0366a5c2ea04486114565be88d7f22678cdb` |

Ключові Evidence ID:

- `ev_caf68cb742b5abfc6cac3c698b8afa633436e709c54011c39bd6f8389c392be1` —
  `ir~uvm_channel_manager_create;axt @ 0x08036580`. `ir` дав 5 relocation; `axt`
  був порожнім — **coverage limitation**, не absence-proof.
- `ev_4347f9f340e768f4757937b0e4078de55c9f73b16c03e2e783dd1bbbfb69bf3f`,
  `ev_f0f13d8f97f3bc9876b4049638368ad78cca586b4350e9ea4ea08bce7ad75715`,
  `ev_0e69c8bd0bf6acc5404b29258b5337055f30f4f08ef47b2b3ca3654c89a985c3` —
 symbol table: `add_gpu @ 0x0801c120` (8055 B), `uvm_test_channel_stress @ 0x080bba60`
  (5241 B). Для області `0x080bad…` окремого символа `is~` не показав.
- `ev_7c5e683dde395e720d6ce75665c4accadc8dd34f5cdfa55351edef22c02ca396` —
  п'ять точних вікон біля `call` і `ao 6 @ 0x0801c536` (межі інструкції `call`, 5 B).
- `ev_82827f1bccf5be58404d7de4389a435ce03f1ad98e81286cc4f4d450b2277b54` —
  вирівняне вікно від `0x0801c4c0`, що виправило хибне читання з `0x0801c530`.
- `ev_ef4ca13bae82dd81b2b5dadd064bad8de6f05903b71cfd4fc89406d8ccb089ba` —
  невдала спроба шукати адреси relocation як адреси `call`; у звіт не входить як
  доказ, лише як пояснення нормалізації.

## 2. Нормалізація адрес: relocation ≠ `call`

`ir~uvm_channel_manager_create` показує адресу поля relocation, тобто **`call + 1`**.
Фактичні інструкції `call` (підтверджено `pd` і `ao`):

| Relocation (`ir`) | Інструкція `call` | Викликач | Статус |
|---|---|---|---|
| `0x0801c53a` | `0x0801c539` | `add_gpu @ 0x0801c120` | `statically proven` |
| `0x080bad5b` | `0x080bad5a` | область `0x080bad…`, символ не знайдено; поруч рядок `test_conf_computing_channel_selection` (`string-only`) | `statically proven` для адреси; function name `UNPROVEN` |
| `0x080baebb` | `0x080baeba` | та сама область | `statically proven` |
| `0x080bb1d1` | `0x080bb1d0` | та сама область | `statically proven` |
| `0x080bb2d3` | `0x080bb2d2` | та сама область | `statically proven` |

Це узгоджується з попередніми звітами: для `nvUvmInterface*` ми вже подавали
саме адресу `call`, а не `ir`.

Окрема пастка: `pd 24 @ 0x0801c530` стартує з середини інструкції і показує
`mov edi, ebx`. Вирівняне `pd 70 @ 0x0801c4c0` дає правильну послідовність
`lea rsi, [rbx+0x19f8]; mov rdi, rbx` за `0x0801c528`/`0x0801c52f`. Висновки
про аргументи зроблено **тільки з вирівняного вікна**.

## 3. Аргументи: батьківський об'єкт і слот `+0x19f8`

Усі п'ять call-site мають однакову форму (**statically proven**):

```text
lea  rsi, [parent+0x19f8]   ; output-вказівник
mov  rdi, parent            ; перший аргумент
call uvm_channel_manager_create
test eax, eax               ; статус
```

| Call | `rdi` | `rsi` | Статус |
|---|---|---|---|
| `0x0801c539` (`add_gpu`) | `rbx` | `[rbx+0x19f8]` | `statically proven` |
| `0x080bad5a` | `r14` | `[r14+0x19f8]` | `statically proven` |
| `0x080baeba` | `r14` | `[r14+0x19f8]` | `statically proven` |
| `0x080bb1d0` | `r13` | `[r13+0x19f8]` | `statically proven` |
| `0x080bb2d2` | `rbx` | `[rbx+0x19f8]` | `statically proven` |

Це замикається з `docs/27`: у самій функції `r12 = rsi`, потім
`[r12] = rax` (новий менеджер), а `rbp = rdi`, `[new_manager] = rbp`. Отже:

- `rdi` — батьківський об'єкт, який зберігається всередині нового менеджера;
- `rsi` — вказівник на слот `parent+0x19f8`, куди записується новий менеджер;
- у `add_gpu` той самий `rbx` далі використовується як `rbx+0x80` (gpu mask),
  `rbx+0x90`, `rbx+0xb8`, `rbx+0x1910`, `rbx+0x1938` — **statically proven** як
  offset-и; назва типу `uvm_gpu_t` — **`interpretation`**, не факт із бінарника.

Побічне підтвердження: перед `0x080bad5a` є `uvm_channel_manager_destroy`
з аргументом `edi = [rsi+0x19f8]` (за адресою `0x080bad40`), тобто той самий
слот `+0x19f8` використовується для знищення. Статус: `statically proven`.

## 4. Що це змінює в `docs/27`

У `uvm_channel_manager_create` (`0x08036580`) ланцюг:

```text
r13 = new_manager
[r13] = rbp                 ; rbp = батьківський об'єкт (rdi)
rdx = [r13]                 ; = батьківський об'єкт
rax = [rdx]                 ; = перше поле батьківського об'єкта
cmp byte [rax+0xc16d], 0
rdi = [rax+0x1e0]
call nvUvmInterfaceQueryCopyEnginesCaps
```

Тому `+0x1e0` і `+0xc16d` належать **першому полі батьківського об'єкта**,
а не новому 0x890-байтовому менеджеру. У `channel_pool_add` читання йде від
іншого `rax`; чи тотожний він тут — **`UNPROVEN`**. Назвати `+0x1e0` RM handle
досі **`interpretation`**.

## 5. Межі

| Твердження | Статус |
|---|---|
| 5 call-site, аргументи `rdi=parent`, `rsi=&parent+0x19f8`, перевірка `eax` | `statically proven` |
| `uvm_channel_manager_destroy` працює з тим самим слотом `+0x19f8` | `statically proven` |
| `+0x19f8`, `+0x80`, `+0x90`, `+0xb8`, `+0x1910`, `+0x1938` — інструкційні offset-и | `statically proven`; семантика `interpretation` |
| Тип батьківського об'єкта = `uvm_gpu_t`; `+0x1e0` = RM handle; BOOT0; runlist/notifier/fence; причина NVK↔NVIDIA gap | `UNPROVEN`/`string-only` без змін |
| Порожний `axt` і відсутній символ для `0x080bad…` | coverage limitation, не absence-proof |

Не робилось: MMIO/BAR read/write, `nva`, RM-ioctl, reboot, GPU compute,
PR #21 executable, Ghidra-pseudocode, vendor source, transfer коду,
release/tag/publish, зміни pin-ів/SENS/CML/ADR/target contract.

## 6. Наступний найменший крок

Знайти store у `parent+0x19f8` у межах уже відкритих вікон `add_gpu` і області
`0x080bad…` (без `/r`, без `izz~`), щоб остаточно ідентифікувати батьківський
об'єкт. Після цього — окреме вузьке порівняння з `channel_pool_add`,
не змішуючи з runlist.

## Ukrainian one-liner

П'ять call-site `uvm_channel_manager_create` передають батьківський об'єкт у `rdi`
і слот `+0x19f8` у `rsi`; `+0x1e0` належить першому полю батька, а не менеджеру —
RM-семантика лишається UNPROVEN.
