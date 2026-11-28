# 37 — REA P1: прямі caller-и `add_gpu` і роль першого аргументу

Продовження [`docs/35`](35-rea-p1-btf-type-proof.md). Там caller-и `add_gpu`
були `UNPROVEN`, а `axt @ 0x0801c120` порожнім. Тут вони знайдені
перерахунком усіх прямих `call`/`jmp` до символу в shipped-артефакті, а роль
першого аргументу перевірена безпосередньо на call-site.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | docs/23–28, 34–36: dispatch, typed-ланцюг BTF, тестовий шлях, pairing артефакта | не повторювати |
| `PARTIAL` | docs/35: роль `rdi` в гілці `r8==0` доведена всередині `add_gpu`, але call-site невідомі | цей звіт |
| `UPSTREAM_EXISTS` | Nouveau/NVKM/NVK channel manager | implementation authority, не реверсити |
| `UNIQUE_GAP` | перерахунок прямих call-site `add_gpu` і звірка `rdi` на них | цей звіт |

Pin-и v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract, ABI-pin і
asm-first контракт [`docs/33`](33-asm-first-target-contract.md) не змінено.

## 1. Артефакти й інструменти

| Поле | Значення |
|---|---|
| Shipped artifact | `/lib/modules/7.2.15+kali-amd64/updates/dkms/nvidia-uvm.ko.xz`, SHA-256 `80132204f76981b2373baeb936866347e3c80e8527feb118bffe03f6adc10e8f` |
| REA target | `/tmp/opencode/rea-nvidia-uvm/nvidia-uvm.ko`, SHA-256 `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6`, 4662893 B |
| Raw witness | [`evidence/rea-20261128/add-gpu-call-sites.txt`](../evidence/rea-20261128/add-gpu-call-sites.txt) |
| REA bundle | `evidence/rea-20261128/evidence-p1-add-gpu-call-sites.json`, 136 records, 4 unknown revisions |
| Інструменти | REA `execute_rizin_command` (`rizin 0.9.1 @ linux-x86-64`, provider version `null`), GNU `objdump`/`readelf` (Binutils `2.47.50.20261021`) |

Усі нові REA-записи: `confidence=observed`, `authority=shipped-artifact`,
`artifact_sha256_after=81b215…`, `artifact_changed=false`,
`completion_status=complete`.

Ключові Evidence ID:

| Evidence ID | Команда | Що дала |
|---|---|---|
| `ev_e218f83a26c62f546e2e34aa84eeaef58a0525deaddebfb852a20d2cc6f65532` | `pd 60 @ 0x0801c120` | аргументи `add_gpu`: `r12=r8`, `r13d=esi`, `r14=rdx`, `rdi→[rbp-0x118]`; гілка `r8==0` |
| `ev_aec8bacd4f06ef2dab847853186420cf4223faf09c3389d497297169f1063d45` | `pd 75 @ 0x0801e950` | пролог `uvm_gpu_retain_by_uuid`, спростування хибних адрес |
| `ev_a050e97cc2571910067d049b059a52c9c0cd4331d6e2f2af148e9088ba7c5654` | `pd 120 @ 0x0801e950` | `mov r12,rdi`; `mov rdi,r12` перед `uvm_parent_gpu_get_by_uuid_locked`; перший `call sym.add_gpu` |
| `ev_eaa459a1a6ab6f2730a55f3fc11d4ede23e01ab3081951aead4a5dac069a2563` | `pd 60 @ 0x0801eb10` | call-site 1 `0x0801eb42`, `r8=0`, `rdi=r12` |
| `ev_efd11d06e5968cfa22e9e9890f2966bbfd537afb02b2d91011550ace517ee8cd` | `pd 50 @ 0x0801ebc0` | call-site 2 `0x0801ebf7`, `r8=rbp`, `rdi=r12` |
| `ev_e68b38ab8f495592e47764ba6c0395a390be0b181572f434dd10ea97be598b0d` | `pd 45 @ 0x0801e370` | `uvm_uuid_eq(&parent->uuid, rdi)` — доведення, що перший аргумент caller-а є UUID-джерелом |
| `ev_9b9f9d40c8f277d2102a93aec74fe7d5caaded8643e20269edc712de0c7b9275` | `pd 40 @ 0x0801c8c0` | спростування «рекурсивного call» на `0x0801c8e5` |
| `ev_299e0e9ca0f8b9d45560f401c94e8e481bec253f484650553789c6776397a997` | `/x 4df9ffff @ …` | rejects: `ERROR: search: failed to read at 0x08147e08` |
| `ev_a55f19619282a71e6567596ce479bc37b0bac1ff0602cab3824242d2f2026819` | `axt @ 0x0801c120` | порожньо; coverage limitation, не absence-proof |

