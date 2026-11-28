# 45 — REA P1: Windows ↔ Linux, UUID → UVM

Продовження [`docs/41`](41-rea-p1-libcuda-userspace-uuid-source.md) і [`docs/40`](40-rea-p1-gpu-info-uuid-direction.md).
На Linux-стороні шлях `device+0xc06 → ioctl(fd, 0x25, …)` і читання того самого
поля `cuDeviceGetUuid` зафіксовано як `statically proven`. Цей звіт заповнює
Windows-колонку звірки **лише shipped-артефактами** та власними нотатками
Rizin. Висновок частковий: механізм еквівалентний, коди й структури — інші,
кінцеве джерело UUID не доведене жодною зі сторін.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | docs/38–41 (Userspace UUID → `0x25`, напрямок `GetGpuInfo`) | не повторювати |
| `UPSTREAM_EXISTS` | Nouveau/NVKM/NVK | implementation authority, не замінює shipped-доказ |
| `UNIQUE_GAP` | Windows userspace counterparts `\\.\UVMLiteController`, `nvcuda64.dll` | цей звіт |
| `PARTIAL` | Windows `device+0xc06`, writer-сайти | знайдено, початкове джерело — ні |
| `UNPROVEN` | `BDF ↔ RM gpu_id`, Windows-еквівалент `UVM_REGISTER_GPU (0x25)` | лишається відкритим |

Pin-и ABI v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract і asm-first
контракт не змінено. Реліз/тег/publish не виконувався.

## 1. Артефакти, інструменти, мапа адрес

| Артефакт | SHA-256 | Версія файлу | Роль |
|---|---|---|---|
| `C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_58519edca6172ba9\nvcuda64.dll` | `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407` | `32.0.15.8278` (ресурс: `NVIDIA CUDA Driver, Version 582.78`, `CUDA 13.0.100 driver`) | основний Windows-відповідник `libcuda` |
| `C:\Windows\System32\nvcuda.dll` | `60a0f34f4e28bd305a1fe009635ccd62e7f4b6ed1500692adaf4a0eeb2cd0a91` | `32.0.15.8278` | loader-only: `DeviceIoControl` відсутній |
| `C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_58519edca6172ba9\nvlddmkm.sys` | `ae93846067fbb17327d0fc970ce23c533922e811199830d5ac469523c9ca78a3` | `32.0.15.8278` | kernel-кандидат, тільки inventory |
| `C:\Windows\System32\nvml.dll` | `c53e981ac0d01410dba1e9e11f74ea80c7bcb0a2150b68c4a9c99bd38cac4774` | `8.17.15.8278` | NVML side-path кандидат, тільки inventory |

Linux-артефакти для звірки (з docs/36, docs/40, docs/41):

| Артефакт | SHA-256 |
|---|---|
| `/usr/lib/x86_64-linux-gnu/libcuda.so.580.196.11` | `20ad440390dad2c5fd06c14e518990512a8e7b31f8b6add7bb1581832fd4d331` |
| shipped `nvidia-uvm.ko` | `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` |
| shipped `nvidia.ko` | `95c5fa5ab0546ee40842cda2ec20ea3ec1e196a5afee1580944ecae2ffc75bbe` |

Інструмент: REA `execute_rizin_command`, `rizin 0.9.1 @ windows-x86-64`,
commit `c3a90e9226d977f58f4e9c75f78fa6b07afe13c7`. Адреси нижче — віртуальні
адреси PE (`image base 0x180000000`), не file offset-и. Ghidra-провайдер REA
був недоступний (`Set GHIDRA_INSTALL_DIR to an extracted Ghidra 12.x (>=12.2)
release directory.`), тому декомпіляторного cross-check немає:
`coverage limitation`, не absence-proof.

Власні нотатки й команди:
[`evidence/windows-20261128/`](../evidence/windows-20261128/).

## 2. `/dev/nvidia-uvm`-еквівалент і `ioctl`-еквівалент

`nvcuda64.dll` містить UTF-16 рядок `\\.\UVMLiteController` @`0x181e803c0`;
data-xrefs: `0x1801f00d6` (`fcn.1801f0040`), `0x1803399b4`, `0x18033a834`,
`0x1803c58b7`, `0x1803e49f6`. Шляхเอง — `string-only`, але xrefs і код нижче
роблять його **використаним**, а не просто рядком.

