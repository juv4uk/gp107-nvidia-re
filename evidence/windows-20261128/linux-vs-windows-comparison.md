# Linux ↔ Windows: порівняльний каркас REA P1

Цей файл створено на Linux-стороні для заповнення на Windows-стороні.
Джерело — shipped-артефакти, без vendor source і без Ghidra-pseudocode.
Кожен рядок Windows-колонки має містити artifact SHA-256, tool/version,
адресу/функцію, xrefs/caller/callee, статус і unanswered question.

## 1. Linux-сторона (вже отримано)

### 1.1 Артефакти

| Артефакт | SHA-256 | Статус |
|---|---|---|
| `/usr/lib/x86_64-linux-gnu/libcuda.so.580.196.11` | `20ad440390dad2c5fd06c14e518990512a8e7b31f8b6add7bb1581832fd4d331` | `statically proven` для шляху UUID → UVM ioctl |
| `/tmp/opencode/rea-nvidia-uvm/nvidia-uvm.ko` | `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` | `runtime-proven` pairing з встановленим `nvidia_uvm` |
| `/tmp/opencode/rea-nvidia-uvm/nvidia.ko` | `95c5fa5ab0546ee40842cda2ec20ea3ec1e196a5afee1580944ecae2ffc75bbe` | `statically proven` forwarding UUID у RM |

### 1.2 Ключові ланцюги

**Kernel UVM → RM (`docs/40`):**
- `uvm_gpu_retain_by_uuid` calls `nvUvmInterfaceGetGpuInfo` at Rizin `0x0801ea10` і `0x0801eadb` з `rdi=r12` = UUID.
- `nvidia.ko`: `nvUvmInterfaceGetGpuInfo @0x0801ff80` → `rm_gpu_ops_get_gpu_info @0x08da2df0` → `_nv046828rm @0x080e0c30`; UUID forwarded як перший аргумент.
- Напрямок UUID: **вхід** в `GetGpuInfo`, не вихід. Гіпотеза про генерацію — `retracted hypothesis`.

**Userspace (`docs/41`):**
- `libcuda` містить `/dev/nvidia-uvm`, імпортує `ioctl`/`open`.
- `UVM_REGISTER_GPU` = `0x25` (`docs/ioctl-map.md`).
- Єдиний targeted `ioctl(fd,0x25,…)` call-site: `0x449faf` у хелпері `0x449f40`.
- Хелпер копіює 16 байт першого аргументу в ioctl-payload.
- Два протрасовані caller-и передають `&device+0xc06`: `0x320b56`, `0x320c8d`.
- `cuDeviceGetUuid @0x37aa70` → dispatch `[0x5bd48f0]` → `0x38c1d0`, який читає `[device+0xc06]` у вихідний `CUuuid` (`0x38c257`).
- `0xfaf660` заповнює буфер через callback `[holder+0x30]`; verified callers `0x3031ae`, `0x46a6d5`.
- Слот `+0x30` нульовий у shipped-файлі; runtime-ціль callback-а не спостережена → `UNPROVEN`.

### 1.3 Статуси Linux-сторони

| Твердження | Статус |
|---|---|
| UUID = перше поле ioctl-параметра в `uvm_gpu_retain_by_uuid` | `statically proven` |
| UUID йде **в** `nvUvmInterfaceGetGpuInfo` і далі в RM | `statically proven` |
| `nvUvmInterfaceGetGpuInfo` як джерело UUID | `retracted hypothesis` |
| `ioctl(fd,0x25,…)` у `libcuda` і копія 16 байт у payload | `statically proven` |
| `device+0xc06` як спільне джерело `cuDeviceGetUuid` і UVM-реєстрації | `statically proven` |
| Кінцевий виробник `device+0xc06`, `BDF ↔ RM gpu_id` | `UNPROVEN` |
| Непрямі виклики / пропущені REA-інтервали / третій caller `0x46f03e` | `coverage limitation` |
| MMIO, RM-ioctl, GPU compute, boot/reboot, PR #21 | `NOT RUN` |
| BOOT0 / `0x137000A1` | `UNPROVEN` / `string-only` |
| Пароль у чат/файли | не зберігався; в експорті — `[REDACTED]` |