## 2. Виправлення хибних прочитань (retracted, не Evidence)

У попередньому усному звіті цієї сесії були помилково названі call-site-и
`0x0801e9e9`/`0x0801ea10`, «рекурсивний виклик» на `0x0801c8e5`, три збіги
`/x 4df9ffff` і роль `rdi = &parent->gpus`. Свіжі command-observation
спростовують це:

- `0x0801e9e9` — `jz 0x801eb90`; `0x0801ea10` — `call nvUvmInterfaceGetGpuInfo`.
- `0x0801c8e5` — `lea rdi,[r10+0xc0e8]`; жодного `call` там немає.
- `/x 4df9ffff @ 0x08000000+0x1000000` завершився помилкою читання, збігів не дав.
- У `add_gpu` базою масиву `parent->gpus[]` є **`r8`**, а не `rdi`
  (`mov r12,r8`; `mov [r12+r13*8+0x08],rbx`). `rdi` зберігається в
  `[rbp-0x118]` і в гілці `r8==0` є UUID-джерелом.
- BTF-назва поля `gpu+0x19f8` — `channel_manager` (не `gpu`);
  `uvm_channel_manager_struct.gpu @ 0` — зворотний вказівник.

Це **`retracted observation`**, не новий факт про артефакт. Хибні твердження
не були записані в `docs/35`; тут вони явно позначені як спроствовані.

## 3. Перерахунок прямих викликів

Команда (targeted, за відомим символом, без broad `/r`, `/c`, `izz~`):

```
objdump -d --no-show-raw-insn <target> | grep -E '(call|jmp)[[:space:]].*<add_gpu>'
```

Результат — **рівно два** рядки: `1a4e2: call 17ac0 <add_gpu>` і
`1a597: call 17ac0 <add_gpu>`. `readelf -rW … | grep -i add_gpu` не показує
жодного relocation на `add_gpu` (усі збіги — інші символи з `add_gpu` у назві).

Мапа адрес (`statically proven` з `readelf -SW`): `.text` file offset `0x4660`,
ELF `add_gpu=0x17ac0` (8055 B) → Rizin `0x0801c120`; ELF
`uvm_gpu_retain_by_uuid=0x1a2f0` (740 B) → Rizin `0x0801e950`. Отже обидва
call-site лежать усередині `uvm_gpu_retain_by_uuid`:

| ELF адреса | Rizin адреса | Функція |
|---|---|---|
| `0x1a4e2` | `0x0801eb42` | `uvm_gpu_retain_by_uuid` |
| `0x1a597` | `0x0801ebf7` | `uvm_gpu_retain_by_uuid` |

Статус: **`statically proven`** для множини прямих `call`/`jmp` у
дизасембльованих код-секціях `.ko`. Порожній `axt` лишається coverage
limitation, не absence-proof. Непрямі виклики через таблиці та альтернативні механізми інструкцій —
`UNPROVEN`.

## 4. Call-site 1: `0x0801eb42`, гілка створення батька

```
0x0801eb1a  cmp qword [rbp*8+0x810b0d0], 0x00   ; g_uvm_global.parent_gpus[i]
0x0801eb23  jnz 0x801eafe
0x0801eb2e  xor r8d, r8d                         ; parent = NULL
0x0801eb31  push rax
0x0801eb32  lea esi, [r13*8+0x01]                ; gpu id = parent_index*8+1
0x0801eb3a  mov rdi, r12
0x0801eb3d  lea rcx, [rsp+0x18]
0x0801eb42  call sym.add_gpu
```

