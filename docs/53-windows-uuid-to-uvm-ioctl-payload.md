# 53 — Windows: `device+0xc06` → `0x22e034` input `+0x08`

Продовження [`docs/45`](45-windows-uvm-uuid-comparison.md) і
[`docs/50`](50-windows-uvm-ioctl-map-and-uuid-payload.md). У docs/45 було
`statically proven`, що `cuDeviceGetUuid` читає 16 байт за `device+0xc06`, але
копію цих байт у тіло UVM-запиту не знайдено. У docs/50 знайдено 16-байтне поле
за `+0x08` у запиті `0x22e034`, проте походження значення позначено
`UNPROVEN`. Цей звіт з'єднує обидві частини **для одного конкретного сайту**
в shipped `nvcuda64.dll`.

**Головне (`statically proven`)**: `movups xmm2,[rcx+0xc06]` @`0x1803c5b41`
→ без проміжного запису `xmm2` → `movups [rsp+0x68],xmm2` @`0x1803c5c04`
→ `call 0x1803396c0` @`0x1803c5c09` з `edx=0x22e034`, `r9d=0x28`.
Отже 16 байт із об'єкта за адресою `+0xc06` стають полем `+0x08..+0x17`
40-байтного input-буфера IOCTL `0x22e034`.

**Не доведено й не виправдано екстраполяцією**: що об'єкт із таблиці є саме
`CUdevice`; що `0x22e034` — Windows-еквівалент Linux `UVM_REGISTER_GPU (0x25)`;
що індекс `r10` є RM `gpu_id` або CUDA- ordinal. Реліз/тег/publish не
виконувався.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `UNIQUE_GAP` | value-flow `+0xc06` → payload `0x22e034` у Windows | цей звіт |
| `statically proven` | опкоди, адреси, розташування поля, розміри, xmm2-ланцюжок | таблиці §2–§4 |
| `statically proven` | той самий зсув `+0xc06` і ширина 16 байт у `cuDeviceGetUuid` | перехресна перевірка §5 |
| `UNPROVEN` | тип об'єкта, `0x22e034 ≡ UVM_REGISTER_GPU`, `r10 ↔ gpu_id` | лишається відкритим |
| `coverage limitation` | BSS-значення, indirect dispatch, `axt`/`afi` порожні | не absence-proof |

Pin-и ABI v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract і asm-first
контракт не змінено.

## 1. Артефакт, інструменти, відтворення

| Артефакт | SHA-256 | Роль |
|---|---|---|
| `C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_58519edca6172ba9\nvcuda64.dll` | `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407` | єдиний Windows-артефакт цього звіту; 34 562 280 байт, image base `0x180000000` |
| `evidence/windows-20261128/uuid_to_ioctl_audit.json` | `04490016fd07a746a8be433dacf3893cd6dbfa6cb9f3b0be8c6a1cdd57a83d56` | машиночитний результат, 14/14 перевірок OK |
| `evidence/windows-20261128/pe_ioctl_audit.json` | `f7aa2836e40ad7de537f14ad2894f3955db30c05fb2c00ffa54e9f2583df6cdc` | IOCTL-карта з docs/50 |

| Інструмент | Версія | Застосування |
|---|---|---|
| Rizin (`rizin -v`) | `0.9.1 @ windows-x86-64` | адреси, opcodes, `px`, `axt`; REA `execute_rizin_command`, той самий SHA |
| Python (`py -3`) | `3.12.10` | запуск аудиту |
| `pefile` | `2024.8.26` | PE-секції, `.pdata`, VA↔file offset |
| `capstone` | `5.0.7` | обмежений лінійний розбір у межах pdata-діапазонів |

Відтворення (read-only, без запуску коду цілі):