- `0x1803395b0` — open-helper: `CreateFileW` @`0x18033960d`
  (`dwDesiredAccess=0xc0000000`, `dwCreationDisposition=3`, share `3`).
- `0x1803396c0` — IOCTL-helper: `DeviceIoControl` @`0x1803396f3`.
- `0x1803399b4` — виклик open-helpera з `\\.\UVMLiteController`, далі
  `dwIoControlCode=0x22f000` @`0x1803399e4`, in-size `0x104`.
- `0x18033a834` — той самий device, `dwIoControlCode=0x22e028`
  @`0x18033a880`, in/out-size `8`.

Окремий адміністративний шлях: `\\.\NvAdminDevice` @`0x18020b8be`
(`CreateFileA`, caller `fcn.18020b620`), handle зберігається @`0x182025550`;
тут `fcn.18020b3c0` використовує `0x8de0004` @`0x18020b438`
(in/out `0x88`), а `fcn.18020c350` — `0x8de0008` @`0x18020c3f9` (in `0x5c`).
IAT `KERNEL32.dll!DeviceIoControl` @`0x18184a3b8`; `CreateFileW` @`0x18184a080`;
`CreateFileA` @`0x18184a160`.

**Статус: `statically proven`** для наявності пристрою, helper-ів і числових
кодів. Не доведено, який із кодів виконує реєстрацію GPU; не можна
екстраполювати Linux `nr=0x25` на Windows — `UNPROVEN`.

## 3. `cuDeviceGetUuid` і поле `+0xc06`

- `cuDeviceGetUuid @0x180280540` → dispatch `[0x181ffa340]` → `0x180280320`
  → `fcn.180048780` (call @`0x18028039a` та `0x1802804d7`).
- `cuDeviceGetUuid_v2 @0x18021f040` → dispatch `[0x181ffa868]` → `0x18021ee20`
  → той самий `fcn.180048780` (call @`0x18021ee9a`, `0x18021efd7`).
- `fcn.180048780`: таблиця `data.182002520 + idx*8 + 0x328` @`0x180048845` /
  `0x180048875`; звичайний шлях `movups xmm0,[rax+0xc06]` @`0x18004887d`
  → `movups [rdi],xmm0` @`0x180048886`; альтернативний шлях перевіряє
  `test byte [rax+0x5e49],0x01` @`0x18004884d` і читає `[rax+0xc27]`
  @`0x180048856` → `[rdi]` @`0x18004885f`.
- Точні opcode-и підтверджені окремо: `0f1080060c0000` (`+0xc06`),
  `0f1080270c0000` (`+0xc27`).

**Статус: `statically proven`** для зсувів і напрямку читання (об'єкт →
вихідний `CUuuid`). На відміну від Linux, тут **не знайдено** копію цих 16 байт
у тіло UVM-запиту — `coverage limitation`, не доведення відсутності. Тип
структури з PE не відновлено — `UNPROVEN`.

## 4. Хто заповнює `+0xc06` / `+0xc27`

Writer A, `fcn.180409010`:

- @`0x1804091fc`: `var_998h = arg3 + 0x2e8 + i*0x198`;
- @`0x1804096e8`–`0x1804096ef`: `movups xmm0,[rcx-0xf0]` → `movups [rax+0xc06],xmm0`;
  джерело — `[arg3+0x1f8+i*0x198]`;
- прямий caller (Rizin `axt`): `(nofunc) 0x18040a09b [CALL] call fcn.180409010`;
  у caller-і `rdx=rbp` (буфер), `rcx=r14`, `r8=[rsp+0x68]`.

Writer B, функція з прологом @`0x18036d300`:

- @`0x18036d627`: `or byte [rbx+0x5e49],0x01` — вмикає альтернативний зсув;
- @`0x18036d637`–`0x18036d645`: `movups xmm0,[rdi+0x481]` → `movups [rbx+0xc27],xmm0`;
- @`0x18036d64c`–`0x18036d653`: ще 16 байт `[rdi+0x471]` → `[rbx+0xc16]`;
- адреса `0x18036d300` завантажується як дані в `fcn.18036bb70`
  (`lea rax,[data.18036d300]` @`0x18036bb70`), а `0x18036d300` викликає
  `0x18036bb70` @`0x18036d37d` — тобто Function B працює в парі з цим хелпером.

