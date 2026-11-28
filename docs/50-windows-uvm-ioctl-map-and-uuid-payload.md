# 50 — REA P2: Windows UVM IOCTL-карта й 16-байтне поле в `0x22e034`

Продовження [`docs/45`](45-windows-uvm-uuid-comparison.md). Там Windows-колонка
мала два розрізнені коди (`0x22f000`, `0x22e028`) і відкритим лишалося питання,
чи копіюється 16-байтний UUID у UVM-запит. Цей звіт дає **повну карту** кодів,
які `nvcuda64.dll` подає у свій `DeviceIoControl`-helper, і вперше фіксує
точний формат 40-байтного запиту `0x22e034` з 16-байтним полем у ньому.

Важливо: доведено **наявність і розташування 16 байт**, але не доведено, що саме
це значення є UUID з `device+0xc06`/`+0xc27`, і не доведено, що `0x22e034` —
Windows-еквівалент Linux `UVM_REGISTER_GPU (0x25)`. Обидва твердження лишаються
`UNPROVEN`.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `UPSTREAM_EXISTS` | Linux `uvm_gpu_retain_by_uuid` / `nvUvmInterfaceGetGpuInfo` | implementation authority, не замінює shipped-доказ |
| `UNIQUE_GAP` | Windows IOCTL-карта й payload `0x22e034` | цей звіт |
| `PARTIAL` | 16 байт із 4-го аргументу в UVM-запиті | знайдено, тотожність UUID — `UNPROVEN` |
| `UNPROVEN` | `0x22e034 ≡ UVM_REGISTER_GPU`, `BDF ↔ RM gpu_id` | лишається відкритим |
| `coverage limitation` | indirect dispatch, Ghidra timeout, ESIL-помилки | не absence-proof |

Pin-и ABI v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract і asm-first
контракт не змінено. Реліз/тег/publish не виконувався.

## 1. Артефакт, інструменти, відтворення

| Артефакт | SHA-256 | Роль |
|---|---|---|
| `C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_58519edca6172ba9\nvcuda64.dll` | `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407` | основний Windows-відповідник `libcuda`; файл не змінювався |
| `evidence/windows-20261128/pe_ioctl_audit.json` | `f7aa2836e40ad7de537f14ad2894f3955db30c05fb2c00ffa54e9f2583df6cdc` | машиночитний результат аудиту |

Інструменти (усі встановлені локально без адміна; Ghidra-псевдокод не використовувався):

| Інструмент | Версія | Застосування |
|---|---|---|
| Chocolatey Portable | `2.7.5` (`C:\Tools\chocoportable`) | менеджер портативних пакетів |
| Python (launcher `py -3`) | `3.12.10` | запуск аудиту |
| `pefile` | `2024.8.26` | PE-секції, image base, export table |
| `capstone` | `5.0.7` | backtrack-розбір інструкцій |
| Rizin (REA `execute_rizin_command`) | `0.9.1`, commit `c3a90e9226d977f58f4e9c75f78fa6b07afe13c7` | адреси, opcodes, `af`/`axt` |
| `jq`, `ripgrep`, `7-Zip`, LLVM | `1.8.2`, `16.0.0`, `26.6.0`, `19.1.0` | перевірка JSON/файлів |

Відтворення (read-only):

```powershell
py -3 scripts/pe_ioctl_audit.py `
  'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_58519edca6172ba9\nvcuda64.dll' `
  evidence\windows-20261128\pe_ioctl_audit.json
```

Метод: сканування `E8/E9 rel32` у всіх секціях PE + capstone-backtrack до
кожного site (лінійний `disasm` по всій секції в цьому DLL дрейфує й давав
`helper_calls_count=0`, тому відкинутий). Жодного RM-ioctl, MMIO, GPU compute
або запуску коду цілі не виконувалося.

REA Evidence (Rizin, той самий SHA):

