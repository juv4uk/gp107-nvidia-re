# 38 — REA P1: ланцюг UUID від ioctl до `add_gpu`

Продовження [`docs/37`](37-rea-p1-add-gpu-call-sites.md). Там лишилося два
питання: звідки береться UUID, який `uvm_gpu_retain_by_uuid` передає в
`add_gpu`, і чи справді `[rbp-0x118]` у гілці `r8==0` містить початковий
`rdi`. Обидва закриті на shipped-артефакті без заліза.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | docs/35–37: BTF-типи, call-site `add_gpu`, роль `rdi` на першому з них | не повторювати |
| `PARTIAL` | docs/37 §7: `[rbp-0x118]` і походження UUID — `UNPROVEN` | цей звіт |
| `UPSTREAM_EXISTS` | Nouveau/NVKM/NVK | implementation authority |
| `UNIQUE_GAP` | ланцюг ioctl → `uvm_va_space_register_gpu` → `uvm_gpu_retain_by_uuid` → `add_gpu` у пропрієтарному `.ko` | цей звіт |

Pin-и v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract, ABI-pin і
asm-first контракт не змінено.

## 1. Артефакти й інструменти

| Поле | Значення |
|---|---|
| REA target | `/tmp/opencode/rea-nvidia-uvm/nvidia-uvm.ko`, SHA-256 `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` |
| Raw witness | [`evidence/rea-20261128/register-gpu-uuid-chain.txt`](../evidence/rea-20261128/register-gpu-uuid-chain.txt) |
| REA bundle | `evidence/rea-20261128/evidence-p1-register-gpu-chain.json` |
| Інструменти | REA `execute_rizin_command` (`rizin 0.9.1`, provider version `null`), GNU `objdump`/`readelf` `2.47.50.20261021` |

Мапа адрес: `Rizin = 0x08004660 + ELF .text VMA = 0x08000000 + file offset`.
Це підтверджено таблицею символів: `add_gpu` ELF `0x17ac0` → `0x0801c120`,
`uvm_gpu_retain_by_uuid` ELF `0x1a2f0` → `0x0801e950`.

Ключові Evidence ID: `ev_ea5ef805…` (`pd 45 @ 0x080204c0`),
`ev_b71903e5…` (`pd 80 @ 0x080259d0`), `ev_56ca57c3…`
(`pd 40 @ 0x08025a10`), `ev_a050e97c…`, `ev_e68b38ab…`, `ev_e218f83a…`,
`ev_3a72c27e…`, `ev_90da4b74…`, `ev_bbfbbf26…`.

## 2. Ланцюг викликів

| Крок | Адреса / функція | Що доведено | Статус |
|---|---|---|---|
| 1 | `uvm_api_register_gpu @0x080204c0` | `uvm_fd_get_type(rsi, 2) → rax`; потім `uvm_va_space_register_gpu(rdi=rax, rsi=rbx, rdx=&local, rcx=rbx+0x10, r8=rbx+0x14, r9=&local)` | `statically proven` |
| 2 | `uvm_va_space_register_gpu @0x080259d0` | `mov rdi,rsi`; `mov rsi,rdx`; `call uvm_gpu_retain_by_uuid @0x08025a2a` — arg2 стає arg1 | `statically proven` |
| 3 | `uvm_gpu_retain_by_uuid @0x0801e950` | `mov r12,rdi`; `mov rdi,r12`; `call uvm_parent_gpu_get_by_uuid_locked`, де `uvm_uuid_eq(&parent->uuid, rdi)` | `statically proven` |
| 4 | `add_gpu @0x0801c120` | два прямі call-site з docs/37 | `statically proven` |
| 5 | userspace, який будує структуру ioctl-параметра | у shipped `.ko` відсутній | `UNPROVEN` |

Єдиний relocation на `uvm_va_space_register_gpu` — `0x1bece` (`uvm_api_register_gpu`),
єдиний relocation на `uvm_gpu_retain_by_uuid` — `0x213cb`
(`uvm_va_space_register_gpu`). Прямих `jmp` до цих символів немає.