```powershell
py -3 scripts/pe_uuid_flow_audit.py
(Get-FileHash -Algorithm SHA256 evidence\windows-20261128\uuid_to_ioctl_audit.json).Hash.ToLowerInvariant()
rizin -N -q -c "pd 55 @ 0x1803c5a70" 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_58519edca6172ba9\nvcuda64.dll'
rizin -N -q -c "pd 18 @ 0x1803c5bbf"  'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_58519edca6172ba9\nvcuda64.dll'
```

Скрипт відхиляє роботу, якщо SHA-256 артефакта не збігається або будь-яка з
14 перевірок не проходить. RM-ioctl, MMIO, GPU compute, запуск цілі — `NOT RUN`.

## 2. Розв'язка `device+0xc06` → `0x22e034`

Ланцюжок у межах одного PE (усі адреси — Virtual Address, image base
`0x180000000`):

| VA | Opcode | Інструкція | Що це дає |
|---|---|---|---|
| `0x1803c5a99` | `4d63d1` | `movsxd r10, r9d` | 4-й аргумент стає індексом |
| `0x1803c5aeb` | `f605d6f0c30101` | `test byte [rip+0x1c3f0d6],1` → `0x182004bc8` | runtime-прапорець вибирає гілку |
| `0x1803c5af2` | `742c` | `je 0x1803c5b20` | за цією гілкою — таблиця об'єктів |
| `0x1803c5b2a` | `443b1517cfc301` | `cmp r10d,[rip+0x1c3cf17]` | RIP → `0x182002a48`, межа індексу |
| `0x1803c5b36` | `488d0d0bcdc301` | `lea rcx,[rip+0x1c3cd0b]` | RIP → `0x182002848`, база таблиці |
| `0x1803c5b3d` | `4a8b0cd1` | `mov rcx,[rcx+r10*8]` | покажчик об'єкта з таблиці |
| **`0x1803c5b41`** | **`0f1091060c0000`** | **`movups xmm2,[rcx+0xc06]`** | 16 байт `+0xc06` → `xmm2` |
| `0x1803c5bdf` | `41b928000000` | `mov r9d,0x28` | input size = 40 |
| `0x1803c5bea` | `ba34e02200` | `mov edx,0x22e034` | IOCTL code |
| `0x1803c5bf4` | `f30f7f442478` | `movdqu [rsp+0x78],xmm0` | input `+0x18..+0x27` = 0 |
| **`0x1803c5c04`** | **`0f11542468`** | **`movups [rsp+0x68],xmm2`** | `xmm2` → input `+0x08..+0x17` |
| **`0x1803c5c09`** | **`e8b23af7ff`** | **`call 0x1803396c0`** | DeviceIoControl-helper |

Між `0x1803c5b41` і `0x1803c5c04` немає жодного запису в `xmm2`
(перевірено за явними операндами capstone 5.0.7, бо `regs_read`/`regs_write`
для `movups` у цій версії порожні). `rsp` не змінюється: `sub rsp,0x90` було
@`0x1803c5a75`, `add rsp,0x90` — лише після виклику.

Input-буфер починається з `rsp+0x60` (`lea r8,[rsp+0x60]` @`0x1803c5baf`):

| Зсув input | Джерело | Статус |
|---:|---|---|
| `+0x00..+0x03` | `r9d` (0 або 1, залежно від гілки `edx`) | `statically proven` |
| `+0x04..+0x07` | `esi` (значення з перемикача `r8d`) | `statically proven` |
| `+0x08..+0x17` | `xmm2` = 16 байт `[rcx+0xc06]` | **`statically proven`** |
| `+0x18..+0x27` | `xmm0 = 0` | `statically proven` |

Після виклику `qword [rsp+0x50]` пишеться в `[rbx+8]`, де
`rbx = rdi + rax*8` @`0x1803c5bc7` — результат повертається у масив контексту
за тим самим індексом. **Статус рядка 3: `statically proven`.** Що саме
представляє `r10` (Ordinal GPU чи RM id) — `UNPROVEN`.

## 3. Межі функцій і BSS

`.pdata` дає два суміжні записи (обидва знайдені скриптом у файлі):

