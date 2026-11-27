# 07 — Наступний напрям: від RM-ідентичності до керованого виконання

Цей документ описує **питання**, які ще треба перевірити, і порядок їх
перевірки. Усе нижче — `UNPROVEN`, доки не зʼявиться власний зонд із маркерами
та негативними перевірками. Документ не змінює SENS, CML, `wsm-os-lisp`,
їх ABI-pin чи ADR і не надає права на writable BAR0.

## Межа поточного знання

Наразі runtime-proven лише:

- ідентичність PCI/RM та шлях GPU-вузла з `minor_number`;
- RM-ланцюжок до `NV20_SUBDEVICE_0` і `MC_GET_ARCH_INFO`;
- явний `NV_ESC_RM_FREE` у зворотному порядку, включно з частковими відмовами;
- fail-closed BAR0-negative: `OPEN_DENIED`, `MMAP_DENIED`, BOOT0 `UNPROVEN`.

Немає жодного доведеного шляху подання команд, створення channel/context,
мапінгу BAR0, DMA/GVA, синхронізації чи запуску ядра. `arch=0x130/impl=0x7`
не є дозволом на ці дії.

## Розділення каналів

| Канал | Що вже є | Що далі | Межа |
|---|---|---|---|
| RM control (`/dev/nvidiactl`) | alloc/free, `GET_PROBED_IDS`, `ATTACH_IDS`, `GET_ARCH_INFO` | channel/context/notifier через публічні `NV_ESC_RM_ALLOC`/`RM_CONTROL` | угоди про RM-обʼєкти не дають MMIO |
| GPU fd (`/dev/nvidia<N>`) | open + `REGISTER_FD` у C-зонді | можливі шляхи подання команд/мапінгу буферів | тримати fd відкритим до cleanup |
| UVM (`/dev/nvidia-uvm`) | open у C-зонді | DMA/GVA, користувацькі буфери, page tables | не ототожнювати з RM device_id |
| sysfs PCI config/resource0 | identity, read-only open attempt | **не growth** у hosted-режимі | BOOT0 лишається UNPROVEN |
| Bare-metal/UEFI seam | відсутній | окремий читаць NV_PMC_BOOT_0 | не переносити на активний `nvidia.ko` |

## Пропоновані етапи

### E1 — Read-only trace cmd submission

Зняти власним LD_PRELOAD-shimом (не копіюючи vendor-код) послідовність
`ioctl`/`mmap` для `cuCtxCreate`, `cuStreamCreate`, `cuMemAlloc`,
`cuModuleLoadData`, `cuLaunchKernel`. Фіксувати лише: номер ioctl, напрямок,
розмір параметрів, імʼя публічної константи, повернутий статус.

Критерій green: таблиця спостережуваних викликів із двома незалежними
прогонами; негатив: будь-який невідомий request без окремого рядка `UNPROVEN`.

### E2 — Channel / context lifecycle

Перевірити, які RM-класи й параметри реально приймає R580 для створення
channel і context під уже створеним `NV01_DEVICE_0`/`NV20_SUBDEVICE_0`.
Не вигадувати class id: кандидати беруться лише з публічних SDK-імен,
підтверджуються власним `NV_ESC_RM_ALLOC` і Status=0.

Критерій green: alloc → control → free у зворотному порядку, як у G3;
негатив: інʼєкція часткової відмови звільняє рівно створені обʼєкти.

### E3 — Pushbuffer та command submission

Визначити мінімальний формат записів pushbuffer/GPFIFO з публічних
описань, зробити власні структури з compile-time `SizeOf`-assertами,
подати команду через підтверджений канал E2. Жодного `PROT_WRITE` на
`resource0`; буфери мають бути окремо виділені та перевірені.

Критерій green: власний маркер submitted/status=0 + звірений з trace
порядок полів; негатив: хибна розкладка ламає збірку.

### E4 — GPU sync

Дослідити семафори/fence/notifier як єдиний прийнятний механізм
синхронізації в hosted-зонді. Не використовувати busy-wait на незмапованому BAR0 і не
трактувати `rev=0xa1` як ознаку готовності пристрою.

Критерій green: два прогони з однаковим фінальним статусом і явним timeout;
негатив: timeout не приховується як успіх.

### E5 — MMIO map: тільки окремий seam

Дослідити читання/мапінгування BAR0 **окремо** від hosted Linux: UEFI,
bare-metal або ізольований processes з явно підтвердженим доступом. У цій
конфігурації `resource0` дає `OPEN_DENIED`/`MMAP_DENIED`, тому будь-який
`NV_PMC_BOOT_0` лишається `string-only`/`UNPROVEN`.

Критерій green: новий документ із явним власником доступу, chipset-маскою
і явним read; негатив: маркер BOOT0 не зʼявляється без реального read.

### E6 — DMA/GVA та kernel launch

Після E2–E4 перевірити, чи потрібні UVM-алокації, GVA-переклади й які
параметри grid/block/register/shared memory передаються у launch command.
Це найдальший і найменш певний етап: допускається лише інкрементальний
підтверджений піднабір, не «повний драйвер одразу».

Критерій green: мінімальне ядро з відтворюваним результатом; негатив:
відсутність будь-якого з етапів E1–E5 не компенсується припущенням.

## Заборони на всіх етапах

- Не писати в BAR0, не додавати `PROT_WRITE`, `MAP_FIXED`, `O_RDWR` до BAR-зонда.
- Не копіювати vendor header/source/decompiled код; лише власні flows, таблиці, ABI-факти й власний C/Pascal.
- Не оновлювати ABI pin у `wsm-os-lisp`, не оголошувати Contract 12 conformance
  без окремого owner-рішення й робочі runtime endpointи.
- Не перетворювати FPC research probes у нову основу Lisp-машини;
  механічні ABI-тести належать `wsm-lazarus`.
- Не змішувати hosted compute/RM/UVM із display/GOP/framebuffer або з bare-metal BOOT0.

## Статус цього документа

Усе, крім посилань на вже виконані G0–G3, має стан **UNPROVEN**.
Це план дослідження, не доказ і не дозвіл на зміну системних контрактів.