## 3. Звідки береться UUID

У `uvm_api_register_gpu`:

- `rbx = arg1` (`0x080204ce`).
- `uvm_uuid_copy(dst=rbx, src=&[rsp+0x20])` після успішної реєстрації
  (`0x0802054f`–`0x0802055b`) — кінцевий UUID пишеться назад у структуру
  параметра.
- `rbx+0x10`, `rbx+0x14`, `rbx+0x18`, `rbx+0x20` передаються далі як
  додаткові поля того самого параметра.

Отже UUID, який далі йде через `uvm_gpu_retain_by_uuid` у `add_gpu`, — це
перше поле структури параметра ioctl. Хто саме в userspace заповнює це поле й чи
походить воно від RM GPU info / PCI BDF — з цього артефакту **не доведено**
(`UNPROVEN`). `BDF ↔ RM gpu_id` лишається `UNPROVEN`.

## 4. Закриття `[rbp-0x118]`

У `add_gpu`:

- `0x0801c151`: `mov [rbp-0x118], rdi` — початковий перший аргумент.
- `0x0801c16d`–`0x0801c170`: `test r8,r8; jz 0x801c862` (ELF `0x17b10` → `0x18202`).
- Усі наступні записи в цей слот (`ELF 0x17c03`, `0x17cd2`, `0x17d0e`,
  `0x17e41`, `0x17ed2`, `0x17f45`, `0x1800f`, `0x1805a`, `0x180d8`) лежать
  на гілці `r8!=0`, яку цей `jz` оминає.
- `0x0801c862` (ELF `0x18202`) починає гілку `r8==0`; до `0x0801c899`
  (ELF `0x18239`) немає жодного запису в `[rbp-0x118]`.
- `0x0801c899`: `mov rsi,[rbp-0x118]`; `0x0801c8ba`: `lea rax,[r10+0x50]`;
  `0x0801c8be`: `mov rdi,rax`; `0x0801c8c8`: `uvm_uuid_copy` — тобто
  `&parent->uuid ← початковий rdi`.

Статус: **`statically proven`**. Питання з `docs/37 §7` закрите.

## 5. Статуси й межі

| Твердження | Статус |
|---|---|
| Ланцюг `uvm_api_register_gpu → uvm_va_space_register_gpu → uvm_gpu_retain_by_uuid → add_gpu` | **`statically proven`** |
| UUID у `add_gpu` (гілка `r8==0`) = перше поле параметра ioctl | **`statically proven`** |
| `[rbp-0x118]` на шляху `r8==0` = початковий `rdi` | **`statically proven`** |
| Походження UUID у userspace, `BDF ↔ RM gpu_id`, RM class/runlist/notifier/fence | **`UNPROVEN`** |
| BOOT0 / `0x137000A1` | `UNPROVEN` / `string-only` |
| MMIO, RM-ioctl, GPU compute, PR #21 | **`NOT RUN`** |

`axt` для проміжних символів не використовувався як absence-proof; тут
використано перерахунок relocation-ів і прямих викликів у межах відомих
symbol-range. Непрямі виклики через таблиці лишаються `UNPROVEN`.

## 6. Найменший наступний крок

Найменший крок — у shipped `nvidia.ko` (SHA `95c5fa5a…`) знайти
`nvUvmInterfaceGetGpuInfo` за relocation-ім'ям і перевірити, чи формує він
поле UUID, яке згодом потрапляє в ioctl-параметр. Без MMIO, без RM-запитів,
без vendor source.

## Ukrainian one-liner

У shipped `nvidia-uvm.ko` доведено ланцюг `uvm_api_register_gpu →
uvm_va_space_register_gpu → uvm_gpu_retain_by_uuid → add_gpu`; UUID береться з
першого поля ioctl-параметра, а `[rbp-0x118]` у гілці `r8==0` справді містить
початковий `rdi`.
