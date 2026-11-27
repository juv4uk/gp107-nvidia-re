# 27 — REA P1: FIELD `+0x1e0` МАЄ РІЗНІ БАЗИ В `nvidia-uvm.ko`

Наступний найменший крок після `docs/26`: не шукати broad-посилання, а
перевірити, чи однаковий offset `+0x1e0` означає одне поле. Відповідь — **ні**:
у двох сусідніх функціях це різні об'єкти. Це прямо спростовує спокусу
назвати його «RM handle» без(store-site) доказів.

## 0. Triage перед завданням

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | docs/23/24/25/26: function-level карти, RM dispatch window, call-site, enum-розгалуження, виправлення disalignment | не повторювати |
| `PARTIAL` | docs/26: `[rax+0x1e0]` у `channel_pool_add`; typeof field = `UNPROVEN` | ціль цього звіту |
| `UPSTREAM_EXISTS` | Nouveau/NVKM UVM-еквіваленти, NVK/NAK | implementation authority, не реверсити |
| `UNIQUE_GAP` | хто саме є базою для `+0x1e0` у `channel_pool_add` і `uvm_channel_manager_create` | ціль цього звіту |

Перед запуском перевірено індекс docs/01–26. Issue #3/#18/#28 через GitHub API
не перевірялись: `gh api rate_limit` показав `remaining=0`, reset
`2026-11-27T23:12:11 UTC`; це **coverage limitation**, а не підтвердження,
що там немає нових вказівок. Upstream не змінено. Pin-и v8/v9, SENS, CML,
`wsm-os-lisp`, ADR, target contract і ABI не чіпались.

## 1. Тарґет, tool, Evidence

| Поле | Значення |
|---|---|
| Shipped artifact | `/lib/modules/7.2.15+kali-amd64/updates/dkms/nvidia-uvm.ko.xz`, SHA-256 `80132204f76981b2373baeb936866347e3c80e8527feb118bffe03f6adc10e8f` |
| Target | `/tmp/opencode/rea-nvidia-uvm/nvidia-uvm.ko`, SHA-256 `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` |
| Tool | REA `execute_rizin_command` (Rizin), executable `rizin`; provider version не підтверджено; Ghidra не відкривався |
| Bundle | `evidence/rea-20261128/evidence-p1-uvm-object-offsets.json`, 44 record (17 для цього target), SHA-256 `feab9e6c9740caeb530747c9f5ab17e8f013585714bc0b7c7035fda0e131fd99` |

Ключові Evidence ID:

- `ev_0e69c8bd0bf6acc5404b29258b5337055f30f4f08ef47b2b3ca3654c89a985c3` —
  `is~0x08036`: `uvm_channel_manager_create @ 0x08036580`, 2333 B.
- `ev_92b42e3ed745b8a4f329d4dde03d1161d1fccb079890847110d5111b1f1dcee7`,
  `ev_abf245596f9492a890f594830c0ab609ce8a55df7a38530587b6cd7eb9c2778c` —
  лінійна disassembly від entry `0x08036580`.
- `ev_3f9de99c323fa009fab6c0b7132e79f5152ca93e595541a59baafff63370befe`,
  `ev_85a6c60b304e90601d96418caced27737010bde3b04846f29c02c1363b6069b8` —
  Allocation і store у новий manager-об'єкт.
- `ev_08922fa282538b37a1d9d011aa5cdf6f667b3c6aa15196d84f6740fc67732ad6` —
  спроба `ao 24 @ 0x080361c0` дала `invalid`/неправдоподібні opcode:місце
  виходу з синхронізації, **не доказ** про код у цій точці.

## 2. Що таке `uvm_channel_manager_create`

Enclosing function: `0x08036580`, 2333 B, `GLOBAL FUNC` (**statically proven**).