### 1.4 Інструменти

- REA `execute_rizin_command`, `rizin 0.9.1 @ linux-x86-64`, provider version `null`.
- GNU `objdump`/`readelf`/`strings`, Binutils `2.47.50.20261021`.
- FPC `3.2.2`; gate: `CAPABILITY-DRIVER-GATE-OK c11=yes fpc=3.2.2 layout=32/68/140 fail-closed=passed mmio=deferred safe-offset=unproven pascal=C-parity hardware-mmio=NOT-AUTHORIZED/NOT-RUN`.

## 2. Windows-сторона (заповнено 2026-11-28)

> Не запускати PR #21. Не робити write-MMIO, RM-ioctl, reboot, firmware-змін.
> Не копіювати vendor source — лише shipped-артефакти й власні нотатки.
> Усі адреси — віртуальні адреси PE-образа `nvcuda64.dll` (image base `0x180000000`).

### 2.0 Артефакти й інструменти

| Артефакт | SHA-256 | Версія файлу | Роль |
|---|---|---|---|
| `C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_58519edca6172ba9\nvcuda64.dll` | `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407` | `32.0.15.8278` (ресурс: `NVIDIA CUDA Driver, Version 582.78`, `CUDA 13.0.100 driver`) | основний Windows-відповідник `libcuda` |
| `C:\Windows\System32\nvcuda.dll` | `60a0f34f4e28bd305a1fe009635ccd62e7f4b6ed1500692adaf4a0eeb2cd0a91` | `32.0.15.8278` | loader-only: `DeviceIoControl` відсутній; реальна реалізація — у `nvcuda64.dll` |
| `C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_58519edca6172ba9\nvlddmkm.sys` | `ae93846067fbb17327d0fc970ce23c533922e811199830d5ac469523c9ca78a3` | `32.0.15.8278` | kernel-кандидат; **проаналізовано тільки inventory** |
| `C:\Windows\System32\nvml.dll` | `c53e981ac0d01410dba1e9e11f74ea80c7bcb0a2150b68c4a9c99bd38cac4774` | `8.17.15.8278` | NVML side-path кандидат; **проаналізовано тільки inventory** |

Tool/version (усі рядки таблиці нижче): REA `execute_rizin_command`, `rizin 0.9.1 @ windows-x86-64`, commit `c3a90e9226d977f58f4e9c75f78fa6b07afe13c7`. REA Ghidra-провайдер недоступний (`Set GHIDRA_INSTALL_DIR to an extracted Ghidra 12.x (>=12.2) release directory.`) — декомпіляторного cross-check немає.

### 2.1 Таблиця звірки

