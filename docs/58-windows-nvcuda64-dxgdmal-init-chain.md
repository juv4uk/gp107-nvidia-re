# 58 — Windows `nvcuda64.dll`: хто саме заповнює `0x28f8` для Writer A

Продовження [`docs/56`](56-windows-nvcuda64-uuid-writer-dataflow.md) і [`docs/57`](57-windows-cudevicegetuuid-chain.md) на тому самому активному бінарнику. Дозвіл і межі — [`docs/55`](55-windows-reverse-scope-and-artifacts.md). Тільки статичний Rizin-розбір; жодного процесу, ioctl чи GPU-дії не виконувалося.

Evidence: `evidence/windows-20261128/nvcuda64-dxgdmal-init-chain.json`.

## 0. Суб'єкти

| Бінарник | SHA-256 | Роль |
|---|---|---|
| `nvcuda64.dll`, `32.0.15.8278` | `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407` | CUDA userspace, Writer A/B, експорти `cuDeviceGetUuid` |
| `nvdxgdmal64.dll` | `9353f1b598f2c8649a33b59db011763474e8ef2a6749385a23d9f78af25feceb` | супутній DLL з того самого `DriverStore`, постачає `dxgdmal*` і D3DKMT-обгортку |

Другий hach записаний окремо; `docs/55` його не містив. Файл знайдено statically — за рядком `nvdxgdmal64.dll` у `nvcuda64.dll` — і хешовано read-only. Обидва бінарники в репозиторій не копіювалися.

## 1. Ініціалізація `iface` у `nvcuda64.dll`

Прямий запис глобала знайдено лише один: `0x180413615: mov qword [0x182004658], rax` (evidence `ev_0cdef301…`). Функція навколо `0x1804135e0` робить `LoadLibraryA` для `nvdxgdmal64.dll` і розв'язує чотири експорти:

| Слот | Значення | Доказ |
|---|---|---|
| `[iface+0xb8]` | `HMODULE` `nvdxgdmal64.dll` | `ev_048e466…` |
| `[iface+0xc0]` | `dxgdmalEnumAdapters` | `ev_5672166a…` |
| `[iface+0xc8]` | `dxgdmalGetAdapterCallbacks` | `ev_5672166a…`, `ev_a0355e…` |
| `[iface+0xd0]` | `dxgdmalImportFromExternalDescriptor` | `ev_5672166a…` |
| `[iface+0xd8]` | `dxgdmalDestroyExternalDescriptorObjects` | `ev_5672166a…` |

Отже питання з `docs/56` §2 «яка функція стоїть у `[iface+0xc8]`» закрите: це **`dxgdmalGetAdapterCallbacks`**. **Статус: `statically proven`**.

Уточнення щодо evidence: дамп `pd 45 @ 0x180413990` починається серединою інструкції, тому призначення слотів звірялося з вирівняним `pd 80 @ 0x180413960` і з `af/pdf`, а не з сирим рядком `mov eax, 0xff000000`.

## 2. Що робить `dxgdmalGetAdapterCallbacks`

Експорт за адресою `0x180001010` (evidence `ev_53bf8eec…`, `ev_489637bc…`):

- перевіряє ненульовий дескриптор і `[desc] >= 0x38`;
- бере `rax = [desc+0x10]`;
- пише його у вихідний вказівник `rdx` і повертає `0`; інакше повертає `1`.

Тобто він публікує **таблицю методів адаптера**, яка лежить за зсувом `+0x10` дескриптора. Це не запис UUID і не ioctl. **Статус: `statically proven`**.

## 3. Таблиця методів і шлях до `D3DKMTQueryAdapterInfo`

`nvdxgdmal64.dll` будує таблицю в `0x180006480` (evidence `ev_bd00532a…`, `ev_8f4185a3…`):

| Зсув таблиці | Значення |
|---|---|
| `+0x00` | `0x60` — розмір дескриптора |
| `+0x08` | `0x1800052c0` |
| `+0x10` | `0x180006b40` |
| `+0x18` | `0x180005540` |

Дескриптор отримує вказівник на таблицю в `[desc+0x10]` (`0x180006588`). У `nvcuda64.dll` зворотний виклик `0x180409f50` після `call [iface+0xc8]` робить `call qword [table+0x18]` (`0x180409fce`) — тобто викликає **`0x180005540`** (evidence `ev_997f2fdc…`).

Імпорти D3DKMT розв'язуються динамічно; `[0x18008d088]` = `D3DKMTQueryAdapterInfo`, `[0x18008d090]` = `D3DKMTCloseAdapter`, `[0x18008d098]` = `D3DKMTEnumAdapters2`, `[0x18008d0a0]` = `D3DKMTEnumAdapters3` (evidence `ev_1528ae5f…`; повний перелік рядків — `ev_ee7caa2a…`, `ev_c71f4473…`).