| Адреса | Факт | Статус |
|---|---|---|
| `0x080365a1` | `rbp = rdi` (перший аргумент manager-create) | `statically proven` |
| `0x080365a4`–`0x080365ca` | `__uvm_kvmalloc_zero(edi=0x890, rsi="nvidia-uvm/uvm_channel.c", …)`; рядок — `string-only` шлях вихідного файлу з бінарника | `statically proven` для констант/виклику |
| `0x080365e3` | `r13 = rax` (новий об'єкт), `[r12] = rax`, `[rax] = rbp` | `statically proven` |
| `0x080365dd`, `0x080365ff`, `0x08036624` | `esi = [uvm_channel_num_gpfifo_entries]`; clamp `<=0x1f → 0x20`, `>0x100000 → 0x100000`, інакше power-of-2 перевірка; `[r13+0x878] = …` | `statically proven`; global value `0x400` — дані ELF-образа, не runtime |
| `0x08036648`–`0x08036679` | `[rbp+0x90] == 0` guard, `[r13+0x87c]=1`, `[r13+0x880]=0x100000001`, `uvm_pushbuffer_create(r13, &r13+8)` | `statically proven` |

Важливо: `r13` — **нововиділений manager-об'єкт**; `rbp` — **його перший
аргумент**. Це різні рівні, хоч обидва беруть участь у `[rax] = rbp`.

## 3. Хто справді має `+0x1e0`

### 3.1. `uvm_channel_manager_create` → `nvUvmInterfaceQueryCopyEnginesCaps`

- `0x08036703`: `rdx = [r13]` — тобто збережений `rbp`;
- `0x08036707`: `rax = [rdx]` — **другий рівень покажчика**;
- `0x0803670a`: `cmp byte [rax+0xc16d], 0` → `jnz 0x8036a12`;
- `0x08036717`: `rdi = [rax+0x1e0]`, `rsi = r8` (buffer з
  `__uvm_kvmalloc_zero(edi=0x200, edx=0xc60, "nvidia-uvm/uvm_channel.c")`);
- `0x08036725`: `call reloc.target.nvUvmInterfaceQueryCopyEnginesCaps`.

Все вище — **statically proven** за relocation + лінійною disassembly від
справжнього entry. `rax` тут **не** `r13`; отже `+0x1e0` належить об'єкту,
на який вказує `[[r13]]`, а не новому manager-об'єкту.

### 3.2. `channel_pool_add` → `nvUvmInterfacePagingChannelAllocate`

- `0x08035e64`: `cmp byte [rax+0xc16d], 0`;
- `0x08035e71`: `rdi = [rax+0x1e0]`;
- `0x08035e7d`: `call nvUvmInterfacePagingChannelAllocate` (docs/26).

### 3.3. Інший `+0x1e0` — байтовий store

У тому самому `channel_pool_add`, `0x08035a97`: `mov byte [rbp+0x1e0], 0x00`
після `snprintf(..., esi=0x40, ...)`. Це **інша база** (`rbp`) і **інша ширина**
(1 байт проти 8 у qword read). Ототожнювати його з qword-полем із 3.1/3.2
**заборонено** без доведення, що `rbp == rax` у тій самій гілці.
Таке доведення відсутнє: status **`UNPROVEN`**.

Спроба `ao` коло `0x080361de`/`0x080361c0` не дала надійних меж, тому
висновки про `rbp` у тих гілках не робились.

## 4. Підсумкова таблиця

| Твердження | Статус |
|---|---|
| `uvm_channel_manager_create` виділяє 0x890-байтовий об'єкт і зберігає в ньому перший аргумент | `statically proven` |
| `+0x878`, `+0x87c`, `+0x880` — реальні store-адреси в manager-об'єкт | `statically proven` як інструкції |
| `+0x1e0` читається як qword від `[[r13]]` перед `QueryCopyEnginesCaps` і від `[rax]` перед `PagingChannelAllocate` | `statically proven` |
| `mov byte [rbp+0x1e0],0` — той самий field | `UNPROVEN` (різні base/width) |
| `+0x1e0` — RM handle, а `+0xc16d` — feature flag | `interpretation`, не факт |
| `kchannelBindToRunlist_IMPL`, notifier/fence, BOOT0, причина NVK/NVIDIA gap | `UNPROVEN`/`string-only` без змін |

## 5. Unanswered question і наступний найменший крок

**Питання:** який об'єкт прихований за `[[r13]]` у `uvm_channel_manager_create`
і чи той самий він у `channel_pool_add`?

**Наступний крок:** у межах уже виділених вікон `uvm_channel_manager_create`
перевірити `mov [rax], rbp` та перший аргумент (`rdi`) самої функції через
вузький `pd` від entry (без `/r`, без `izz~`), потім порівняти з
`channel_pool_add(rdi=...)` call-site. Жодного припущення про структуру RM.

Не робилось: MMIO/BAR, `nva`, RM-ioctl, reboot, GPU compute, PR #21 executable,
Ghidra-pseudocode, vendor source, transfer коду, release/tag/publish,
зміни pin-ів/SENS/CML/ADR/target contract.

## Ukrainian one-liner

Один і той самий offset `+0x1e0` у `nvidia-uvm.ko` читається від різних базових
об'єктів; назвати його RM-полем без store-site доказів — UNPROVEN.