| Питання | Linux-результат | Windows-результат | Збіг? | SHA / tool / адреса / xrefs | Статус | Unanswered question |
|---|---|---|---|---|---|---|
| Який shipped DLL/DRV містить `/dev/nvidia-uvm`-еквівалент і `ioctl`-еквівалент? | `libcuda.so.580.196.11`, `ioctl@plt` | `nvcuda64.dll`: UTF-16 `\\.\UVMLiteController` @`0x181e803c0`; data-xrefs @`0x1801f00d6` (`fcn.1801f0040`), `0x1803399b4`, `0x18033a834`, `0x1803c58b7`, `0x1803e49f6`. Open-helper `0x1803395b0` → `CreateFileW` @`0x18033960d`; IOCTL-helper `0x1803396c0` → `DeviceIoControl` @`0x1803396f3`. Окремий шлях `\\.\NvAdminDevice` @`0x18020b8be` (`CreateFileA`), handle @`0x182025550`. | частково: механізм той самий (`CreateFile*` + `DeviceIoControl`), пристрій і коди інші | SHA `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407`; rizin 0.9.1; `axt @ 0x181e803c0`, `pd @ 0x1803395b0`, `pd @ 0x1803396c0` | `statically proven` для наявності шляху й helper-ів; назва шляху сама по собі — `string-only` | Який саме IOCTL виконує реєстрацію GPU: `0x22f000`, `0x22e028` чи інший? |
| Чи існує еквівалент `UVM_REGISTER_GPU (0x25)`? | `0x449faf`, nr `0x25` | У targeted UVMLiteController-шляху: `dwIoControlCode=0x22f000` @`0x1803399e4` (in-size `0x104`) і `0x22e028` @`0x18033a880` (in/out 8). В адміністративному шляху: `0x8de0004` @`0x18020b438` (`fcn.18020b3c0`, in/out `0x88`) та `0x8de0008` @`0x18020c3f9` (`fcn.18020c350`, in `0x5c`). Жодного `0x25` у цих call-site не знайдено. | ні: nr відрізняється; відповідність не доведена | SHA `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407`; rizin 0.9.1; `fcn.18020b3c0` / `fcn.18020c350`, IAT `DeviceIoControl` @`0x18184a3b8` | `statically proven` для числових кодів; `UNPROVEN` для відповідності `0x25` | Який Windows-код і який payload відповідає Linux `UVM_REGISTER_GPU`? |
| Чи копіюється 16-байтний UUID у payload? | `movdqu xmm1,[r13]` → `[rbp-0x60]`, далі в ioctl-payload @`0x449faf` | `cuDeviceGetUuid @0x180280540` → `[0x181ffa340]` → `0x180280320` → `fcn.180048780` (call @`0x18028039a`, `0x1802804d7`); `_v2 @0x18021f040` → `[0x181ffa868]` → `0x18021ee20` → ті ж call @`0x18021ee9a`, `0x18021efd7`. Хелпер копіює 16 байт **зі структури у вихід** (`[rax+0xc06]` @`0x18004887d` → `[rdi]` @`0x180048886`). Копію саме в IOCTL-payload не знайдено. | частково: той самий 16-байтний UUID, але напрямок — у вихід CUDA, а не в payload | SHA `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407`; rizin 0.9.1; `axt @ 0x180048780`, `pdf @ 0x180280320`, `pdf @ 0x18021ee20` | `statically proven` для читання UUID; `coverage limitation` для payload-копії | Де саме Windows-хелпер маршалить UUID у тіло UVM-запиту? |
| Чи є поле-еквівалент `device+0xc06`? | так, `cuDeviceGetUuid` читає `[device+0xc06]` @`0x38c257` | так: той самий offset `+0xc06` у структурі пристрою; альтернативний слот `+0xc27` з прапорцем `byte [obj+0x5e49] & 1` @`0x18004884d`. База — таблиця `data.182002520 + idx*8 + 0x328` @`0x180048845`/`0x180048875`. Тип структури з PE не відновлено. | так (offset збігається) | SHA `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407`; rizin 0.9.1; `fcn.180048780`, `0f1080060c0000` / `0f1080270c0000` | `statically proven` для offset-ів; тип — `UNPROVEN` | Який C-тип і повний layout структури з `+0xc06`/`+0xc27`/`+0x5e49`? |
| Хто заповнює це поле? | `0xfaf660` → callback `[holder+0x30]`, ціль `UNPROVEN` | Writer A: `fcn.180409010` @`0x1804096ef` `movups [rax+0xc06],xmm0` з `[rcx-0xf0]`; джерело обчислено @`0x1804091fc` як `arg3 + 0x2e8 + i*0x198`, тобто `[arg3+0x1f8+i*0x198]`; прямий caller — `(nofunc) 0x18040a09b`. Writer B: `0x18036d645` `movups [rbx+0xc27],xmm0` з `[rdi+0x481]`; прапорець `or byte [rbx+0x5e49],1` @`0x18036d627`; функція починається @`0x18036d300`, ії адреса завантажується як дані в `fcn.18036bb70` @`0x18036bb70`. | частково: writer-и знайдені, початкове джерело — ні | SHA `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407`; rizin 0.9.1; `axt @ 0x180409010`, `axt @ 0x18036d300`, `pd @ 0x18036d300`, `pd @ 0x18040a060` | `statically proven` для writer-сайтів і розрахунку адреси; `UNPROVEN` для походження вихідних 16 байт | Хто наповнює `arg3+0x1f8+i*0x198` та `rdi+0x481`? Чи є Windows-еквівалент callback `[holder+0x30]`? |
| Чи прослідковується `BDF ↔ RM gpu_id`? | `UNPROVEN` | Read-only інвентар: `PNPDeviceID=PCI\VEN_10DE&DEV_1C82&SUBSYS_33511462&REV_A1\4&2DB3ECDA&0&0008`, driver `32.0.15.8278`. У `fcn.18020b620` D3DKMT-енумерація порівнює vendor `0x10de` @`0x18020bc73`; жодного зв'язку з RM `gpu_id` або UUID не знайдено. | ні | SHA `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407` (DLL), `60a0f34f4e28bd305a1fe009635ccd62e7f4b6ed1500692adaf4a0eeb2cd0a91` (loader); rizin 0.9.1; `fcn.18020b620`, `0x18020bc73` | `UNPROVEN`; name-only/string-only не використовувався | Як Windows BDF/D3DKMT handle перетворюється на RM `gpu_id` і чи бере участь UUID? |
| Які обмеження покриття? | REA skipped intervals, `axt` empty, третій caller `0x46f03e` | Rizin: `bin_file_strings: search interval size (0x1848c00) exceeds max region size (0xa00000), skipping it`; ESIL `Cannot peek memory without specifying an address` для низки адрес; `invalid` у `0x18040979e`–`0x1804097a4`, `0x18036d6f3`–`0x18036d6f4`; `pdf @ 0x18036d300` → `Cannot find function at 0x18036d300`, хоча `pd` показує пролог. Ghidra-провайдер REA недоступний. `nvml.dll`/`nvlddmkm.sys` — тільки inventory. Indirect calls/`uxt` не протрасовані. | обидві сторони мають прогалини | ті самі SHA; rizin 0.9.1; логи у `win-evidence/*-utf8.txt` | `coverage limitation`, не absence-proof; RM-ioctl/MMIO/compute/boot — `NOT RUN` | Чи змінить висновки повний Ghidra-прохід і динамічний read-only trace? |


## 3. Порядок звірення

1. Заповнити таблицю §2 на Windows, зберігши цей самий файл (або новий з суфіксом `-windows.md`).
2. Повернути файл у `/home/agents/gp107-nvidia-re/` або в цей самий каталог на Ventoy.
3. Linux-сторона звіряє SHA-256 артефактів і Evidence IDs, позначає кожен рядок як `statically proven` / `runtime-proven` / `UNPROVEN` / `coverage limitation`.
4. Лише після звірки — окремий research-документ `docs/42-...` у репозиторії. Без release/tag/publish.

## 4. Файли поруч

- `conversation-linux-export.md` / `.json` — експорт видимих user/assistant повідомлень цієї сесії з OpenCode DB (без reasoning і сирих tool results, з redaction).
- `linux-evidence/docs-40-rea-p1-gpu-info-uuid-direction.md`
- `linux-evidence/docs-41-rea-p1-libcuda-userspace-uuid-source.md`
- `linux-evidence/libcuda-uuid-to-uvm-ioctl.txt`
- `linux-evidence/evidence-p1-libcuda-uuid.json`
- `linux-evidence/linux-state.txt`
- `SHA256SUMS.txt` — контрольні суми всіх файлів цього експорту