`r12 = rdi` з пролога `uvm_gpu_retain_by_uuid` (`0x0801e96a`). Той самий
`r12` передається першим аргументом у `uvm_parent_gpu_get_by_uuid_locked`
(`0x0801e9ed`), де він порівнюється з `&parent->uuid` через `uvm_uuid_eq`
(`0x0801e3c1`–`0x0801e3c8`). Отже `rdi` на call-site — **UUID-джерело**.

У `add_gpu` `r8==0` обирає гілку `alloc 0xc228` (`uvm_parent_gpu_t`), а
`[rbp-0x118]` (вхідний `rdi`) є `src` для `uvm_uuid_copy` у `parent->uuid`
(`0x0801c899`, `0x0801c8ba`, `0x0801c8c8`). Це замикає ланцюг
call-site → аргумент → використання: **`statically proven`**.

## 5. Call-site 2: `0x0801ebf7`, гілка вже наявного батька

```
0x0801ebd8  mov edx, [rbp+0x1c8]
0x0801ebde  mov r9, r15
0x0801ebe1  mov r8, rbp                          ; parent = get_by_uuid result
0x0801ebe4  mov rdi, r12
0x0801ebe7  lea rcx, [rsp+0x10]
0x0801ebec  lea esi, [rax+rdx*8-0x07]
0x0801ebf0  mov rax, rsp
0x0801ebf3  mov rdx, rbx
0x0801ebf6  push rax
0x0801ebf7  call sym.add_gpu
```

`r8` = знайдений `uvm_parent_gpu_t`, `rdi` = той самий UUID-вказівник `r12`.
У гілці `r8!=0` `add_gpu` копіює UUID з `[rdx+0x40]`, тому семантичне
використання саме `rdi` у цій гілці — **`UNPROVEN`**; тотожність значення
`rdi` з call-site 1 — **`statically proven`**.

## 6. Статуси

| Твердження | Статус |
|---|---|
| Прямі call-site `add_gpu`: `0x0801eb42`, `0x0801ebf7`, обидва в `uvm_gpu_retain_by_uuid` | **`statically proven`** |
| Рівно два прямі `call`/`jmp` на `add_gpu` у дизасембльованих код-секціях `.ko` | **`statically proven`** |
| `r8` — батько/база `parent->gpus[]`; `esi` — gpu id; `rdi` — перший аргумент | **`statically proven`** |
| Call-site 1: `rdi` = UUID-джерело, яке потім іде в `parent->uuid` | **`statically proven`** |
| Call-site 2: `rdi` = той самий UUID-вказівник; у гілці `r8!=0` слот `[rbp-0x118]` перевикористовується, початковий `rdi` не використовується | **`statically proven`** ([`docs/38`](38-rea-p1-register-gpu-uuid-chain.md)) |
| Повний прототип `add_gpu` (типи всіх 7 аргументів і повернення) | **`UNPROVEN`** |
| `axt @ 0x0801c120` порожньо | **coverage limitation**, не absence-proof |
| BOOT0 / `0x137000A1` / RM class-runlist-notifier-fence / BDF↔RM gpu_id | `UNPROVEN` / `string-only` без змін |
| MMIO, RM-ioctl, GPU compute, PR #21 | **`NOT RUN`** |

## 7. Безвідповідальне питання й найменший крок

Це питання закрите в [`docs/38`](38-rea-p1-register-gpu-uuid-chain.md):
усі записи в `[rbp-0x118]` лежать на гілці `r8!=0`, яку `jz @0x0801c170`
оминає, тому на шляху `r8==0` слот містить початковий `rdi`.

Наступний крок виконано в [`docs/40`](40-rea-p1-gpu-info-uuid-direction.md):
`nvUvmInterfaceGetGpuInfo` споживає UUID, а не генерує його; гіпотеза
`retracted hypothesis`. Подальше джерело UUID у userspace і `BDF ↔ RM gpu_id`
лишаються `UNPROVEN`.

## Ukrainian one-liner

У shipped `nvidia-uvm.ko` знайдено рівно два прямі виклики `add_gpu` —
`0x0801eb42` і `0x0801ebf7` в `uvm_gpu_retain_by_uuid`; на першому
`rdi` доведено як UUID-джерело для `parent->uuid`, а базою `parent->gpus[]`
є `r8`, не `rdi`.