**Статус: `statically proven`** для writer-сайтів і обчислення адрес.
`UNPROVEN`: хто наповнює вихідні 16 байт у `arg3+0x1f8+i*0x198` і
`rdi+0x481`; Windows-еквівалент callback `[holder+0x30]` з Linux не знайдено.
Один прямий caller Writer A й одна DATA-адреса Writer B — не absence-proof.

## 5. `BDF ↔ RM gpu_id`

Read-only інвентар цієї машини: `NVIDIA GeForce GTX 1050 Ti`,
`DriverVersion=32.0.15.8278`,
`PNPDeviceID=PCI\VEN_10DE&DEV_1C82&SUBSYS_33511462&REV_A1\4&2DB3ECDA&0&0008`.
У `fcn.18020b620` D3DKMT-енумерація (__m128 `D3DKMTQueryAdapterInfo`)
порівнює vendor `0x10de` @`0x18020bc73` і збирає адаптери в таблицю
@`0x182025594`. Зв'язку з RM `gpu_id` чи UUID статично не знайдено:
`UNPROVEN`. Назви й рядки не використовувалися як доказ.

## 6. Зведена звірка

| Питання | Linux | Windows | Статус Windows |
|---|---|---|---|
| UVM-пристрій + `ioctl` | `/dev/nvidia-uvm`, `ioctl@plt` | `\\.\UVMLiteController` + `DeviceIoControl` у `nvcuda64.dll` | `statically proven` (механізм), код реєстрації — `UNPROVEN` |
| `UVM_REGISTER_GPU` | `0x25` @`0x449faf` | `0x22f000`, `0x22e028`, `0x8de0004`, `0x8de0008` у різних шляхів |Nr не збігається; відповідність `UNPROVEN` |
| 16-байтний UUID у payload | `movdqu [r13]` → payload | 16 байт читаються у вихід `CUuuid`; копію в payload не знайдено | `statically proven` для читання; `coverage limitation` для payload |
| `device+0xc06` | так | так, плюс альтернатива `+0xc27`/flag `+0x5e49` | `statically proven`; тип — `UNPROVEN` |
| Хто заповнює поле | `0xfaf660` → `[holder+0x30]`, ціль `UNPROVEN` | Writer A `0x1804096ef`, Writer B `0x18036d645`, джерела — `UNPROVEN` | `statically proven` для writer-ів |
| `BDF ↔ RM gpu_id` | `UNPROVEN` | `UNPROVEN` | `UNPROVEN` |
| Покриття | skipped intervals, `axt` empty | Rizin warnings, `invalid` slots, Ghidra недоступний | `coverage limitation` |

## 7. Межі й що не робилося

- Rizin: `bin_file_strings: search interval size (0x1848c00) exceeds max
  region size (0xa00000), skipping it`; ESIL `Cannot peek memory without
  specifying an address` для низки адрес; `invalid` @`0x18040979e`–
  `0x1804097a4`, `0x18036d6f3`–`0x18036d6f4`; `pdf @ 0x18036d300` →
  `Cannot find function at 0x18036d300`, хоча `pd` показує пролог.
- Не протрасовані indirect calls/`uxt`; `nvml.dll` і `nvlddmkm.sys` лише
  занесені в inventory (side-path перевірка не виконувалася).
- RM-ioctl, MMIO-записи, GPU compute, boot/reboot, firmware-зміни, PR #21 —
  `NOT RUN`. Пароль в експорті — `[REDACTED]`, не зберігався.
- Linux-сторона ще не звірила Evidence IDs; цей документ — Windows-внесок у
  спільний файл порівняння, а не підсумок остаточного cross-check.

## 8. Відкриті питання

1. Який Windows-код (`0x22f000`, `0x22e028` чи інакший) відповідає
   `UVM_REGISTER_GPU`, і який формат його payload?
2. Де Windows-хелпер копіює 16 байт UUID у тіло UVM-запиту?
3. Хто є початковим виробником 16 байт за `arg3+0x1f8+i*0x198` і
   `rdi+0x481`?
4. Чи існує Windows-еквівалент callback `[holder+0x30]`?
5. Як D3DKMT/BDF перетворюється на RM `gpu_id` і чи бере участь UUID?
