# 41 — REA P1: userspace-джерело UUID у shipped `libcuda`

Продовження [`docs/40`](40-rea-p1-gpu-info-uuid-direction.md). Там найменшим
кроком було знайти, хто заповнює перше поле ioctl-параметра в userspace.
Відповідь часткова: у shipped `libcuda` знайдено шлях
`device+0xc06 → ioctl(fd, 0x25, …)` і той самий зсув читає `cuDeviceGetUuid`.
Кінцевий виробник значення (RM/NVML/PCI BDF) **не доведено**.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | docs/35–38 (BTF, `add_gpu`, ioctl → `add_gpu`), docs/40 (напрямок `GetGpuInfo`) | не повторювати |
| `PARTIAL` | docs/40 §6: хто в userspace заповнює UUID | цей звіт: шлях знайдено, джерело — ні |
| `UPSTREAM_EXISTS` | Nouveau/NVKM/NVK | implementation authority, не замінює shipped-доказ |
| `UNIQUE_GAP` | shipped `libcuda`: UUID → `UVM_REGISTER_GPU` | цей звіт |
| `UNPROVEN` | виробник `device+0xc06`, `BDF ↔ RM gpu_id` | лишається відкритим |

Pin-и v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract, ABI-pin і
asm-first контракт не змінено.

## 1. Артефакти, інструменти, мапа адрес

| Артефакт | SHA-256 |
|---|---|
| `/usr/lib/x86_64-linux-gnu/libcuda.so.580.196.11` | `20ad440390dad2c5fd06c14e518990512a8e7b31f8b6add7bb1581832fd4d331` |

Інструменти: REA `execute_rizin_command` (`rizin 0.9.1 @ linux-x86-64`,
provider version `null`), GNU `objdump`/`readelf`/`strings` (Binutils
`2.47.50.20261021`).

Для цього ELF Rizin-адреси збігаються з ELF-віртуальними адресами (символи
`objdump`), **не з file offset-ами**. File offset `/dev/nvidia-uvm`
(`0x592509e`) у звіті окремо не змішується з віртуальними адресами.

Версія файлу `580.196.11` збігається з раніше спостережуваним
`driver_id=4 / info=580.196.11`, але Build-ID pairing цього `.so` з `.ko`
у цій сесії **не виконувався** — `coverage limitation`, не доказ розбіжності.

Raw witness:
[`evidence/rea-20261128/libcuda-uuid-to-uvm-ioctl.txt`](../evidence/rea-20261128/libcuda-uuid-to-uvm-ioctl.txt),
SHA-256 `773aab0201ca1212a2b7bc5eaed55964b53baa595b025cf608666c1cfa306447`.
Evidence bundle: `evidence/rea-20261128/evidence-p1-libcuda-uuid.json`,
184 records, SHA-256 `582da82a7de7ba0e75574a0f7cd61e4f6f8e0f7169dd28eab9b4d542dabd58ac`.

Ключові Evidence IDs: `ev_348cc965…`, `ev_1e2955ae…`, `ev_0ce48687…`,
`ev_b17b2c42…`, `ev_85bc487b…`, `ev_bf085e8e…`, `ev_9da6da5f…`,
`ev_30d9dcc2…`, `ev_cd20e5c1…`, `ev_2c1d3e7a…`, `ev_d6496e9c…`.

## 2. Унікальний `ioctl(fd, 0x25, …)` і його payload

`docs/ioctl-map.md`: UVM `nr 37` = `0x25` = `UVM_REGISTER_GPU`.

Цільовий перерахунок `ioctl@plt` із перевіркою 14 попередніх інструкцій на
`$0x25,%esi` дав **рівно один** виклик: `0x449faf`. Хелпер `0x449f40`:

- `0x449f4a`: `r13 = rdi` — 16-байтне джерело;
- `0x449f67`: `movdqu xmm1, [r13]`;
- `0x449f76`–`0x449f82`: local buffer `[rbp-0x60..-0x40]` спочатку zeroed,
  потім `[rbp-0x60] = xmm1`;
- `0x449f9b`: `r13d = [rbx]`, де `rbx = [0x5c31848]` — fd-holder;
- `0x449fa4`–`0x449faf`: `rdx = &buf`, `esi = 0x25`, `call ioctl`.

Evidence `ev_0ce48687…` (`pd 50 @ 0x00449f40`).

**Статус: `statically proven`** для того, що перші 16 байтів payload є
побайтовою копією першого аргументу хелпера. Це не `absence-proof` для інших
шляхів: `axt @ 0x00166160` (Evidence `ev_e30c7680…`) був порожнім із
попередженнями pro skipped intervals — `coverage limitation`.

## 3. Хто викликає хелпер: `device+0xc06`

Прямі виклики `0x449f40`: `0x320b56`, `0x320c8d`, `0x46f03e`
(targeted `objdump` cross-check; Rizin `axt` знову з `coverage limitation`).

- `0x00320b27`: `lea r14, [rdi+0xc06]`; method call `[rdi+0x7130]` заповнює
  **окремий локальний** буфер `r13`; далі `rdi=r14`, `rsi=r13`,
  `call 0x449f40` — Evidence `ev_b17b2c42…`.
- `0x00320c88`–`0x00320c8d`: fallback з тим самим `r14` — Evidence
  `ev_85bc487b…`.