| Evidence ID | Що містить |
|---|---|
| `ev_962ff51c0cbf1a923ceaa5415f9147b523c2e0991a2d388ccfd023c55fef583c` | `pd 45 @ 0x18033a980`: повне тіло функції |
| `ev_ec88513241378628bbb1b49aeac88bddba2329619f902c14c142ff8067393201` | `pd 42 @ 0x18033a980`: `movaps xmm2,[r9]`, `0x22e034` |
| `ev_944e22fa9e97fd2346ec0f2d64bf76d62d9cef830ef6935f462cf36bc39cbb3c` | `afi @ 0x18033a980`: size `169`, call-refs `0x1803396c0`, `0x1817c6290` |
| `ev_41927488d3122b529c371721ca1c8d57df8db39429c508886d3aece50bf211d2` | `pd 260 @ 0x18033a8e0`: `0x22e030`, буфер `0x388`, stride `0x1c` |
| `ev_cc83569ff67a2bf0c2639e99d503679092b875cc81273e5e1dac6c51d2168ada` | `pd 55 @ 0x1803c5bc0`: друга копія payload `0x22e034` |
| `ev_136a1472f7cd9345969ab68f26012e1836b5ef4233d5d49ef8d59d603b8bce8e` | `0x22e028` @`0x18033a880`, `0x22e030` @`0x18033a93b` |
| `ev_b70c0d4190182b9a7182568560d817038ddd8c271a36a7e3b486565f9934da20` | `DeviceIoControl` @`0x1803396f3` у helper-і `0x1803396c0` |
| `ev_58bfc3034445829b9805e6265c28eccdba9808690ba7790071ae21bdb0e4a19f` | `CreateFileW` @`0x18033960d`, `CreateFileMappingW` @`0x180339637` |
| `ev_80dd8cee3cefbe764b2c52c735a85403cb60b55625a5f90efc34ffe5d024c56d` | `\\.\UVMLiteController` @`0x181e803c0` (string-only) |
| `ev_ce05a70e2b3e6af401307fd1b44ba83a16e39b427992107d51693f1282b9507f` | `axt @ 0x1803396c0`: 58 прямих caller-ів |

## 2. Повна IOCTL-карта `\\.\UVMLiteController`

Усі 58 викликів helper-а `0x1803396c0` (`DeviceIoControl` @`0x1803396f3`)
згруповані за `dwIoControlCode` (з `mov edx, imm` перед викликом). `in-size` —
значення `r9d`; `-` означає, що безпосередній `mov r9d, imm` у вікні не знайдено
(`coverage limitation`, а не нуль).

| IOCTL | Викликів | in-size (`r9d`) | Репрезантативний call VA |
|---|---:|---|---|
| `0x22e004` | 3 | `0x18` | `0x1801f0dac` |
| `0x22e008` | 2 | `0x18` | `0x1801f0e84` |
| `0x22e00c` | 2 | `0x30` | `0x1801f4076` |
| `0x22e010` | 2 | `0x18` | `0x1801f425c` |
| `0x22e014` | 2 | `0x30` | `0x1801f45d2` |
| `0x22e018` | 2 | `0x10` | `0x1801f4363` |
| `0x22e01c` | 1 | `0x110` | `0x1801f44b4` |
| `0x22e024` | 1 | `0x2c` | `0x18033a3dd` |
| `0x22e028` | 3 | `0x8` | `0x18033a885` |
| `0x22e030` | 3 | `0x388` | `0x18033a947` |
| `0x22e034` | 3 | `0x28` | `0x18033a9fc` |
| `0x22e038` | 3 | `0x28` | `0x18033acfe` |
| `0x22e03c` | 2 | `0x8` | `0x18033ad80` |
| `0x22e040` | 3 | `0x28`, `0x38` | `0x18033ae09` |
| `0x22e044` | 1 | `0x10` | `0x18033aea0` |
| `0x22e050` | 3 | `0x208` | `0x18033af4e` |
| `0x22e054` | 2 | - | `0x1801f3e26` |
| `0x22e058` | 2 | `0x18` | `0x1801f3ee1` |
| `0x22e064` | 2 | -, `0x14` | `0x1801f4c9b` |
| `0x22e068` | 2 | `0x14` | `0x1801f4d6f` |
| `0x22e094` | 2 | `0x28` | `0x1801f49a0` |
| `0x22e098` | 2 | `0x14` | `0x1801f4ae3` |
| `0x22e09c` | 2 | `0x8` | `0x1801f01c6` |
| `0x22f000` | 2 | - | `0x1801f010b` |
| `0x22f004` | 2 | `0x20` | `0x1801f4139` |
| `0x22f008` | 2 | `0x10` | `0x1801f41ca` |
| `0x22fffc` | 2 | `0x8` | `0x1801f0259` |