| Unwind-запис | Початок | Кінець | unwind VA | file offset |
|---|---|---|---|---|
| 1 | `0x1803c5a70` | `0x1803c5bbf` | `0x181f1e058` | `0x2031224` |
| 2 | `0x1803c5bbf` | `0x1803c5c30` | `0x181f1e070` | `0x2031230` |

`0x1803c5b41` належить першому запису, `0x1803c5c04` і `call` — другому.
Це **не дві різні функції з різними стеками**: між записами немає `
add rsp`/`ret`, а `mov [rsp+0xb8],rbx` @`0x1803c5bbf` зберігає `rbx` у тому
ж кадрі, який далі читається @`0x1803c5c20`. Отже поток `xmm2` через
`rsp+0x68` — один кадр. `statically proven` для інструкцій; намір компілятора
не інтерпретується.

Три глобальні адреси лежать у `.data` за межами raw-даних секції
(`VirtualSize=0x45948`, `SizeOfRawData=0x8a00`), тобто в zero-filled хвості:

| VA | RVA | Роль | Вміст у файлі |
|---|---|---|---|
| `0x182002a48` | `0xaa48` | лічильник для `cmp r10d` | відсутній (`file_backed=false`) |
| `0x182002848` | `0xa848` | таблиця покажчиків, stride 8 | відсутній (`file_backed=false`) |
| `0x182004bc8` | `0xcbc8` | прапорець вибору гілки | відсутній (`file_backed=false`) |

Тому значення таблиці, лічильника й прапорця є **runtime-станом**. Ми не
виконували драйвер і не читали його пам'ять: `UNPROVEN` / `coverage limitation`,
а не доводження порожнечі. Альтернативна гілка викликає `0x1803c5700` —
`lock cmpxchg` + `GetSystemInfo` + виділення пам'яті (REA Evidence
`ev_12f515df…`), тобто ініціалізацію, а не копіювання UUID.

## 4. Записи `.rdata`, схожі на pdata

32-бітні RVA початку `0x1803c5a70` (`0x3c5a70`) трапляються двічі в `.rdata` —
за VA `0x181f1e078` і `0x181f1e088` (file `0x1f1d078` / `0x1f1d088`), оба з
сусідніми `0x3c5bbf` і `0x1f1e058`; третій випадок — власне `.pdata`.
Аналогічно `0x1803e4c10` (`0x3e4c10`) — VA `0x181f20514` / `0x181f20524` з
сусідніми `0x3e4c75` і `0x1f204f8`. Pdata для третього сайту теж розділений:
`0x1803e4c10–0x1803e4c75` і `0x1803e4c75–0x1803e4ce1`.

**Статус**: наявність і адреси — `statically proven`; призначення цих
`.rdata`-записів (dispatch-таблиця, EH-метадані тощо) — `UNPROVEN`. Прямих
`E8/E9`-викликів ані `0x1803c5a70`, ані `0x1803e4c10` не знайдено; `axt` для
них порожній — `coverage limitation`, не absence-proof.

## 5. Перехресна перевірка з `cuDeviceGetUuid`

docs/45 §3 довів, що `cuDeviceGetUuid` через dispatch потрапляє в
`fcn.180048780`, де `movups xmm0,[rax+0xc06]` @`0x18004887d` (opcode
`0f1080060c0000`) копіює 16 байт у вихідний `CUuuid`. Новий REA-запис
`ev_3ac635f4…` підтверджує ті самі opcode і адресу на цьому самому SHA.

| Властивість | `cuDeviceGetUuid` | site `0x1803c5b41` | Статус |
|---|---|---|---|
| Зсув | `+0xc06` | `+0xc06` | `statically proven` |
| Ширина | 16 (`movups`) | 16 (`movups`) | `statically proven` |
| Напрямок | об'єкт → `CUuuid` | об'єкт → IOCTL input `+8` | `statically proven` |
| Тип об'єкта | `UNPROVEN` (PE без типів) | `UNPROVEN` (таблиця в BSS) | `UNPROVEN` |

