# 40 — REA P1: напрямок UUID через `nvUvmInterfaceGetGpuInfo`

Продовження [`docs/38`](38-rea-p1-register-gpu-uuid-chain.md). Там найменшим
кроком було перевірити, чи `nvUvmInterfaceGetGpuInfo` формує UUID. Відповідь:
**ні** — він споживає UUID як перший аргумент. Це закриває цю гілку й лишає
`BDF ↔ RM gpu_id` недоведеним.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | docs/35–38: BTF-типи, call-site `add_gpu`, ланцюг ioctl → `add_gpu` | не повторювати |
| `PARTIAL` | docs/38 §6: `nvUvmInterfaceGetGpuInfo` як можливе джерело UUID | цей звіт, відповідь «ні» |
| `UPSTREAM_EXISTS` | Nouveau/NVKM/NVK | implementation authority |
| `UNIQUE_GAP` | напрямок UUID на межі UVM ↔ RM у shipped-артефактах | цей звіт |

Pin-и v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract, ABI-pin і
asm-first контракт не змінено.

## 1. Артефакти, інструменти, мапа адрес

| Артефакт | SHA-256 |
|---|---|
| `nvidia-uvm.ko` | `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` |
| `nvidia.ko` | `95c5fa5ab0546ee40842cda2ec20ea3ec1e196a5afee1580944ecae2ffc75bbe` |

Інструменти: REA `execute_rizin_command` (`rizin 0.9.1`, provider version
`null`), GNU `readelf`/`objdump` (`2.47.50.20261021`).

**Важливо:** база Rizin різна для двох `.ko`, бо різна file offset `.text`:

- `nvidia-uvm.ko`: `Rizin = 0x08004660 + ELF vaddr`
  (`add_gpu` ELF `0x17ac0` → `0x0801c120`).
- `nvidia.ko`: `Rizin = 0x080028e0 + ELF vaddr`
  (`nvUvmInterfaceGetGpuInfo` ELF `0x1d6a0` → file offset `0x1ff80` →
  `0x0801ff80`; `rm_gpu_ops_get_gpu_info` ELF `0xda0510` → file offset
  `0xda2df0` → `0x08da2df0`).

Raw witness:
[`evidence/rea-20261128/gpu-info-uuid-direction.txt`](../evidence/rea-20261128/gpu-info-uuid-direction.txt),
SHA-256 `2824dbfea882db2b5b9396065ea638d7617d2fd5a7450e9901a525ae3b294d5b`.
Evidence bundle: `evidence/rea-20261128/evidence-p1-gpu-info-uuid.json`,
159 records, SHA-256 `912ec870d3615761dc12af59b2b4163ccfa0f147ee8350e73c5b00a6c32fc67c`.

Ключові Evidence IDs: `ev_0161857e…`, `ev_85119b22…`, `ev_580d64fc…`,
`ev_d35da1bb…`, `ev_2efe1290…`, `ev_41442471…`, `ev_658020eb…`.

## 2. `uvm_gpu_retain_by_uuid`: UUID йде **в** `GetGpuInfo`

У `uvm_gpu_retain_by_uuid @0x0801e950` (ELF `0x1a2f0`):

1. `0x0801e96a`: `mov r12, rdi` — UUID від `uvm_va_space_register_gpu`
   ([docs/38](38-rea-p1-register-gpu-uuid-chain.md)).
2. `0x0801e9ed`–`0x0801e9f8`: `uvm_parent_gpu_get_by_uuid_locked(rdi=r12)`.
3. `0x0801ea05`–`0x0801ea10`: `lea rsi,[rsp+0x08]`; `mov rdx,rbx`
   (zeroed allocation `0xf0`); `mov rdi,r12`;
   `call nvUvmInterfaceGetGpuInfo`.
4. Другий виклик — `0x0801eadb` (Rizin; ELF relocation `0x1a47c` → Rizin
   `0x0801eadc`), знову з `rdi=r12`. Підтверджено Evidence
   `ev_580d64fc…` (`pd 14 @ 0x0801ead0`).

Перерахунок relocation-ів у межах функції дав рівно два записи на
`nvUvmInterfaceGetGpuInfo` (`0x1a3b1`, `0x1a47c`), один
`uvm_parent_gpu_get_by_uuid_locked` (`0x1a399`) і один
`nvUvmInterfaceRegisterGpu` (`0x1a414`). Це перерахунок relocation-ів, не
absence-proof для непрямих викликів.