Разом **27 унікальних кодів**, з них 26 у діапазоні `0x22e0xx–0x22e09c` і
три `0x22f0xx` + один `0x22fffc`. Попередній попарний перелік у docs/45 не є
повним; `0x8de0004`/`0x8de0008` належать іншому пристрою (`\\.\NvAdminDevice`)
і в цю таблицю не входять.

**Статус: `statically proven`** для кодів, розмірів і call VA.
**UNPROVEN**: який саме код виконує реєстрацію GPU. Кандидати — `0x22e030`
(масив `0x388` байт, stride `0x1c`) і `0x22e034` (пер-GPU запит `0x28` байт);
пріоритет між ними статично не встановлено.

## 3. payload `0x22e034`: 16 байт із 4-го аргументу

Три ділянки з однаковою структурою (capstone + Rizin збігаються):

| `mov edx, 0x22e034` | виклик helper-а | джерело 16 байт |
|---|---|---|
| `0x18033a9cf` | `0x18033a9fc` | `movaps xmm2, xmmword [r9]` @`0x18033a99b` |
| `0x1803c5bea` | `0x1803c5c09` | `movups xmmword [rsp+...]` з попереднього `xmm` (Ev `ev_cc8356…`) |
| `0x1803e4ca7` | `0x1803e4cc0` | `movaps xmm0, xmmword [r9]` @`0x1803e4c7d` |

Розбір тіла `0x18033a980` (Rizin `afi`: size `169`,Evidence
`ev_962ff5…` / `ev_944e22…`):

```text
0x18033a99b  movaps  xmm2, xmmword [r9]        ; 16 байт із 4-го аргументу
0x18033a9a1  mov     rcx, [rcx+0x810]          ; handle UVMLiteController
0x18033a9bb  mov     r9d, 0x28                 ; in-size = 40
0x18033a9c6  mov     dword [rsp+0x58], edx     ; in[0x00..0x03]
0x18033a9ca  mov     dword [rsp+0x5c], r8d     ; in[0x04..0x07]
0x18033a9cf  mov     edx, 0x22e034             ; IOCTL
0x18033a9d4  mov     qword [rsp+0x28], 0x28    ; out-size = 40
0x18033a9dd  lea     r8, [rsp+0x58]            ; in-buffer
0x18033a9e2  mov     [rsp+0x20], rax           ; out-buffer = rsp+0x30
0x18033a9e7  movdqu  xmmword [rsp+0x70], xmm0  ; in[0x18..0x27] = 0
0x18033a9ed  movups  xmmword [rsp+0x30], xmm1  ; out[0x00..0x0f] = 0
0x18033a9f2  movups  xmmword [rsp+0x40], xmm1  ; out[0x10..0x1f] = 0
0x18033a9f7  movups  xmmword [rsp+0x60], xmm2  ; in[0x08..0x17] = [r9]
0x18033a9fc  call    0x1803396c0               ; DeviceIoControl helper
0x18033aa01  mov     rcx, [rsp+0x48]           ; out[0x18..0x1f]
0x18033aa08  mov     [rbx], rcx                ; повернення через out-pointer
0x18033aa1b  call    0x1817c6290               ; stack-canary check
```

Формат 40-байтного **input**:

| Зсув | Ширина | Що | Статус |
|---|---:|---|---|
| `+0x00` | 4 | `edx` (2-й аргумент) | `statically proven` |
| `+0x04` | 4 | `r8d` (3-й аргумент) | `statically proven` |
| `+0x08` | 16 | `[r9]` (4-й аргумент), через `xmm2`/`xmm0` | `statically proven` |
| `+0x18` | 16 | нуль (`xorps xmm0,xmm0` → `movdqu`) | `statically proven` |

Формат 40-байтного **output**: нульова початкова область; після виклику
`qword [out+0x18]` копіюється в `[rbx]` — out-pointer 5-го аргументу.

**Статус: `statically proven`** для зсувів, напрямку копіювання, розмірів і
call site-ів. **UNPROVEN**: тотожність `[r9]` з `CUuuid` з `device+0xc06`/
`+0xc27` (див. §4).

## 4. Ідентичність функції та xrefs

- `0x18033a980` — function start за `.pdata`: RVA `0x33a980`, file offset
  `0x20286bc`. Експорту з цією адресою немає (перевірено 711 export-ів,
  `exports_near_targets=[]`).
- REA Rizin `axt @ 0x1803396c0` дав 58 caller-ів; `axt @ 0x18033a980`,
  `axt @ 0x18033a8e0` — порожньо з ESIL `Cannot peek memory without specifying
  an address` → `coverage limitation`.
- Незалежне сканування всіх секцій: `E8/E9 rel32` у `0x18033a980` → **0 hit**;
  8-байтний покажчик/VMA → **0**; 4-байтний RVA → **1**, і це лише `.pdata`.
  Аналогічно `0x18033a8e0` → 0/0/1 (`.pdata`). Отже прямих викликів у shipped
  PE не знайдено; це **не доводить**, що шлях недосяжний (можливий indirect
  dispatch через таблиці/вказівники, які не зберегли точну адресу).
- `0x1803e4c10` (третя копія payload) має **два** записи як 32-бітний RVA в
  `.rdata` за VA `0x181f20514` і `0x181f20524`, оба з сусіднім
  `0x1803e4c75` та `0x181f204f8`. Це схоже на table-запис, але призначення
  таблиці статично не ідентифіковане → `UNPROVEN`.

| Адреса / функція | Артефакт (SHA-256) | Інструмент / версія | xrefs, caller, callee | Статус | Відкрите питання |
|---|---|---|---|---|---|
| `0x1803396c0`, IOCTL-helper | `af853a5b…d407` | Rizin 0.9.1 + pefile/capstone | 58 caller-ів; callee `KERNEL32!DeviceIoControl` @`0x1803396f3` | `statically proven` | Чи існує серед 58 кодів реєстрація GPU? |
| `0x18033a8e0`, `0x22e030`, buf `0x388` | `af853a5b…d407` | Rizin 0.9.1 | caller-ів не знайдено; callee `0x1817d67a0`, helper `0x1803396c0` | `statically proven` для коду/розміру; caller — `coverage limitation` | Чи є `0x22e030` списком GPU для реєстрації? |
| `0x18033a980`, `0x22e034`, 16 байт | `af853a5b…d407` | Rizin 0.9.1 + pefile/capstone | caller-ів не знайдено; callee `0x1803396c0`, `0x1817c6290`; data-ref `0x181ff8010` | `statically proven` для payload; походження `[r9]` — `UNPROVEN` | Чи `[r9]` = `CUuuid` з `device+0xc06`? |
| `0x1803c5c09`, `0x22e034` (копія 2) | `af853a5b…d407` | Rizin 0.9.1 + capstone | див. `ev_cc8356…`; прямий caller не знайдено | `statically proven` для структури | Хто формує попередній `xmm`? |
| `0x1803e4cc0`, `0x22e034` (копія 3) | `af853a5b…d407` | Rizin 0.9.1 + capstone | RVA в `.rdata` @`0x181f20514`/`0x181f20524`; caller не знайдено | `statically proven` для структури; призначення таблиці — `UNPROVEN` | Чи це dispatch-таблиця UVM/CUDA? |
| `\\.\UVMLiteController` @`0x181e803c0` | `af853a5b…d407` | Rizin 0.9.1 | xrefs `0x1801f00d6`, `0x1803399b4`, `0x18033a834`, `0x1803c58b7`, `0x1803e49f6` | `string-only` + `statically proven` для xrefs | Який із п'яти шляхів реєструє GPU? |