Writers для `+0xc06`/`+0xc27` уже зафіксовані в docs/45 §4
(`0x1804096ef`, `0x18036d645`); походження їхніх 16 байт лишається
`UNPROVEN`. Отже твердження «Windows копіює UUID у `0x22e034`» є
**`statically proven` тільки в частині зсуву/ширини й цільового поля**; повна
ідентичність об'єкта й UUID вимагає value-flow від writer-а до таблиці
`0x182002848`, якого зараз немає.

## 6. Рядки з атрибуцією

Усі рядки нижче використовують артефакт
`af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407`.

| Адреса / функція | Інструмент / версія | xrefs, caller, callee | Статус | Відкрите питання |
|---|---|---|---|---|
| `0x1803c5b41`, table-read | Rizin 0.9.1 + pefile/capstone 2024.8.26/5.0.7 | callee- equivalents відсутні; попередник `mov rcx,[rcx+r10*8]` @`0x1803c5b3d`; прямий caller не знайдено (`axt` порожній) | `statically proven` для opcode й джерела | Чи є `[0x182002848+r10*8]` вказівником на `CUdevice`? |
| `0x1803c5c04`, payload-store | Rizin 0.9.1 + capstone 5.0.7 | немає запису `xmm2` між `0x1803c5b41` і цією адресою; callee — helper `0x1803396c0` | `statically proven` | Чи зберігається той самий кадр при всіх шляхах виходу? |
| `0x1803c5c09`, `0x22e034` | Rizin 0.9.1 | callee `0x1803396c0` (`DeviceIoControl` @`0x1803396f3`); `in=0x28`, `out=0x28` | `statically proven` | Чи дорівнює `0x22e034` `UVM_REGISTER_GPU`? |
| `0x1803c5b2a` / `0x1803c5b36` | Rizin 0.9.1 + pefile 2024.8.26 | RIP → `0x182002a48` / `0x182002848`; `axt` порожній | `statically proven` для адрес; вміст — `coverage limitation` | Хто заповнює лічильник і таблицю в BSS? |
| `0x1803c5aeb`, branch flag | Rizin 0.9.1 | `test byte [0x182004bc8],0x01`; альтернативний callee `0x1803c5700`, `axt` порожній | `statically proven` для гілки | Яке значення прапорця під час реального виклику? |
| `0x18004887d`, `cuDeviceGetUuid` read | Rizin 0.9.1 | з docs/45: dispatch `0x180280320`/`0x18021ee20` → `fcn.180048780` | `statically proven` для зсуву/ширини | Чи тотожній об'єкт таблиці й об'єкт UUID? |
| `0x1803e4cc0`, третя копія `0x22e034` | Rizin 0.9.1 + pefile/capstone | RVA в `.rdata` @`0x181f20514`/`0x181f20524`; прямий caller не знайдено | `statically proven` для payload; призначення таблиці — `UNPROVEN` | Чи це інший шлях реєстрації GPU? |

## 7. REA Evidence (Rizin 0.9.1, artifact SHA вище)