Після виклику код перевіряє `rbx+0x84` та `rbx+0x88` — тобто результат лежить
в окремому output-об'єкті, а не в UUID-слоті, який `add_gpu` читає з
`[rbp-0x118]`.

**Статус: `statically proven`.** Гіпотеза «`nvUvmInterfaceGetGpuInfo` генерує
UUID» — **`retracted hypothesis`** (хибне читання напрямку аргументів).

## 3. `nvidia.ko`: інтерфейс forwarding-ить UUID у RM

`nvUvmInterfaceGetGpuInfo @0x0801ff80` (ELF `0x1d6a0`):

- `rbx = rdi`, `rbp = rsi`, `r12 = rdx`.
- `rm_is_altstack_in_use`; обидві гілки (`jmp @0x0801ffb6` і
  `call @0x0801fff2`) ведуть до `rm_gpu_ops_get_gpu_info @0x08da2df0`.
- У гілку з altstack `mov rsi,rbx` знову передає початковий перший аргумент.

`rm_gpu_ops_get_gpu_info @0x08da2df0` (ELF `0xda0510`) зсуває аргументи й
викликає `_nv046828rm @0x080e0c30`. Отже початковий UUID з UVM forwarded як
перший аргумент RM-helper-а.

**Статус: `statically proven`** для самого факту forwarding-у. **Не доведено**,
що цей RM-helper пов'язує UUID з PCI BDF: `BDF ↔ RM gpu_id` лишається
`UNPROVEN`. Жодного RM-ioctl чи MMIO не виконувалось.

## 4. Помилка адреси (retracted observation)

window `pd 22 @ 0x08da4b70` (Evidence `ev_b6fbe1d6…`) потрапив у
`os_alloc_mem`-шлях, а не в `rm_gpu_ops_get_gpu_info`, бо до `nvidia.ko` було
застосовано базу `nvidia-uvm.ko` (`0x08004660`). Правильна адреса —
`0x08da2df0`, взята з `is~rm_gpu_ops_get_gpu_info`. Хибне вікно позначено як
`retracted observation`; висновки з нього не витягувались.

## 5. Статуси й межі

| Твердження | Статус |
|---|---|
| Ланцюг ioctl → `uvm_va_space_register_gpu` → `uvm_gpu_retain_by_uuid` → `add_gpu` | `statically proven` (docs/38) |
| `[rbp-0x118]` у гілці `r8==0` = початковий `rdi` | `statically proven` (docs/38) |
| UUID — вхідний аргумент `nvUvmInterfaceGetGpuInfo`, не його вихід | **`statically proven`** |
| `nvUvmInterfaceGetGpuInfo` як джерело UUID | **`retracted hypothesis`** |
| `nvidia.ko` forwarded UUID у `rm_gpu_ops_get_gpu_info` → `_nv046828rm` | **`statically proven`** |
| Хто заповнює UUID у userspace; `BDF ↔ RM gpu_id`; RM class/runlist/notifier/fence | **`UNPROVEN`** |
| BOOT0 / `0x137000A1` | `UNPROVEN` / `string-only` |
| MMIO, RM-ioctl, GPU compute, PR #21 | **`NOT RUN`** |

## 6. Unanswered question і найменший крок

**Unanswered:** хто саме в userspace заповнює перше поле ioctl-параметра UUID
і чи походить воно від RM GPU info / PCI BDF.

**Найменший крок:** у shipped userspace-бібліотеці NVIDIA (не в `.ko`) знайти
за relocation-ім'ям `UvmRegisterGpu`/ioctl-шлях і перевірити, чи формується
це поле з RM `gpu_id`. Без MMIO, без RM-запитів, без vendor source. Якщо
тарґет недоступний — залишити `UNPROVEN` з `coverage limitation`, не
екстраполювати.

## Ukrainian one-liner

У shipped `nvidia-uvm.ko` і `nvidia.ko` доведено, що UUID **йде в**
`nvUvmInterfaceGetGpuInfo` як перший аргумент і далі forwarded у RM-helper;
він не генерується цією функцією, а `BDF ↔ RM gpu_id` лишається `UNPROVEN`.