## 5. Що це змінює у звірці docs/45

| Питання docs/45 | Було | Стало |
|---|---|---|
| «Де Windows копіює 16 байт у UVM payload?» | `coverage limitation` | **знайдено**: `in+0x08` запиту `0x22e034`, 3 копії; саме поле — `statically proven`, тотожність UUID — `UNPROVEN` |
| «Який nr відповідає `UVM_REGISTER_GPU`?» | 2 кандидати | 27 кодів; головні кандидати `0x22e030`/`0x22e034`, вибір — `UNPROVEN` |
| «Чи можна екстраполювати `0x25`?» | ні | ні; Windows-коди не збігаються з Linux `nr` |

Linux-ланцюг лишається незмінним: `/dev/nvidia0` → `0x41` → `GPU_GET_PROBED_IDS
(0x214)` → `GPU_ATTACH_IDS (0x215)` → `NV01_DEVICE_0 (0x80)` →
`NV20_SUBDEVICE_0 (0x2080)` → `MC_GET_ARCH_INFO (0x20801701)`; userspace
`ioctl(fd,0x25,…)` @`0x449faf`. Перенесення номера коду на Windows заборонено.

## 6. Відкриті питання

1. Чи є `0x22e034` (`0x28`-байтний per-GPU запит) Windows-еквівалентом
   `UVM_REGISTER_GPU`, чи лише запитом/оновленням UUID?
2. Чи дорівнює 16 байт `[r9]` у `0x18033a980` значенню `device+0xc06` /
   `+0xc27`, яке читає `cuDeviceGetUuid`? Для відповіді потрібен прямий
   caller або value-flow через indirect dispatch — зараз `UNPROVEN`.
3. Хто початковий виробник 16 байт у `arg3+0x1f8+i*0x198` і `rdi+0x481`
   (docs/45 §4)?
4. Чи існує Windows-еквівалент Linux callback `[holder+0x30]`?
5. Як D3DKMT/BDF перетворюється на RM `gpu_id` і чи бере участь UUID?
6. Яке призначення `.rdata`-таблиці, що містить `0x1803e4c10`/`0x1803e4c75`?

## 7. Межі й що не робилося

- Ghidra через REA: `open_binary` вдавався, але `procedure_info` для 34 МБ DLL
  завершився `provider_timeout` після `900000 ms`; псевдокод не скопійовано.
  `coverage limitation`, не absence-proof.
- Rizin: `bin_file_strings: search interval size (0x1848c00) exceeds max region
  size (0xa00000), skipping it`; `esil address ... Cannot peek memory` для
  низки адрес; `axt` для interior-адрес порожній. Це не доводить відсутність.
- Capstone-лінійний прохід по всій секції дрейфує; ускладнений backtrack
  відновлює лише безпосереднє оточення site-у, не весь CFG.
- `nvlddmkm.sys`/`nvml.dll` — лише inventory; NVML side-path не перевірявся.
- RM-ioctl, MMIO-записи, GPU compute, boot/reboot, firmware-зміни, PR #21 —
  `NOT RUN`. Реліз/тег/GitHub Release/rc6/keyring/upstream installer — не
  виконувалися й не авторизовані.

## 8. Покриття доказів

- Кожен рядок таблиць §2–§4 посилається на той самий артефакт
  `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407`;
  машиночитний файл — `pe_ioctl_audit.json` з хешем вище.
- Висновки позначено `statically proven`, `string-only`, `UNPROVEN` або
  `coverage limitation`. Жодне твердження не базується лише на іменах рядків.