Метод `0x180005540` викликає `QueryAdapterInfo` з numeric type `0x31`, `0x0f`, `0x30` (розмір виходу `0x428`) і `0x25`, а також перетворює UTF-16-шлях із результату запиту, знімає префікс `\SystemRoot\` і розкриває його через `GetWindowsDirectoryA` (evidence `ev_28dc67dd…`). Числові типи подані як спостережені константи: публічні заголовки D3DKMT у цьому lane не відкривалися.

Фільтр адаптера в `dxgdmalEnumAdapters`: `cmp eax, 0x10de` або `cmp eax, 'NVDA'` (`0x4144564e`), далі перевірка `>= 0x7d0`, побудова дескриптора `0x180006440` і виклик користувацького callback-а (evidence `ev_89d52c79…`). **Статус: `statically proven`** для всього ланцюга викликів.

## 4. Що саме доводить `docs/56` і `docs/57`

Ланцюг тепер виглядає так:

```
cuInit -> 0x1800660e0 -> 0x18018b4a0 -> 0x18018c0c0   (стан ініціалізації)
       -> LoadLibraryA(nvdxgdmal64.dll) + GetProcAddress(dxgdmal*)
       -> [iface+0xc8] = dxgdmalGetAdapterCallbacks
       -> [desc+0x10] = table, table[0x18] = 0x180005540
       -> D3DKMTQueryAdapterInfo (типи 0x31/0x0f/0x30/0x25)
       -> об'єкт 0x28f8 -> [iface+0xc8]-шлях -> Writer A (0x180409010)
       -> [device+0xc06] -> cuDeviceGetUuid / _v2 -> 16 байт
```

Стан ініціалізації: `fcn.18018c0c0` перевіряє магію `[0x182002830] == 0xabc123`, кількість `[0x182002a48]` і перебирає `[0x182002520 + idx*8]`, тестуючи `[device+0x5e49] & 0x40` (evidence `ev_6099bfe6…`). Помилкові стани включають `0x321cba00` (evidence `ev_9d89f054…`). Таблиця `[0x182002520]` спочатку нулюється на `0x12c8` байт у `0x18018b4a0` (evidence `ev_0b38e245…`); хто саме записує туди заповнені об'єкти, у цьому вікні не знайдено.

**Статус: `statically proven`** для маршруту викликів і для адресування. **UNPROVEN** для тотожності 16 байт і їх кінцевого виробника.

## 5. Межі доказів

| Твердження | Статус |
|---|---|
| `[iface+0xc8]` = `dxgdmalGetAdapterCallbacks` | `statically proven` |
| `dxgdmalGetAdapterCallbacks` публікує `[desc+0x10]` | `statically proven` |
| `table[0x18]` = `0x180005540`, який викликає `D3DKMTQueryAdapterInfo` | `statically proven` |
| Фільтр адаптера `0x10de` / `'NVDA'` | `statically proven` |
| `cuInit` проходить через `0x18018c0c0` і магію `0xabc123` | `statically proven` |
| Яке саме поле D3DKMT/приватних даних стає 16 байтами | `UNPROVEN` |
| Чи є ці 16 байт саме UUID GPU | `UNPROVEN` |
| Хто пише заповнені об'єкти в `[0x182002520+idx*8]` | `UNPROVEN` |
| RM/NVML/D3DKMT/PCI BDF як кінцеве джерело | `UNPROVEN` |
| `BDF_TO_RM_GPU_ID` | `UNPROVEN` |
| Виконання будь-якого шляху на цій машині | `NOT RUN` |

Coverage limitations: Ghidra двічі не завершив імпорт/аналіз 34 MB DLL у межах 900000 ms (`provider_timeout`), тому Ghidra-xrefs не заявляються; Rizin не зберігає аналіз між викликами, отже `axt` виконувався лише в одній команді з `aaa`; частина `pd`-вікон починалася серединою інструкції й використовувалася лише для звірки з вирівняними `af/pdf`; пошук абсолютних адрес через `/a` і сирі байти для RIP-relative посилань не спрацював.

Жодного RM/UVM/D3DKMT ioctl, `cuInit`, `cuDeviceGetUuid`, CUDA/Vulkan/OpenGL init, GPU submit, MMIO, firmware, reboot, tag чи release не виконувалося. Наступний безпечний крок — звузити поле всередині приватного буфера адаптера, лишаючись у статичному Rizin-розборі тих самих двох hach-ів.