- Третій виклик `0x46f03e` не протрасовано до джерела UUID —
  `coverage limitation`.

**Статус: `statically proven`** для двох протрасованих шляхів: UUID у
`UVM_REGISTER_GPU` береться з 16 байтів за зсувом `0xc06` об'єкта device.
Метод `+0x7130` не є джерелом саме `0xc06`; він лише готує другий аргумент.

## 4. `cuDeviceGetUuid` читає той самий зсув

`cuDeviceGetUuid @0x0037aa70` викликає dispatch table `[0x5bd48f0]`
(Evidence `ev_2d03587a…`). У цілі `0x0038c1d0`:

- `0x0038c1d8`: `r12 = rdi` — вихідний `CUuuid`;
- `0x0038c248`–`0x0038c24f`: table `[0x5bd9a40]`, device за індексом `rbx`;
- `0x0038c257`–`0x0038c25f`: `movdqu xmm1, [rdx+0xc06]`;
  `movups [r12], xmm1`.

Evidence `ev_fc19a9d6…` і targeted window `ev_bf085e8e…`.

**Статус: `statically proven`**: публічний `cuDeviceGetUuid` і
`UVM_REGISTER_GPU` споживають одне й те саме поле `device+0xc06`.

## 5. Хто заповнює `device+0xc06`: хелпер є, кінцевий виробник — ні

`0x00faf660` бере `rdi = &buf`, `r12 = [0x5c31848]`, блокує rwlock за
`rdi-0x38` і викликає `qword [r12+0x30]` для заповнення буфера
(Evidence `ev_9da6da5f…`). З двома verified caller-ами:

- `0x0030318e` → `0x003031ae`: `lea rdi,[rdi+0xc06]`, `call 0xfaf660`
  (Evidence `ev_cd20e5c1…`);
- `0x0046a696` → `0x0046a6d5`: `lea r13,[r15+0xc06]`, `call 0xfaf660`
  (Evidence `ev_30d9dcc2…`).

Слот `[holder+0x30]` у shipped-файлі нульовий (Evidence
`ev_2c1d3e7a…`, `px 128 @ 0x5bd5378`), а один шлях ініціалізації може
записати цей zeroed template у глобальний holder (Evidence `ev_d6496e9c…`,
`0x3032a0`/`0x3032a7`). Який саме callback встановлюється під час виконання,
у цій сесії не спостережено: `axt @ 0x005c31848` — порожньо з попередженнями
(Evidence `ev_0a6d1fc4…`) — `coverage limitation`, не absence-proof.

**Статус:** роль `faf660` як заповнювача буфера — `statically proven`;
ціль callback-а, можливий RM/NVML-виробник і будь-який вивід
`BDF ↔ RM gpu_id` — **`UNPROVEN`**.

## 6. `retracted observation`

Чернетка witness-файлу (до коміту) помилково стверджувала, що метод
`[device+0x7130]` є джерелом поля `0xc06`, і що Rizin-адреси цього `.so`
збігаються з file offset-ами. Обидва твердження вилучено до публікації:
перше — хибне читання аргументів (`+0x7130` заповнює окремий локальний
буфер), друге — хибна мапа адрес. Висновки docs/41 з них не виводяться.

## 7. Статуси й межі

| Твердження | Статус |
|---|---|
| `libcuda` містить `/dev/nvidia-uvm` та імпортує `ioctl`/`open` | `statically proven` (String REA — `coverage limitation`; shell cross-check) |
| Єдиний targeted call-site `ioctl(fd,0x25,…)` = `0x449faf` | `statically proven` (не absence-proof для непрямих шляхів) |
| Перші 16 байт payload = копія першого аргументу `0x449f40` | `statically proven` |
| Два протрасовані caller-и передають `&device+0xc06` | `statically proven` |
| `cuDeviceGetUuid` читає той самий `device+0xc06` | `statically proven` |
| `faf660` заповнює цей буфер через callback `[holder+0x30]` | роль `statically proven`, ціль — `UNPROVEN` |
| Кінцевий виробник UUID, `BDF ↔ RM gpu_id` | **`UNPROVEN`** |
| RM class/runlist/notifier/fence | `UNPROVEN` |
| BOOT0 / `0x137000A1` | `UNPROVEN` / `string-only` (без змін) |
| Непрямі виклики, пропущені REA-інтервали, третій caller | `coverage limitation` |
| MMIO, RM-ioctl, GPU compute, boot/reboot, PR #21 | **`NOT RUN`** |

## 8. Unanswered question і найменший крок

**Unanswered:** яка саме функція встановлюється в `[holder+0x30]` і чи
отримує вона UUID з RM GPU info / PCI BDF.

**Найменший крок:** цільово простежити записи в глобальний holder
`0x5c31848` і в слот `+0x30` у shipped `libcuda`/пов'язаних NVIDIA
бібліотеках ( relocation/dispatch-table/indexed writes), не виконуючи ioctl
і не відкриваючи MMIO. Якщо callback лишається непрозорим — залишити
`UNPROVEN` із `coverage limitation`, не екстраполювати на RM.

## Ukrainian one-liner

У shipped `libcuda` доведено, що UUID для `UVM_REGISTER_GPU` і публічного
`cuDeviceGetUuid` береться з поля `device+0xc06`; хто саме заповнює це поле і
чи воно походить від BDF/RM — `UNPROVEN`.
