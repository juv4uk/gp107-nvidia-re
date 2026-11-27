# Відкритий графічний стек NVIDIA для GP107 / GTX 1050 Ti

> Стан огляду: 2026-11-27. Це початкова карта дослідження, а не твердження про повну функціональність кожної конкретної плати.

## 1. Цільова карта обладнання

Ціль цього дослідження — NVIDIA GeForce GTX 1050 Ti на Pascal GP107:

- PCI vendor/device: `10de:1c82`.
- Власний Windows hardware ID, раніше зафіксований власником: `SUBSYS_33511462`, revision `A1`; у форматі PCI це subsystem vendor/device `1462:3351` (MSI).
- Публічні PCI-записи та апаратні звіти пов'язують `1462:3351` з MSI GTX 1050 Ti Gaming X 4G. Це **ймовірна board SKU**, а не остаточно доведена ідентифікація: підтвердити наклейкою на платі або VBIOS board name/hash.
- MSI для моделі GTX 1050 Ti GAMING X 4G вказує GP107-400, 4 GB GDDR5, 128-bit memory bus, 6-pin power connector і 75 W specification. Ці параметри застосовувати до нашої плати лише після підтвердження SKU.
- Кодове ім'я: GP107, сімейство Pascal / NV130.
- Архітектура обчислювальних ядер: `sm_61`.
- Профіль цього репозиторію для пропрієтарного порівняння: Linux x86-64, NVIDIA R580 `580.196.11`, Kali Rolling, kernel `7.2.15+kali-amd64`, FPC 3.2.2.

