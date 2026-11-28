# 35 — REA P1: BTF-доведення типу батька `uvm_channel_manager_create`

Це продовження [`docs/34`](34-rea-p1-parent-object-and-test-context.md).
Там тип-назви лишались `interpretation`. Тут вони зняті з **BTF-метаданих
у тому ж shipped-артефакті** — без Ghidra-pseudocode, без vendor source,
без broad `/r` і без `izz~`.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | docs/23–28, 34: RM dispatch, call-site, `uvm_test_channel_sanity`, шлях до `g_uvm_global+0x28` | не повторювати |
| `PARTIAL` | docs/34: інструкції доведені, але назва типу й роль `rdi` — `interpretation`/`UNPROVEN` | цей звіт |
| `UPSTREAM_EXISTS` | Nouveau/NVKM/NVK channel manager | implementation authority, не реверсити |
| `UNIQUE_GAP` | BTF-доведення, що `+0x28` = `parent_gpus[]`, `+0x08` = `parent->gpus[]`, `+0x19f8` = `channel_manager`, і роль першого аргументу `add_gpu` у гілці `r8==0` | цей звіт |

Pin-и v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract, ABI-pin і
asm-first контракт [`docs/33`](33-asm-first-target-contract.md) не змінено.

### Виправлення інциденту з тарґетом (не приховано)

Під час BTF-даблпа я виконав `objcopy --dump-section .BTF=... <target>` без
явного output-файлу; `objcopy` перезаписав тарґет in-place і обрізав його
до 4662440 B (SHA `af3d233705fbbe2436a5af6aa3dba3a26a7e0c624d13ae6c80f9f27c137315af`).
Це виявлено з поля `subject.identity.sha256` у REA Evidence. Тарґет відновлено
з shipped `.ko.xz` до **`81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6`**,
4662893 B; усі нижче наведені REA-команди перезапущено на відновленому файлі,
їх вивід байтово збігається з попереднім. Bundle зі скороченим тарґетом видалено.
Це **`runtime-proven`** факт про помилку інструменту, не про артефакт.

## 1. Артефакти й інструменти

| Поле | Значення |
|---|---|
| Shipped artifact | `/lib/modules/7.2.15+kali-amd64/updates/dkms/nvidia-uvm.ko.xz`, SHA-256 `80132204f76981b2373baeb936866347e3c80e8527feb118bffe03f6adc10e8f` |
| Target | `/tmp/opencode/rea-nvidia-uvm/nvidia-uvm.ko`, SHA-256 `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` |
| BTF section | `.BTF`, SHA-256 `0de4d26929154f37cfc6c64f3482126fb06cd72430cc6716f61ff4995c9de845` |
| BTF layout dump | `evidence/rea-20261128/btf-uvm-type-layout.txt`, SHA-256 `b305ddcf413cdf60c7675364dfde3b7c6c18d7231ee37b20ccfef5fe90008e51` |
| REA bundle | `evidence/rea-20261128/evidence-p1-btf-parent-proof-restored.json`, 118 records, 4 unknown revisions, SHA-256 `41a6cf6eca784a6ddcb3a5ec333f7b119a20927ecba855a56c961fcae45b6a66` |
| Unknown | `unk_60e2b61cc14cb5c16774bf5bc277761da2726301ae73d05373cf6d060b104e92`, revision 4, `resolved` |
| Tools | `pahole 1.32` (BTF layout), REA `execute_rizin_command` / `rizin 0.9.1` (provider version `null`) |

Revision 4 того самого unknown змінює лише SHA нормалізованого dump-у BTF
(видалено зайві порожні рядки в кінці файлу); попередні ревізії збережені в
bundle. Зміст усіх REA-команд лишився незмінним.

Ключові REA Evidence (усі — `confidence=observed`, `authority=shipped-artifact`,
`artifact_sha256_after=81b215…`, `artifact_changed=false`, `output_truncated=false`):