| Evidence ID | Команда / вміст |
|---|---|
| `ev_7618b073bd674485636fb182e523c0e48437c8bdd08e0e1d6bb60993a4e9a125` | `pd 30 @ 0x1803c5b20`: RIP-цілі, `mov rcx,[rcx+r10*8]`, `+0xc06` |
| `ev_19cc5c476c4b76b58e8200439588517152d28c0d7e056a7c9181291d032b19e3` | `pd 55 @ 0x1803c5a70`: пролог, `r9d→r10`, прапорець, виклик `0x1803c5700` |
| `ev_9ad9300fced6fe2921838e032d90ed2c388cd782f28915bc765acf3e8adae444` | `pd 38 @ 0x1803c5b41`: неперервний потік через межу pdata до payload |
| `ev_620cbae1757223d6f42c9a3a6e68a5346de373fa05230421a85a75e53517aadc` | `pd 18 @ 0x1803c5bbf`: `mov edx,0x22e034`, store `xmm2`, call helper |
| `ev_3ac635f4631041e864e915894e578ab5feed248d2c0174b40bc945bc2c6d5a15` | `pd 12 @ 0x180048870`: `movups xmm0,[rax+0xc06]` |
| `ev_5b65640f5e70516b8b3405ea8d1d9e4c32fc092669b69309fb461c4f8fd528ec` | `px 64 @ 0x181f1e050`: записи в `.rdata` |
| `ev_12f515df159d5d15ec35cb4ee1410fb46dc08f41ddf8a569d71f2e8111565c54` | `pd 45 @ 0x1803c5700`: `lock cmpxchg`, `GetSystemInfo` |
| `ev_8c36054eba210309b2d238b53f4aafe48a45ab0c4757bd814a904fe9edb9ffd0` | `afi @ 0x1803c5a70`: порожньо (без попереднього `af`) — `coverage limitation` |
| `ev_6d80ab3566b972f5effb0530d099e642594563d0bf693d4677e4e0f0bc88499f` | `axt @ 0x1803c5a70`: порожньо — `coverage limitation` |
| `ev_71612137f6a026efa0f2af232d42ab3fdac7f3964471c1cf9603df2442bccff7` | `axt @ 0x1803c5bbf`: порожньо — `coverage limitation` |
| `ev_15bd7fcd46c556c5f7867273f640df11bfd30b4582b900e77909953f963c3f34` | `axt @ 0x1803c5700`: порожньо — `coverage limitation` |

REA виводив `WARNING: bin_file_strings: search interval size (0x1848c00)
exceeds max region size (0xa00000), skipping it`; `completion_status=complete`,
`artifact_changed=false` для кожного запису. Порожний `axt`/`afi` — не
доводження відсутності.

## 8. Що змінюється й що лишається відкритим

| Питання | docs/45 | docs/50 | docs/53 |
|---|---|---|---|
| Де Windows копіює 16 байт у UVM payload? | `coverage limitation` | знайдено `in+8`, джерело `UNPROVEN` | **`statically proven`**: `[obj+0xc06]` → `in+8` |
| Чи той самий зсув, що в `cuDeviceGetUuid`? | так (`+0xc06`) | `UNPROVEN` | зсув/ширина `statically proven`; тип об'єкта `UNPROVEN` |
| Який IOCTL реєструє GPU? | `UNPROVEN` | 27 кодів, кандидати `0x22e030`/`0x22e034` | без змін: `UNPROVEN` |
| Чи можна перенести Linux `0x25`? | ні | ні | ні |

Відкриті питання: початковий виробник 16 байт; шлях від writer-ів docs/45 до
таблиці `0x182002848`; значення BSS-прапорця; kernel-side dispatch `0x22e034`
у `nvlddmkm.sys`; еквівалент Linux callback `[holder+0x30]`; `BDF ↔ RM gpu_id`.

## 9. Межі

- Ghidra через REA для 34 МБ DLL завершився `provider_timeout` після
  `900000 ms` (docs/50); Ghidra-псевдокод у цей документ не копіювався.
- `nvlddmkm.sys` (`ae938460…`) містить рядки `\\.\UVMLiteController`, але
  повні константи `0x22e034` у коді відсутні; kernel dispatch — `UNPROVEN`.
- RM-ioctl, MMIO-записи, GPU compute, boot/reboot, firmware-зміни, PR #21 —
  `NOT RUN`. Реліз, тег, GitHub Release, rc6/keyring/upstream installer —
  не авторизовані й не виконувалися.
- Усі твердження позначено `statically proven`,
  `string-only`, `UNPROVEN` або `coverage limitation`; жодне не ґрунтується
  лише на іменах символів чи рядках.