PCI ID перевіряється за [envytools PCI ID database](https://github.com/envytools/envytools/blob/master/docs/hw/pciid.rst). Точна плата/Subsystem ID, VBIOS та обсяг VRAM мають фіксуватися окремо: назва GTX 1050 Ti не ідентифікує виробника плати й варіант BIOS.

## 2. Висновок: відкритий драйвер уже існує

Для GP107 базовий відкритий стек — **Linux `nouveau` + Mesa**:

1. **Ядро Linux / DRM Nouveau** — PCI probe, modesetting, керування пам'яттю, GPU objects, каналами команд, перериваннями й апаратними підсистемами через NVKM.
2. **Mesa Nouveau Gallium** — OpenGL для старіших NVIDIA GPU, включно з Pascal.
3. **Mesa NVK** — відкритий Vulkan-драйвер; підтримку Pascal оголошено 22 квітня 2025 року.
4. **NAK** — backend-компілятор шейдерів, який використовується NVK.
5. **Zink** — OpenGL поверх Vulkan. Документація Mesa вказує, що NVK+Zink став типовим OpenGL шляхом для Turing і новіших GPU; для GP107 не слід припускати, що Zink є типовим шляхом. Для GP107 досліджуємо традиційний Nouveau Gallium OpenGL окремо від NVK Vulkan.

Офіційна сторінка Nouveau описує Vulkan як підтримуваний на Kepler і новіших GPU; Mesa вказує мінімум Linux 6.6 для NVK. Важливо не переносити загальне формулювання Mesa про Vulkan 1.4 на Pascal без перевірки per-device API version: у поточному `src/nouveau/vulkan/nvk_physical_device.c` функція `nvk_get_vk_version()` повертає Vulkan 1.3 для всіх `cls_eng3d < TURING_A`, оскільки `hostImageCopy`, необхідний для Vulkan 1.4, у цій реалізації доступний лише на Turing+. GP107/Pascal належить до цієї гілки й тому має повідомляти **Vulkan 1.3**, а не 1.4. Окремо `nvk_is_conformant()` допускає discrete GPUs від Kepler до Ada, тож Pascal входить у conformant-набір, але з API version 1.3. Остаточний runtime proof для нашої плати — `apiVersion` із `vulkaninfo --summary` або Vulkan physical-device properties на реальному GP107.

Поточний код для цього висновку зафіксований на snapshot commit [`b602686e3008239284315b67f7aea226bb8d2af2`](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/b602686e3008239284315b67f7aea226bb8d2af2/src/nouveau/vulkan/nvk_physical_device.c): перевірки `cls_eng3d < MAXWELL_A` → 1.2, `cls_eng3d < TURING_A` → 1.3, інакше → 1.4; окрема conformance-функція включає Kepler–Ada та Blackwell B.

Джерела:
- [Nouveau — current status](https://nouveau.freedesktop.org/)
- [Mesa — NVK](https://docs.mesa3d.org/drivers/nvk.html)
- [Collabora: NVK enabled for Maxwell, Pascal and Volta, 2025-04-22](https://www.collabora.com/news-and-blog/news-and-events/nvk-enabled-for-maxwell,-pascal,-and-volta-gpus.html)
- [Linux kernel — Nouveau driver documentation](https://github.com/torvalds/linux/blob/master/Documentation/gpu/nouveau.rst)
- [Mesa NVK physical-device API-version and conformance logic (pinned source snapshot)](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/b602686e3008239284315b67f7aea226bb8d2af2/src/nouveau/vulkan/nvk_physical_device.c)

## 2.1. OpenCL через Mesa Rusticl: окремий експериментальний шлях

Окрім Vulkan/NVK, для compute існує інший відкритий шлях: **Nouveau Gallium → Mesa Rusticl → OpenCL**. Rusticl є реалізацією OpenCL поверх Gallium, а не CUDA runtime або сумісним шаром CUDA. Його документація перелічує `nouveau` серед драйверів із «decent support», але попереджає про можливі conformance issues/bugs. Пристрої не рекламуються автоматично: потрібен явний opt-in через `RUSTICL_ENABLE`.

Перший безпечний runtime probe на окремому Nouveau boot:
```sh
RUSTICL_ENABLE=nouveau clinfo
```
Зберегти OpenCL platform/device/vendor/version та extensions. Якщо пристрій з'являється, наступний тест — мінімальний vector-add із перевіркою результату, потім відповідний піднабір OpenCL CTS. Не називати шлях робочим на GP107 до проходження цих свідків; не змішувати OpenCL результати з NVK/Vulkan.

Джерела:
- [Mesa Rusticl — OpenCL on top of Gallium and enablement requirement](https://docs.mesa3d.org/rusticl.html)
- [Mesa environment variables — `RUSTICL_ENABLE` and supported drivers](https://docs.mesa3d.org/envvars.html#rusticl-environment-variables)

## 3. Головне обмеження Pascal: reclocking

Це найважливіша перешкода для практичного використання Nouveau на GP107.

Сторінка Nouveau пояснює:
- автоматичний reclocking через GSP firmware є для Turing і новіших GPU;
- ручне керування performance level підтримується для окремих старіших сімейств, але GP10x до цього переліку не входить;
- для GP10x необхідний firmware-доступ, який тепер має бути підписаний NVIDIA.

У матеріалі Collabora від 2025-04-22 окремо сказано, що Pascal та інші старі покоління здебільшого залишаються на boot clocks через firmware limitations. Тому підтримка NVK/Vulkan не означає, що GTX 1050 Ti працюватиме на повних частотах або матиме продуктивність пропрієтарного R580.

**Наслідок:** у тестах обов'язково розділяти:
- функціональність (чи працює OpenGL/Vulkan, пам'ять, подання команд);
- продуктивність на фактичних частотах;
- можливості керування частотами/живленням.

Не трактувати низьку продуктивність як автоматичну помилку компілятора або Vulkan-драйвера, поки не перевірені частоти та power state.

Джерела:
- [Nouveau current status — reclocking](https://nouveau.freedesktop.org/)
- [Collabora — Pascal and boot clocks](https://www.collabora.com/news-and-blog/news-and-events/nvk-enabled-for-maxwell,-pascal,-and-volta-gpus.html)

## 4. Чому NVIDIA Open GPU Kernel Modules не є шляхом для GTX 1050 Ti

Репозиторій NVIDIA `open-gpu-kernel-modules` прямо обмежує сумісність Turing і новішими GPU. Документація NVIDIA з модулів також вказує, що Maxwell, Pascal і Volta потребують proprietary flavor kernel modules.

Отже:
- не намагатися зібрати `nvidia-open` для GP107 — це не підтримувана архітектура;
- не плутати відкриті kernel modules для Turing+ з повністю відкритим драйверним стеком;
- для Pascal вибір між vendor proprietary R580 і upstream Nouveau/Mesa.

За довідкою NVIDIA, Linux R580 — остання гілка, що підтримує Maxwell, Pascal і Volta. Репозиторій фіксує тестовий vendor baseline R580 `580.196.11`; це корисна контрольна точка, а не довгострокова відкрита стратегія.

Джерела:
- [NVIDIA/open-gpu-kernel-modules — compatible GPUs](https://github.com/NVIDIA/open-gpu-kernel-modules)
- [NVIDIA Driver Installation Guide — kernel module flavors](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/kernel-modules.html)
- [NVIDIA — Unix legacy GPU support timeframes](https://nvidia.custhelp.com/app/answers/detail/a_id/3142/kw/experience)
- [NVIDIA R580.196.11 release notes](https://docs.nvidia.com/datacenter/tesla/tesla-release-notes-580-196-11/index.html)

## 5. Nova: стежити, але не планувати для GP107

У документації ядра Linux з'явився проєкт `nova` (`nova-core` + `nova-drm`), який має замінювати Nouveau для NVIDIA GPU на базі GSP. Це перспективний напрям для новіших поколінь, але GP107/Pascal не має GSP-моделі, на якій побудований цей драйвер.

Тому Nova варто відстежувати як загальний розвиток відкритого NVIDIA стека, але не включати до поточного плану реалізації для GTX 1050 Ti.

Джерело: [Linux kernel — Nova NVIDIA GPU drivers](https://docs.kernel.org/gpu/nova/index.html).

## 6. Інструменти для дослідження GP107

### Envytools — апаратна довідка (не повний Pascal SASS decoder)

[envytools](https://github.com/envytools/envytools) — спільнотний набір інструментів і баз даних:

- `nvbios` — декодування структур VBIOS;
- `envydis` — дизасемблер/асемблер NVIDIA GPU ISA;
- `rnndb` — база MMIO-регістрів, FIFO methods і структур пам'яті;
- `nva` — прямий доступ до GPU-регістрів;
- `demmt` та пов'язані засоби — аналіз потоків/методів GPU.

Для першого проходу використовувати `nvbios`, перегляд RNND/документації й статичне декодування. `nva` має прямий доступ до апаратури: не виконувати команди запису, поки окремо не визначено безпечний read-only режим і не створено ізольований стенд.

Джерела:
- [envytools repository](https://github.com/envytools/envytools)
- [envytools hardware docs](https://envytools.readthedocs.io/)
- [GP107 PCI IDs](https://github.com/envytools/envytools/blob/master/docs/hw/pciid.rst)

### Mesa/NVK для аналізу команд і компілятора

Mesa документує корисні прапорці:
- `NAK_DEBUG=print` — вивід проміжних стадій компіляції шейдера;
- `NVK_DEBUG=push,push_sync` — дамп pushbuffer з очікуванням завершення submit;
- `NVK_DEBUG=vm` — журнал прив'язування/відв'язування GPU VA.

Ці можливості корисні для зіставлення того, що формує користувацький драйвер, із низькорівневим протоколом. Спочатку використовувати їх на тестовій системі й зберігати повні журнали з версіями Mesa/kernel.

Джерело: [Mesa NVK debugging options](https://docs.mesa3d.org/drivers/nvk.html#debugging).

### Власний інструментарій цього репозиторію

Уже наявні:
- REA/Ghidra для статичного аналізу vendor `libcuda.so`;
- FPC 3.2.2 та clean-room probes для відкритого ioctl ABI;
- C probe без `libcuda`;
- декодер ioctl і fail-closed гейти;
- evidence-розмежування `statically proven`, `runtime-proven`, `observed`, `interpretation`, `UNPROVEN`.

Цей інструментарій досліджує **пропрієтарний RM ABI**. Він не є самим Nouveau і не повинен змішувати vendor-specific висновки з upstream Nouveau implementation.

## 7. Дві паралельні лінії роботи

### Координація із окремим RM lifecycle / command-submission планом

Паралельний документ [`docs/06-next-research-direction.md`](06-next-research-direction.md)
веде vendor R580 ABI напрям E1–E6: read-only ioctl trace, channel/context
lifecycle, pushbuffer, GPU sync, ізольований MMIO seam та DMA/GVA/kernel launch.
Він належить до proprietary RM reverse engineering і лишається окремою
доказовою лінією. Ця карта зосереджена на upstream open-source Nouveau/Mesa,
тому не дублює E1–E6 і не змінює його безпечні межі.

### A. Реверс-інжиніринг vendor R580 ABI (поточна лінія репозиторію)

Уже зафіксовано:
- шлях `cuInit` → `/dev/nvidiactl`, `/dev/nvidiaN`, UVM;
- ABI `NV_ESC_CARD_INFO`, `NV_ESC_RM_CONTROL`, `NV_ESC_RM_ALLOC`, частина UVM ioctl;
- RM-ланцюжок client → device → subdevice → `NV2080_CTRL_CMD_MC_GET_ARCH_INFO`;
- GPU launch спостерігався без ioctl під час самого виклику: команда записувалася в попередньо відображений pushbuffer, а submission використовував mapped MMIO doorbell;
- BOOT0 лишається `UNPROVEN`; відмова доступу до BAR0 не доводить значення регістра.

Поточні першочергові прогалини:
1. Повний RM object lifecycle: ownership, порядок `ALLOC/FREE`, cleanup після часткової помилки.
2. UVM/GPU VA: реєстрація GPU VA space, життєвий цикл зовнішнього allocation, межі відповідальності RM та UVM.
3. Context/channel initialization.
4. Pushbuffer layout, method stream, fences/sync objects, doorbell — тільки після повного опису потрібних передумов.
5. Переривання, reset/recovery та багатопотокові сценарії.

### B. Дослідження та внески в upstream Nouveau/Mesa

Не створювати паралельний повний Nouveau fork. Спочатку:
1. Зіставити GP107/GP10x код у Linux `drivers/gpu/drm/nouveau` з відповідними NVKM підсистемами.
2. Зіставити Mesa Nouveau Gallium і NVK/NAK із функціями GP107.
3. Відокремити регресії GP107 від архітектурних обмежень firmware.
4. Сформувати мінімальні відтворювані звіти/тести для upstream issue.
5. Підготувати невеликі виправлення або документаційні внески до upstream лише після локального підтвердження.

Основний код:
- [Linux Nouveau source](https://github.com/torvalds/linux/tree/master/drivers/gpu/drm/nouveau)
- [Mesa source](https://gitlab.freedesktop.org/mesa/mesa)
- [Nouveau upstream project](https://nouveau.freedesktop.org/)

## 8. Наступні етапи для нашої плати

| Етап | Завдання | Умова завершення |
|---|---|---|
| 0 | Зафіксувати точну плату, PCI subsystem IDs, VBIOS hash, VRAM, firmware та поточний драйвер | Ідентифікаційний паспорт без припущень |
| 1 | Побудувати карту підтримки GP107 у kernel Nouveau і Mesa/NVK | Посилання на конкретні файли/коміти/тести |
| 2 | Підготувати окремий Linux boot/test профіль з Nouveau | Є шлях повернення на поточний драйвер; основна система не ризикує |
| 3 | Перевірити modesetting, Nouveau Gallium OpenGL, NVK Vulkan 1.3, Rusticl/OpenCL opt-in, suspend/resume, multi-monitor та стабільність | Відтворюваний набір логів і результатів; OpenCL окремо від Vulkan |
| 4 | Виміряти фактичні частоти, temperature, power state та продуктивність | Відокремити boot-clock limitation від функціональних дефектів |
| 5 | Дослідити VBIOS/ISA/register docs через envytools | Лише read-only докази, посилання на джерела |
| 6 | Порівняти vendor R580 та Nouveau на тих самих сценаріях | Матриця відмінностей із доказами |
| 7 | Сформувати upstream-звіти або невеликі патчі | Мінімальний reproducer, перевірка на GP107, review |

## 9. Безпека та межі

- Не прошивати VBIOS і не змінювати firmware.
- Не виконувати MMIO/BAR0 записи в межах початкового дослідження.
- Не запускати експерименти з прямими записами через `nva`.
- Не запускати Nouveau та NVIDIA proprietary driver одночасно на тому самому GPU.
- WSL2 придатний для статичного аналізу й обробки артефактів, але не замінює фізичне тестування kernel DRM driver на реальному PCI GPU.
- Не вважати `OPEN_DENIED`, `MMAP_DENIED` чи `BOOT0=UNPROVEN` доказом конкретної причини.
- Не переносити протокольні спостереження до ABI `wsm-os-lisp` без окремого рішення власника.

## 10. Першоджерела та контрольні посилання

1. [Nouveau project/status](https://nouveau.freedesktop.org/)
2. [Nouveau code names — NV130/Pascal](https://nouveau.freedesktop.org/CodeNames.html)
3. [Mesa NVK documentation](https://docs.mesa3d.org/drivers/nvk.html)
4. [Collabora Pascal enablement announcement, 2025-04-22](https://www.collabora.com/news-and-blog/news-and-events/nvk-enabled-for-maxwell,-pascal,-and-volta-gpus.html)
5. [Linux Nouveau documentation](https://github.com/torvalds/linux/blob/master/Documentation/gpu/nouveau.rst)
6. [Linux Nouveau source tree](https://github.com/torvalds/linux/tree/master/drivers/gpu/drm/nouveau)
7. [NVIDIA open GPU kernel modules](https://github.com/NVIDIA/open-gpu-kernel-modules)
8. [NVIDIA kernel module flavors guide](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/kernel-modules.html)
9. [NVIDIA legacy Linux support timeframes](https://nvidia.custhelp.com/app/answers/detail/a_id/3142/kw/experience)
10. [Linux Nova driver documentation](https://docs.kernel.org/gpu/nova/index.html)
11. [envytools](https://github.com/envytools/envytools)
12. [envytools hardware documentation](https://envytools.readthedocs.io/)
13. [GP107 PCI IDs](https://github.com/envytools/envytools/blob/master/docs/hw/pciid.rst)

Перевірено 2026-11-27. Посилання на рухомі гілки `master` потрібно фіксувати на конкретний commit під час кожного технічного висновку.


## 11. Пряме зіставлення з upstream Linux: GP107 — це окрема реалізація

Під час огляду зафіксовано upstream Linux commit
[`9437ee8b6cf607e883b36e44bd755968daaebd48`](https://github.com/torvalds/linux/commit/9437ee8b6cf607e883b36e44bd755968daaebd48).
Це pin для відтворення посилань нижче; перед кожним майбутнім технічним висновком перевіряти актуальну гілку.

### Ідентифікація архітектури

У `drivers/gpu/drm/nouveau/nvkm/engine/device/base.c` chipset `0x137`
прив'язаний до `nv137_chipset` з назвою `GP107`. Цей профіль підключає
спеціалізований `gp107_gr_new`, спільні GP100/GP102 підсистеми пам'яті,
MMU, FIFO, дисплея, PMU та SEC2, а також NVDEC/NVENC.

Це важливе уточнення: PCI ID `10de:1c82` — точна ідентичність плати,
а внутрішній NVKM chipset ID `0x137` — ідентифікатор сімейства, який
Nouveau визначає на ранній стадії ініціалізації. Не плутати його з
PCI Device ID `0x1c82` чи RM `gpu_id`.

Джерело:
- [Nouveau device chipset map — nv137_chipset (GP107)](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/device/base.c)

### Окремий GP107 graphics engine і context

У ядрі є два окремі файли:
- [`gp107.c`](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/gr/gp107.c) — GP107 GR function table;
- [`ctxgp107.c`](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/gr/ctxgp107.c) — параметри генерації graphics context.

У `gp107.c` зафіксовано:
- 2 GPC, 3 TPC, 1 PPC у конфігурації функцій GR, яку описує цей код;
- класи Pascal 2D/compute;
- контекст `gp107_grctx`;
- завантаження FECS і GPCCS через спільний GM200/ACR firmware path.

Це цінний індекс для читання коду, але не слід трактувати ці числа як
повний паспорт конкретної плати без звірки з fuse/strap/runtime даними.

### Firmware boundary — критична частина відкритого драйвера

GP107 GR явно оголошує такі firmware blobs:
- `nvidia/gp107/gr/fecs_bl.bin`, `fecs_inst.bin`, `fecs_data.bin`, `fecs_sig.bin`;
- `nvidia/gp107/gr/gpccs_bl.bin`, `gpccs_inst.bin`, `gpccs_data.bin`, `gpccs_sig.bin`;
- `nvidia/gp107/gr/sw_ctx.bin`, `sw_nonctx.bin`, `sw_bundle_init.bin`, `sw_method_init.bin`.

Інші спільні NVKM файли оголошують GP107 firmware для SEC2/ACR та NVDEC
scrubber. Тобто відкритий kernel driver не означає, що весь GPU firmware
стек відкритий або генерується з відкритого вихідного коду. Частина
ініціалізації спирається на окремі firmware artifacts.

Джерела:
- [GP107 GR firmware declarations](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/gr/gp107.c)
- [GP102 shared SEC2 implementation (includes GP107 firmware names)](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/sec2/gp102.c)
- [GP102 shared ACR implementation (includes GP107 firmware names)](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/subdev/acr/gp102.c)
- [GP102 shared framebuffer implementation (GP107 NVDEC scrubber)](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/subdev/fb/gp102.c)

### Відомий upstream workaround для деяких GP107/GP108 плат

Найважливіше конкретне спостереження: у
[`gf100_gr_init_()`](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/gr/gf100.c)
є коментар про окрему проблему на деяких платах GP107/GP108:

- після команди SEC2 RTOS запускати GR falcons графічний рушій інколи
  перестає відповідати на PRI-доступ;
- проблема трапляється частіше під час холодного старту/повернення з D3;
- автори прямо зазначають, що першопричина не встановлена;
- workaround — утримувати GR у reset протягом 50 мс перед ініціалізацією;
- код також дозволяє конфігураційне перевизначення через `NvGrResetWar`.

Це не інструкція вручну записувати регістри. Це опис вже наявного
upstream kernel workaround. Наше дослідження має перевірити, чи проявляється
ця проблема на конкретній GTX 1050 Ti, а не змінювати reset-послідовність.

**Пріоритет фізичного тесту:** окремо порівняти cold boot, warm reboot і
resume з D3; зібрати повний `dmesg` Nouveau та зафіксувати, чи ініціалізація
GR/SEC2 проходить без зависань. Кожен сценарій повторити кілька разів,
зберігаючи точну версію kernel, firmware і VBIOS hash.

### Окрема DRM atomic-modesetting регресія для GP107 (вже виправлена в mainline)

Не плутати наведений вище GR/PRI firmware quirk із іншою, програмною
регресією DRM/KMS, яка теж була зафіксована на GP107:

- Commit [`2652aca460dcfdd0d169bbfa358aa15804dc736b`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=2652aca460dcfdd0d169bbfa358aa15804dc736b)
  увімкнув atomic modesetting за замовчуванням для NV50+ Nouveau.
- 2 листопада 2026 власник GP107 у гібридному ноутбуці Intel+NVIDIA повідомив
  про NULL pointer dereference під час ініціалізації: `drm_atomic_commit`
  викликався з fbdev client setup, після повідомлень `No compatible format
  found` / `Cannot find any crtc or sizes`. У тому звіті тимчасовим
  обходом було завантаження з `nouveau.atomic=0`.
- Автор звіту 25 листопада підтвердив, що проблему виправлено в mainline
  комітом [`ed7fb901fce31588bd12ab95adc36ebcb51bc8ea`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=ed7fb901fce31588bd12ab95adc36ebcb51bc8ea).
  Виправлення надає окрему `drm_mode_config_funcs` структуру з
  `atomic_commit = drm_atomic_helper_commit` та
  `atomic_check = drm_atomic_helper_check`, і вибирає її, коли
  `drm_drv_uses_atomic_modeset(dev)` повертає true.
- Fix має `Cc: stable@vger.kernel.org`; це запит на stable backport, а не
  доказ, що кожен дистрибутив уже містить його. У pinned Linux upstream
  snapshot [`9437ee8b6cf607e883b36e44bd755968daaebd48`](https://github.com/torvalds/linux/commit/9437ee8b6cf607e883b36e44bd755968daaebd48)
  виправлення вже є.

Це **DRM atomic/KMS software regression**, а не підтверджений дефект самого
GP107 або той самий GR/PRI reset issue вище. У фізичному тест-плані слід
зафіксувати kernel commit/version і перевірити normal atomic modesetting
на ядрі з `ed7fb901fce31588bd12ab95adc36ebcb51bc8ea` або його stable
backport. `nouveau.atomic=0` залишити лише як діагностичний workaround
для відтворення старого регресійного стану, а не як постійне acceptance
налаштування.

**Stable-backport перевірка станом на 2026-11-27:** у репозиторії
[`gregkh/linux`](https://github.com/gregkh/linux) виправлення вже є у
`master` (файл `drivers/gpu/drm/nouveau/nouveau_display.c` містить
`nouveau_mode_config_funcs_atomic` і вибір через
`drm_drv_uses_atomic_modeset(dev)`). Але перевірені upstream stable-гілки
`linux-7.3.y` та `linux-7.2.y` на цей момент ще не містили цих callbacks
(обидві повертали старий вміст файла, blob
`d71dcfc6ee66b3349cd87404aa15ea9823417d36`). Отже, `Cc: stable@vger.kernel.org`
у fix-коміті — це запит на backport, не доказ його включення у stable branch
чи дистрибутив.

Для нашого зафіксованого профілю Kali/kernel `7.2.15+kali-amd64` не робити
висновок лише з номера версії. Потрібно перевірити вихідний пакет/commit або
наявність atomic callbacks у зібраному Nouveau. Якщо backport відсутній і
регресія відтворюється, `nouveau.atomic=0` — діагностичний тимчасовий обхід;
основним acceptance лишається робота з atomic modesetting на виправленому
ядрі.

Джерела:
- [GP107 regression report and follow-up (2026-11-02 — 2026-11-25)](https://kernelthread.org/t/OS7PR01MB1391484D564CF93DFBB4C1DCE966A2@OS7PR01MB13914.jpnprd01.prod.outlook.kr)
- [Introduced: atomic modesetting by default for NV50+](https://github.com/torvalds/linux/commit/2652aca460dcfdd0d169bbfa358aa15804dc736b)
- [Fix: add atomic DRM mode-config callbacks](https://github.com/torvalds/linux/commit/ed7fb901fce31588bd12ab95adc36ebcb51bc8ea)

### Feature matrix: що ще не готове або залежить від покоління

Офіційна [Nouveau Feature Matrix](https://nouveau.freedesktop.org/FeatureMatrix.html)
пояснює, що її статуси — великі зрізи функціональності, оновлюються рідко,
а `EXTFW` означає залежність від firmware з бінарного драйвера. Сторінка
має дату останньої редакції 2026-10-19. У колонці NV130 вона позначає:
- accelerated video decoding (VDPAU/XvMC): `TODO`;
- power management: `TODO`;
- compute: `WIP`;
- базовий 2D, 3D і KMS — `DONE`.

NV130 — сімейство, а не конкретна гарантія кожної функції для кожної
GP107-плати. Крім того, загальна позначка `compute` у Feature Matrix
не є тестом Vulkan compute у NVK. Тому ми не використовуємо її як
суперечність NVK Vulkan status; фіксуємо як окремі незакриті напрями,
які вимагають точнішої перевірки.

Джерело: [Nouveau Feature Matrix — NV130 column](https://nouveau.freedesktop.org/FeatureMatrix.html).

## 12. Конкретні питання до наступного спринту

1. Які exact firmware-файли для `nvidia/gp107/{gr,sec2,acr,nvdec}` постачаються
   з linux-firmware у поточній версії дистрибутива, і які мають відповідні
   підписи/версії?
2. Чи відповідає наша конкретна плата профілю `nv137_chipset` без додаткових
   board-specific відмінностей?
3. Чи відтворюється GR/PRI hang на cold boot або resume з D3?
4. Чи повідомляє NVK для GP107 очікуваний `apiVersion = 1.3`, чи проходить відповідний Vulkan 1.3 CTS subset; чи немає помилкового очікування Vulkan 1.4 (Turing+)?
5. Що саме обмежує частоти GP107 у Nouveau: лише підписаний firmware,
   чи також неповна реалізація clock/voltage/thermal paths?
6. Які GP107 проблеми мають мінімальний reproducer і можуть стати
   корисним upstream звітом або виправленням?


### Фактична наявність firmware у linux-firmware

Перевірено не лише `MODULE_FIRMWARE()` у Nouveau, а й package manifest:
- У WHENCE з linux-firmware tag `20250917` GP107 GR blobs перелічені як окремі файли; частина GP107 ACR/SEC2/NVDEC компонентів є посиланнями на спільні GP102 blobs.
- У file list пакета Arch `linux-firmware-nvidia 20261019-1` фактично присутні compressed GP107 шляхи для ACR, GR, NVDEC і SEC2.

Це доводить наявність відповідних firmware artifacts у цих дистрибутивних наборах, але **не** доводить, що ті самі файли/версії встановлені у нашій Kali/Ubuntu системі. Під час фізичного тесту зафіксувати package version, реальні файли, symlink targets, SHA-256 та firmware load messages.

Джерела:
- [linux-firmware WHENCE — GP107 firmware declarations and shared GP102 links](https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware/+/refs/tags/20250917/WHENCE)
- [Arch linux-firmware-nvidia 20261019-1 file list — GP107 ACR/GR/NVDEC/SEC2](https://archlinux.org/packages/core/any/linux-firmware-nvidia/files/)

### Діагностичний маркер відомого GR hang

У первинному upstream patch 2020 року наведено конкретний перший симптом у `dmesg`:

```text
nouveau 0000:01:00.0: bus: MMIO read of 00000000 FAULT at 409800 [ TIMEOUT ]
```

Patch повідомляє, що певні GP107/GP108 плати випадково зависали під час GR initialization; першопричину не вдалося ізолювати, а workaround був доданий за замовчуванням для chipset IDs `0x137` та `0x138`. Якщо цей рядок з'явиться на нашій платі, зберегти повний boot log від початку probe; не робити висновок, що кожен MMIO timeout має саме цю причину.

Джерело: [upstream stable patch 028a12f5 — GP107/GP108 GR init workaround](https://lists.openwall.net/linux-kernel/2020/04/22/769).


### Ідентифікація MSI board variant

Owner-observed Windows identity: `10DE:1C82 / SUBSYS_33511462 / REV_A1`.
Decoded subsystem: `1462:3351` (Micro-Star International / MSI). Публічні записи та незалежні апаратні звіти асоціюють цю комбінацію з `MSI GeForce GTX 1050 Ti Gaming X 4G`. Офіційний MSI datasheet для цього SKU вказує:
- GPU: GP107-400;
- 4 GB GDDR5, 128-bit;
- 6-pin PCIe power connector;
- 75 W power specification;
- два вентилятора і профілі OC/Gaming/Silent.

Це покращує нашу target selection порівняно із загальним GP107, але SKU лишається **імовірним до звірки фізичної наклейки або VBIOS**. Не використовувати частоти з datasheet як виміряні частоти нашої карти.

Джерела:
- [MSI official GeForce GTX 1050 Ti GAMING X 4G datasheet](https://storage-asset.msi.com/datasheet/original/vga/global/GeForce-GTX-1050-Ti-GAMING-X-4G.pdf)
- [Public PCI database for 10DE:1C82 / subsystem identifiers](https://manuals.plus/devices/pci/10de/device/1c82)
- [Independent 1462:3351 device report identifying MSI GTX 1050 Ti Gaming X](https://www.gpumagick.com/scores/3450280)


### Обмеження Envytools для Pascal SASS — важлива поправка

Не слід автоматично вважати `envydis` повноцінним дизасемблером SASS для GP107.
У поточному upstream Envytools `envydis/CMakeLists.txt` перелічує ISA backends
`g80.c`, `gf100.c`, `gk110.c`, `gm107.c`; окремого `gp100.c/gp107.c`
backend у цьому списку немає. У `ssot/gpu.py` GP107 є в Pascal GPU inventory,
а в документації GPU-матриці частина GP100/Pascal властивостей залишається
невідомою. Отже:
- Envytools лишається корисним для VBIOS, RNND register/method maps і окремих
  апаратних структур, де Pascal variant явно позначений;
- не покладатися на `envydis` для повного декодування Pascal `sm_61` SASS;
- кожне RNND поле перевіряти наявністю Pascal variant, а не переносити
  визначення з Maxwell/Kepler автоматично.

Джерела:
- [Envytools envydis build list — no GP100/GP107 backend](https://github.com/envytools/envytools/blob/f102b82381f3f11cee113d16374c87091db039d9/envydis/CMakeLists.txt)
- [Envytools Pascal/GP107 GPU inventory](https://github.com/envytools/envytools/blob/f102b82381f3f11cee113d16374c87091db039d9/ssot/gpu.py)
- [Envytools RNND database](https://github.com/envytools/envytools/tree/master/rnndb)

### Дизасемблювання sm_61 SASS: CUDA Binary Utilities

Для SASS саме GP107 практичний контрольний інструмент — NVIDIA `nvdisasm`,
а для пошуку/витягання CUDA cubin із host binaries — `cuobjdump`.
CUDA Binary Utilities 12.6 документують `SM61` як допустиму архітектуру для
`nvdisasm --binary`; це збігається з Pascal compute capability 6.1.

Приклад для сирого instruction image:
```sh
nvdisasm --binary SM61 --print-raw <sm61-instructions.bin>
```

Для cubin:
```sh
nvdisasm <kernel.cubin>
```

Для fatbin/host executable:
```sh
cuobjdump --list-elf <program-or-library>
cuobjdump --dump-sass <program-or-library>
```

Ці інструменти — **закриті утиліти NVIDIA**, а не відкритий компонент стека.
Використовувати їх як контрольний декодер для аналізу коду `sm_61`, де
доступний cubin/SASS. Вони не декомпілюють host-side x86-64 ELF драйвер
(`libcuda.so` або `nvidia.ko`): для цього залишаються Ghidra/REA та
аналіз ELF/ABI.

Джерела:
- [CUDA 12.6 Binary Utilities — nvdisasm supports SM61](https://docs.nvidia.com/cuda/archive/12.6.3/pdf/CUDA_Binary_Utilities.pdf)
- [CUDA Binary Utilities — cuobjdump and nvdisasm roles](https://docs.nvidia.com/cuda/archive/12.6.2/cuda-binary-utilities/index.html)
- [CUDA 12.6 component versions/platform availability](https://docs.nvidia.com/cuda/archive/12.6.0/cuda-toolkit-release-notes/index.html)


## 13. Детальна матриця NV130: робоча графіка проти відсутніх функцій

Цей розділ фіксує **upstream status** сімейства NV130 за офіційними Nouveau
FeatureMatrix, PowerManagement і VideoAcceleration. Це не board-specific
runtime результат для нашої MSI/GTX 1050 Ti; самі таблиці називають свої
статуси великими/приблизними зрізами й можуть містити помилки.

### Графічний і дисплейний шлях

У FeatureMatrix для NV130 позначено DONE:
- базова 2D та швидка 2D acceleration через modesetting DDX;
- 3D primitives і textures;
- vertex, fragment, geometry та tessellation programs;
- Dual-head/RandR 1.2 і Kernel Mode Setting;
- DisplayPort SST (single-stream);
- HDMI display.

Є важливі застереження:
- примітка до shader-program рядків каже, що ці функції можуть бути повільними через незавершене power management;
- DisplayPort SST Audio для NV130 позначено TODO;
- HDMI Audio у загальній таблиці має DONE, але примітка №10 уточнює, що HDMI audio працює лише для NVA3/A5/A8 (GT21x). Отже **HDMI audio для GP107 не підтверджено**;
- наявність Xv playback (overlay) не є доказом апаратного video decoding.

### Power management — повний перелік прогалин

У PowerManagement matrix колонка NV130 позначає TODO для:
- performance levels;
- voltage;
- thermal settings;
- memory timings;
- memory clock/timing mapping;
- engine reclocking;
- memory reclocking;
- automatic reclocking;
- voltage adjusting;
- thermal sensors;
- fan-speed control.

Сторінка прямо попереджає, що це приблизна матриця; використовувати її як
upstream status, а не як фізичне вимірювання конкретної плати. Collabora
додатково описувала, що більшість Maxwell/Pascal/Volta GPU залишаються на
boot clocks через firmware limitations. Тому швидкодію GP107 треба тестувати
разом із фактичними частотами й power state, якщо апаратна карта доступна.

### Відеодекодування: NVDEC у коді ≠ відкритий декодер для користувача

У FeatureMatrix accelerated video decoding (VDPAU/XvMC) для NV130 = TODO.
У VideoAcceleration список GP107/NV130 decode engine не містить: перелік
підтримуваних VP engines завершується NV126 (GeForce 900 series), а рядок
VP6+ має TODO для codec API. Тож наразі немає підтвердженого Nouveau
VDPAU/VA-API decode path для GP107.

Водночас у Linux NVKM chipset profile GP107 дійсно підключений до
`gm107_nvdec_new`, а в kernel source згадується GP107 NVDEC scrubber
firmware. Це доводить, що ядро має компонент для роботи з відповідною
апаратною підсистемою/firmware boundary, але **не доводить** наявність
працюючого userspace codec decoder, підтримки конкретних форматів або
готового VDPAU/VA-API API. Це слід тримати як окрему capability gap.

Документація Nouveau також зазначає, що старіші VP1–VP5 engines залежать
від firmware, яке наразі витягається з пропрієтарного драйвера; це загальна
проблема Nouveau firmware policy і не має бути автоматично перенесено на
GP107 VP6+ без конкретного підтвердження.

### Rusticl/OpenCL — окремий open-compute кандидат

Mesa Rusticl — реалізація OpenCL поверх Gallium; це **не CUDA** і не NVK.
Поточна Mesa environment-variable документація включає `nouveau` у список
Rusticl drivers із decent support, але попереджає про можливі conformance
issues/bugs. Rusticl потребує явного ввімкнення: `RUSTICL_ENABLE=nouveau`.
За документацією Rusticl, пристрої за замовчуванням не експонуються через
стабільнісні обмеження.

Отже, перспективний відкритий compute шлях для GP107:
`Nouveau Gallium → Mesa Rusticl → OpenCL`.
Це upstream-доступність драйвера, але не доказ, що Rusticl уже працює
на конкретній GTX 1050 Ti, і не обіцянка CUDA-сумісності чи продуктивності.

**Мінімальний фізичний тест, коли GP107 буде доступний у Linux:**

1. Переконатися, що Nouveau реально прив'язаний до `10de:1c82` і немає
   одночасно завантаженого proprietary NVIDIA kernel driver для цієї карти.
2. Зберегти точні версії kernel, Mesa, LLVM, linux-firmware, PCI BDF і
   firmware load messages.
3. Запустити `RUSTICL_ENABLE=nouveau clinfo`; перевірити platform/device,
   vendor, device name, OpenCL version та чи не був вибраний CPU/llvmpipe.
4. Запустити малий OpenCL vector-add із перевіркою результату проти CPU.
5. Після smoke test — відповідний subset OpenCL CTS; зберегти повний log
   і failing test names, не лише aggregate pass/fail.
6. Зберігати OpenCL результати окремо від NVK/Vulkan tests і vendor CUDA.

У capability matrix репозиторію стан наразі такий:

| Можливість | Upstream status | На нашій GTX 1050 Ti |
|---|---|---|
| Nouveau KMS / базова графіка | NV130 DONE | board runtime UNPROVEN |
| Mesa Nouveau Gallium OpenGL | NV130 shader/3D features DONE | board runtime UNPROVEN |
| Mesa NVK Vulkan | Pascal; Vulkan API 1.3 за перевіреним per-device source snapshot | board runtime UNPROVEN |
| OpenCL через Rusticl/Nouveau | nouveau у Rusticl supported-driver list | board runtime UNPROVEN |
| VDPAU/VA-API video decode | NV130 TODO; GP107 не listed у engine table | не підтверджено |
| Engine/memory reclocking та automatic PM | NV130 TODO | не підтверджено; firmware limitation |
| DP SST display | NV130 DONE | board/display runtime UNPROVEN |
| DP SST audio | NV130 TODO | не підтверджено |
| HDMI display | NV130 DONE | board/display runtime UNPROVEN |
| HDMI audio | загальна примітка обмежує DONE до старших NVA3/A5/A8 | для GP107 не підтверджено |

### Історичний і поточний статус NVK — не змішувати

- **22 квітня 2025:** Collabora оголосила Pascal enablement і Vulkan 1.3 conformance;
  Mesa 25.1 мала ввімкнути NVK на цих GPU за замовчуванням.
- **Поточна Mesa documentation:** NVK описується як підтримка Kepler і новіших
  GPU та Vulkan 1.4 conformant для всіх офіційно підтримуваних GPU.

Це свідчить про розвиток NVK після первинного Pascal enablement, але жоден
із цих загальних upstream statements не замінює тест на нашій конкретній
GTX 1050 Ti та її subsystem/VBIOS варіанті.

Джерела:
- [Nouveau Feature Matrix — NV130 column](https://nouveau.freedesktop.org/FeatureMatrix.html)
- [Nouveau PowerManagement — NV130 column](https://nouveau.freedesktop.org/PowerManagement.html)
- [Nouveau VideoAcceleration — engine mapping and VP6+ status](https://nouveau.freedesktop.org/VideoAcceleration.html)
- [Mesa Rusticl documentation](https://docs.mesa3d.org/rusticl.html)
- [Mesa Rusticl environment variables — supported drivers and RUSTICL_ENABLE](https://docs.mesa3d.org/envvars.html#rusticl-environment-variables)
- [Mesa NVK — current hardware and conformance status](https://docs.mesa3d.org/drivers/nvk.html)
- [Collabora — historical Pascal Vulkan 1.3 milestone, 2025-04-22](https://www.collabora.com/news-and-blog/news-and-events/nvk-enabled-for-maxwell,-pascal,-and-volta-gpus.html)
- [Linux GP107 chipset profile](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/device/base.c)


### NVK: загальна конформність не дорівнює Vulkan 1.4 на GP107

Є важлива відмінність між поточною загальною Mesa NVK documentation і
per-device version selection у коді Mesa. У source snapshot
[`b602686e3008239284315b67f7aea226bb8d2af2`](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/b602686e3008239284315b67f7aea226bb8d2af2/src/nouveau/vulkan/nvk_physical_device.c):

- `nvk_get_vk_version()` повертає Vulkan 1.3, коли
  `info->cls_eng3d < TURING_A`; Pascal GP107 належить до цієї категорії.
- Коментар у коді пояснює межу: Vulkan 1.4 потребує `hostImageCopy`, а ця
  функція в цьому snapshot реалізована лише для Turing+.
- `nvk_is_conformant()` окремо включає всі discrete GPU від Kepler до Ada
  (а також consumer Blackwell B). Тобто conformant NVK на Pascal не означає,
  що його API version обов'язково 1.4.

Отже, **очікуваний API version для GP107 за цим source snapshot — Vulkan 1.3**,
а conformance має перевірятися окремо за пристроєм/драйвером. Фактичне значення
на нашій GTX 1050 Ti ще треба підтвердити через `vulkaninfo` після фізичного
bring-up. Не переносити загальне заголовне формулювання Mesa Vulkan 1.4
на кожну архітектуру автоматично.

Джерело:
- [Mesa pinned source — per-device NVK API version and conformance predicates](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/b602686e3008239284315b67f7aea226bb8d2af2/src/nouveau/vulkan/nvk_physical_device.c)


## 14. Свіжі межі compute, відео та актуальних інструментів (2026-11-27)

Цей розділ відділяє архітектурну підтримку Pascal від загальних заяв Mesa/NVIDIA та від реального runtime на конкретній GTX 1050 Ti.

### 14.1. NVK Vulkan Video з Mesa 26.3 не поширюється на GP107

У Mesa 26.3 з'явився початковий NVK Vulkan Video шлях із H.264 decode. Він залежить від NVIDIA GSP; H.265 у згаданому зрізі ще спричиняв зависання GSP. Через цю залежність Vulkan Video NVK підтримується лише на Turing і новіших GPU. GP107/Pascal не має GSP, тому нова функція Mesa 26.3 **не є** відеодекодером для GTX 1050 Ti.

Не змішувати:
1. наявність NVDEC/NVDEC-related компонентів у кремнії або NVKM chipset table;
2. наявність firmware/SEC2/NVDEC компонентів у Linux;
3. готовий userspace API (Vulkan Video, VDPAU, VA-API) для конкретного покоління.

Для NV130 таблиця Nouveau досі позначає старий VDPAU/XvMC decode як TODO; наявність NVDEC реєстрації в ядрі сама по собі не доводить роботу userspace decoder.

Джерела:
- [NVK Vulkan Video merged for Mesa 26.3 — GSP dependency and Turing+ limitation (2026-08-22)](https://www.phoronix.com/news/NVK-Vulkan-Video-Mesa-26.3)
- [Mesa 26.3 release notes](https://docs.mesa3d.org/relnotes/26.3.0.html)
- [Nouveau Feature Matrix](https://nouveau.freedesktop.org/FeatureMatrix.html)
- [Nouveau VideoAcceleration matrix](https://nouveau.freedesktop.org/VideoAcceleration.html)

### 14.2. CUDA для SM 6.1: остання лінія збірки — Toolkit 12.x

NVIDIA позначає Maxwell, Pascal і Volta як feature-complete для CUDA; починаючи з CUDA Toolkit 13.0 прибрано offline compilation і library support для цих архітектур. Toolkit 12.x залишається підтримуваною лінією для створення застосунків під ці GPU. Для GP107/SM61 це означає:

- для нової компіляції CUDA-коду під SM61 використовувати CUDA Toolkit 12.x;
- CUDA Toolkit 13.x/13.5 не використовувати як компілятор цілі SM61;
- не робити висновок, що наявна CUDA-програма автоматично перестане запускатися: тут ідеться саме про вилучення offline compilation/library support для старих архітектур;
- vendor CUDA лишається закритим fallback/контрольним шляхом, не відкритим драйвером.

Це не змінює вибір Nouveau/NVK для відкритої графіки. Порівнювати CUDA та Vulkan/OpenCL workload слід окремо й не оголошувати сумісність API між ними.

Джерела:
- [NVIDIA CUDA Features Archive — deprecated Maxwell/Pascal/Volta architectures](https://docs.nvidia.com/cuda/cuda-features-archive/index.html)
- [CUDA Toolkit 13.2.2 release notes](https://docs.nvidia.com/cuda/archive/13.2.2/cuda-toolkit-release-notes/index.html)
- [CUDA Toolkit Archive — current release 13.5.0, November 2026](https://developer.nvidia.com/cuda-toolkit-archive/)

### 14.3. Поточні Mesa bug-fix релізи і як читати їхні Nouveau fixes

Станом на 2026-11-27:
- Mesa 26.2.8 — bug-fix release від 25 листопада 2026;
- Mesa 26.3.1 — bug-fix release від 18 листопада 2026;
- Mesa 26.3.0 — новий feature/development release від 9 листопада; його release notes радять орієнтованим на стабільність користувачам залишатися на попередньому релізі або перейти на 26.3.1.

У Mesa 26.2.8 є Nouveau виправлення для VP3 H.264 decoder (передача `chroma_format_idc` та MBAFF-прапорця), а також інші `nv50/nvc0/winsys` зміни. Це важливі upstream fixes, але **не слід трактувати їх як підтвердження H.264 decode на GP107**: decoder family/engine coverage у Nouveau FeatureMatrix для NV130 залишається окремою прогалиною.

Для перших фізичних тестів варто брати наявний distro bug-fix Mesa package і записувати точну версію; для контрольного порівняння — 26.2.8 або 26.3.1. Не оновлювати Mesa на робочій системі лише заради версії, доки не визначений recovery path.

Джерела:
- [Mesa 26.2.8 release notes (2026-11-25)](https://docs.mesa3d.org/relnotes/26.2.8.html)
- [Mesa 26.3.1 release notes (2026-11-18)](https://docs.mesa3d.org/relnotes/26.3.1.html)
- [Mesa 26.3.0 release notes (2026-11-09)](https://docs.mesa3d.org/relnotes/26.3.0.html)
- [Mesa release news](https://mesa3d.org/news/)

### 14.4. Vulkan compute та llama.cpp — лише після базового NVK bring-up

Успішний `vulkaninfo` доводить лише наявність Vulkan physical device/API properties; він не доводить виконання реального compute workload. Порядок перевірки:
1. Vulkan enumeration / device properties;
2. малий Vulkan compute smoke test із перевіркою результату;
3. тестування кількох черг/синхронізації й пам'яті;
4. лише потім application-level workload, наприклад [llama.cpp Vulkan backend](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md).

llama.cpp документує CMake-параметр `-DGGML_VULKAN=ON`. Це загальний Vulkan backend і потенційний прикладний тест NVK, але підтримка конкретної GP107/NVK комбінації не доведена. Якщо базовий NVK API оголошує Vulkan 1.3, перевірити фактичні extension/feature requirements llama.cpp; не підміняти версію Vulkan і не обходити відмову драйвера.

Для 4-GB GTX 1050 Ti починати з невеликої quantized GGUF моделі та 1–2 GPU layers; фіксувати явне обрання NVK device, модель/quantization, context, кількість offloaded layers, VRAM, температуру/частоти (якщо доступні) та tokens/s. CPU fallback не вважати GPU результатом.

Джерело: [llama.cpp build guide — Vulkan backend](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md).

### 14.5. Суміжний проєкт TheTom/pascal-egpu — reference, не драйвер для GP107

[TheTom/pascal-egpu](https://github.com/TheTom/pascal-egpu) досліджує driverless userspace access до Pascal **GP106/GTX 1060** через Thunderbolt eGPU на macOS Apple Silicon. Це інше середовище й інший GPU ID; проект не є Nouveau і не доводить runtime на нашому GP107.

Після перевірки `hw/compute_dispatch.py` виявлено важливу межу його тесту:
- у гілці `FECS not running` результат `C=A+B` обчислюється на CPU;
- у гілці `FECS alive` код прямо залишає FIFO + QMD submission як TODO, а результат також обчислює на CPU;
- тому `vector_add_test() = PASS` підтверджує CPU арифметику та readback буфера, **не GPU dispatch**.

У проєкті також присутні MMIO write/reset/devinit helper-и; його `RESEARCH.md` описує hardware lockup після експериментальних writes. Не запускати його write/reset/devinit/Falcon-код на робочій GTX 1050 Ti. Використовувати лише як джерело дослідницьких питань і перехресну документацію.

Публічні NVIDIA class headers визначають:
- `PASCAL_COMPUTE_A = 0xC0C0`;
- `PASCAL_COMPUTE_B = 0xC1C0`;
- `MAXWELL_COMPUTE_B = 0xB1C0`.

Це доводить існування різних class IDs у документації, але **не визначає автоматично**, який compute class та які методи дозволені на конкретному GP107. Потрібен окремий доказ GPU→class mapping з upstream Nouveau або апаратного witness; не переносити GP106 assumption на GP107.

Джерела:
- [TheTom/pascal-egpu README and source](https://github.com/TheTom/pascal-egpu)
- [compute_dispatch.py — CPU fallback and TODO dispatch](https://github.com/TheTom/pascal-egpu/blob/main/hw/compute_dispatch.py)
- [Pascal Compute A header](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/compute/clc0c0.h)
- [Pascal Compute B header](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/compute/clc1c0.h)
- [Maxwell Compute B header](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/compute/clb1c0.h)

### 14.6. GP107 atomic KMS regression: перевіряти stable backport, не лише kernel version

Окремий GP107 report описував NULL dereference під час atomic modesetting після commit `2652aca460dc`. Upstream fix `ed7fb901fce31588bd12ab95adc36ebcb51bc8ea` додає коректні atomic callbacks і входить у mainline з v7.4-rc3; fix позначений для stable. Проте `Cc: stable` не гарантує, що патч уже присутній у конкретній stable-гілці чи дистрибутивному ядрі.

Перед першим фізичним boot:
- перевірити наявність commit/backport у джерелах або пакеті конкретного ядра;
- не радити `nouveau.atomic=0` як загальний параметр;
- використовувати його лише як разовий діагностичний boot, якщо відтворюється саме цей Oops на ядрі без виправлення.

Не плутати atomic KMS regression із давнім GP107/GP108 GR/PRI init workaround під час cold boot/D3: це різні проблеми й різні місця в коді.

Джерела:
- [GP107 atomic regression report (2026-11-02)](https://lists.openwall.net/linux-kernel/2026/11/02/1643)
- [Upstream atomic callback fix, ed7fb901fce3 (2026-11-11)](https://github.com/torvalds/linux/commit/ed7fb901fce31588bd12ab95adc36ebcb51bc8ea)
- [v7.4-rc3 DRM fixes pull](https://lists.openwall.net/linux-kernel/2026/11/14/172)