| Evidence ID | Команда | Що дала |
|---|---|---|
| `ev_be767c0ebd6a2dcdd927d025eddbf5825a19cad1a938c5c77c8c11e2c0819725` | `is~add_gpu` | `add_gpu @ 0x0801c120`, 8055 B; `__pfx_add_gpu @ 0x0801c110` |
| `ev_c4f35f5400bf2ef9f11be44cc1fcdb7b89ac8cb4eede4540aa9be2dd0b083c7d` | `pd 36 @ 0x0801c120` | пролог: `r12=r8`, `r13d=esi`, `r14=rdx`, `rdi→[rbp-0x118]`; `alloc_gpu(0x1d98)`; `[rbx]=r12`, `[rbx+0x80]=r13d` |
| `ev_a9c16bc6e6becb8c367be75f5680e817cd4ecc876c4b081aa41f3400750d3dd4` | `pd 52 @ 0x0801c850` | `alloc_parent_gpu(0xc228)`; `rdi=&parent+0x50`, `rsi=[rbp-0x118]`, `uvm_uuid_copy` |
| `ev_7ae7fe3b4b76eca841cb9d998b86916a69b00025da97371e7a7a42054875f1c4` | `pD 8055 @ 0x0801c120~uuid_copy` | два виклики `uvm_uuid_copy` у межах `add_gpu`: `0x0801c293`, `0x0801c8c8` |
| `ev_3f09796a65ed0aa05d8aa6c1559791cd0d4a17ef6eeecbe1f49d6bc6b415ff3c` | `pd 24 @ 0x0801c280` | `rsi=[r14+0x40]`, `rdi=[rbx+0x08]`, `uvm_uuid_copy` у гілці `r8!=0` |
| `ev_9fd28374e20fe6fc1dc3ad8f545f43f2f9956f12d7bb123ec59278ec7a75b919` | `pd 52 @ 0x080bacc0` | `g_uvm_global+0x28 → parent → parent->gpus[r13] → +0x19f8 → create` |
| `ev_736980eac249f268aafb1c84a5db038e0379889945b56952c707804de0fc107a` | `iS. @ 0x08000dc8` | хит `/x 10c10108` належить `patchable_function_entries`, не виклику |
| `ev_a55f19619282a71e6567596ce479bc37b0bac1ff0602cab3824242d2f2026819` | `axt @ 0x0801c120` | порожньо; coverage limitation, не absence-proof |

## 2. BTF-карта типів (не `interpretation`)

З [`btf-uvm-type-layout.txt`](../evidence/rea-20261128/btf-uvm-type-layout.txt):

| BTF тип | Розмір | Поля, що збігаються з інструкціями |
|---|---|---|
| `uvm_global_struct` | 191128 (`0x2ea98`) | `parent_gpus[32]` @ 40 (`0x28`), тип `uvm_parent_gpu_t *`; `rm_session_handle` @ 296 (`0x128`) |
| `uvm_parent_gpu_struct` | 49704 (`0xc228`) | `num_retained_gpus` @ 4; `gpus[8]` @ 8, тип `uvm_gpu_t *`; `uuid` @ 80 (`0x50`) |
| `uvm_gpu_struct` | 7576 (`0x1d98`) | `parent` @ 0, тип `uvm_parent_gpu_t *`; `uuid` @ 8; `id` @ 128 (`0x80`); `retained_count` @ 120 (`0x78`); `channel_manager` @ 6648 (`0x19f8`), тип `uvm_channel_manager_t *` |
| `uvm_channel_manager_struct` | 2192 | `gpu` @ 0, тип `uvm_gpu_t *` |

Розміри 0x1d98 і 0xc228 з інструкцій `__uvm_kvmalloc_zero` збігаються з BTF
розмірами `uvm_gpu_struct` і `uvm_parent_gpu_struct` **побайтово**. Це робить
визначення типу об'єкта **`statically proven`**, а не здогадкою.

## 3. Зіставлення інструкцій із BTF

### Гілка `r8 != 0` — дочірній GPU

| Адреса | Інструкція | BTF-інтерпретація | Статус |
|---|---|---|---|
| `0x0801c182` | `mov edi, 0x1d98` | allocation `uvm_gpu_struct` | **statically proven** |
| `0x0801c1a9` | `mov [rbx], r12` | `gpu->parent = r8` (`uvm_parent_gpu_t *`) | **statically proven** |
| `0x0801c1af` | `mov [rbx+0x80], r13d` | `gpu->id = esi` | **statically proven** |
| `0x0801c1cf` | `mov [r12+r13*8+0x08], rbx` | `parent->gpus[esi & 7] = gpu` | **statically proven** |
| `0x0801c1d4` | `add dword [r12+0x04], 1` | `parent->num_retained_gpus++` | **statically proven** |
| `0x0801c288` | `mov rdi,[rbx+0x08]` | `&gpu->uuid` як dst `uvm_uuid_copy` | **statically proven** |
| `0x0801c284` | `mov rsi,[r14+0x40]` | джерело UUID з об'єкта в `rdx`; його тип лишається `UNPROVEN` | **statically proven** як інструкція |

### Гілка `r8 == 0` — батьківський GPU

| Адреса | Інструкція | BTF-інтерпретація | Статус |
|---|---|---|---|
| `0x0801c87f` | `mov edi, 0xc228` | allocation `uvm_parent_gpu_struct` | **statically proven** |
| `0x0801c8ba` | `lea rax,[r10+0x50]` | `&parent->uuid` | **statically proven** |
| `0x0801c899` | `mov rsi,[rbp-0x118]` | початковий `rdi` як src `uvm_uuid_copy` | **statically proven** |

Отже роль першого аргументу в гілці `r8==0` — **вказівник на UUID-джерело**
для `parent->uuid`. Повний прототип `add_gpu` лишається `UNPROVEN`, бо прямих
caller-ів знайдено немає.

### Тестовий шлях `uvm_channel_manager_create`

| Адреса | Інструкція | BTF-інтерпретація | Статус |
|---|---|---|---|
| `0x080bacc7` | `rax = [r14*8+0x810b0d0]` | `g_uvm_global.parent_gpus[r14]` (`uvm_parent_gpu_t *`) | **statically proven** |
| `0x080bacdc` | `r14 = [rax+r13*8+0x08]` | `parent->gpus[r13]` (`uvm_gpu_t *`) | **statically proven** |
| `0x080bacea` | `cmp qword [r14+0x78],1` | `gpu->retained_count == 1` | **statically proven** |
| `0x080bacf5` | `rax = [r14+0x19f8]` | `gpu->channel_manager` | **statically proven** |
| `0x080bad57` | `rdi = r14` | `uvm_gpu_t *gpu` | **statically proven** |
| `0x080bad50` | `rsi = &r14+0x19f8` | `uvm_channel_manager_t **out` | **statically proven** |

Це закриває питання, яке в `docs/34` було `interpretation`: батько для
`uvm_channel_manager_create` — **`uvm_gpu_t *`**, а не сам елемент
`parent_gpus[]`. Проміжний ланцюг: `parent_gpus[] → uvm_parent_gpu_t →
gpus[] → uvm_gpu_t`.

## 4. Що лишилося недоведеним

- Прямі caller-и `add_gpu`: `axt @ 0x0801c120` порожньо на відновленому
  тарґеті (**coverage limitation**, не absence-proof); `ir~add_gpu` дає лише
  PLT-виклики до інших функцій. `uvm_gpu_init @ 0x0801e100` приймає
  `uvm_peer_copy` (`strcmp "phys"/"virt"`) і викликає `uvm_hal_init_table`,
  тобто не є цим caller-ом.
- Хит `/x 10c10108 @ 0x08000dc8` — `patchable_function_entries`,
  **rejected observation**, не call-site.
- RM class/runlist/notifier/fence, `+0x1e0` як RM handle, `BOOT0`,
  `0x137000A1`, `BDF ↔ RM gpu_id`, причина NVK↔NVIDIA — `UNPROVEN` /
  `string-only` / `PARTIAL` без змін.
- Фізичний MMIO, RM-запити, GPU compute, PR #21 — `NOT RUN`.

## 5. Статуси

| Твердження | Статус |
|---|---|
| `g_uvm_global+0x28` = `parent_gpus[32]`, елемент `uvm_parent_gpu_t *` | **statically proven** (BTF + REA) |
| `parent+0x08` = `gpus[8]`, елемент `uvm_gpu_t *` | **statically proven** (BTF + REA) |
| `gpu+0x19f8` = `channel_manager`, `manager+0x0` = `gpu` | **statically proven** (BTF + REA) |
| Розміри allocation `0x1d98`/`0xc228` відповідають `uvm_gpu_t`/`uvm_parent_gpu_t` | **statically proven** |
| Перший аргумент `add_gpu` у гілці `r8==0` = UUID-джерело | **statically proven** |
| Повний прототип `add_gpu` і його caller-и | **`UNPROVEN`** |
| RM-семантика полів | **`interpretation`/`UNPROVEN`** |

## 6. Найменший наступний крок

Найменший крок — знайти прямий `call` на `0x0801c120` цільовими вікнами в
межах уже відомих symbol-range (наприклад, навколо функцій із BTF-іменами,
пов'язаними з GPU registration), після чого звірити перший аргумент безпосередньо
на `call`-site. Без broad `/r`, без MMIO, без RM-запитів.

## Ukrainian one-liner

BTF з того самого shipped `nvidia-uvm.ko` доводить ланцюг
`g_uvm_global+0x28 → uvm_parent_gpu_t → +0x08 → uvm_gpu_t → +0x19f8 →
uvm_channel_manager`; роль першого аргументу `add_gpu` у гілці `r8==0` —
UUID-джерело, а caller-и лишаються `UNPROVEN`.
