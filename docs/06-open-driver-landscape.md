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

Окрім Vulkan/NVK, для compute існує інший відкритий шлях: **Nouveau Gallium → Mesa Rusticl → OpenCL**. Rusticl є реалізацією OpenCL поверх Gallium, а не CUDA runtime або сумісним шаром CUDA. Документація `RUSTICL_ENABLE` перелічує `nouveau` серед драйверів із «decent support», але попереджає про можливі conformance issues/bugs. Пристрої не рекламуються автоматично: потрібен явний opt-in через `RUSTICL_ENABLE`.

Важлива build-time/runtime різниця в pinned Mesa `meson.options` (snapshot
`660c14e2e7d85f1bb5d4b4b86bec77befe802dab`): `nouveau` входить до списку
доступних `gallium-drivers`, але **не** входить до
`gallium-rusticl-enable-drivers`. Остання опція — allowlist драйверів,
для яких Rusticl вмикається **за замовчуванням**; це не тотожне забороні
явного opt-in. Тому для GP107 не очікувати default OpenCL device enumeration,
але перевірити явний `RUSTICL_ENABLE=nouveau` на відповідній збірці Mesa.

Перший безпечний runtime probe на окремому Nouveau boot:
```sh
RUSTICL_ENABLE=nouveau clinfo
```
Зберегти OpenCL platform/device/vendor/version та extensions. Якщо пристрій з'являється, наступний тест — мінімальний vector-add із перевіркою результату, потім відповідний піднабір OpenCL CTS. Не називати шлях робочим на GP107 до проходження цих свідків; не змішувати OpenCL результати з NVK/Vulkan.

Джерела:
- [Mesa Rusticl — OpenCL on top of Gallium and enablement requirement](https://docs.mesa3d.org/rusticl.html)
- [Mesa environment variables — `RUSTICL_ENABLE` and supported drivers](https://docs.mesa3d.org/envvars.html#rusticl-environment-variables)
- [Pinned Mesa `meson.options`: Nouveau Gallium buildable, but absent from Rusticl default-enable allowlist](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/660c14e2e7d85f1bb5d4b4b86bec77befe802dab/meson.options)

## 2.2. Актуальна Mesa baseline та межа Vulkan Video

Для відтворюваних тестів фіксувати не лише «Mesa latest», а конкретний
release і його checksum. Станом на 2026-11-27:

- **Mesa 26.2.8 (2026-11-25)** — bug-fix release. У release notes є Nouveau
  виправлення `pushbuf_dump()`: уникнути segfault після `ENODEV`, коли є один
  push і нуль buffer references. Це корисне виправлення error/diagnostic path,
  але воно не доводить кращу GP107 command submission чи стабільність усіх
  каналів. SHA-256 source archive:
  `58878dbad3a4bf7ec29639f5db8e2905631a52169729282a2f2614adf3cecbcf`.
- **Mesa 26.3.1 (2026-11-18)** — bug-fix release після 26.3.0; у його
  release notes немає явно названого GP107/NVK fix. Це не означає, що інші
  зміни NVK не потрапили до релізу — лише те, що релізні нотатки не дають
  окремого GP107-specific acceptance claim. SHA-256:
  `4e4e438eac7b840a9383988cbb7c08dad8041da544b9319fc26d319fa7348961`.
- **Mesa 26.3.0 (2026-11-04)** на офіційній сторінці News позначено як
  development release; для стабільного bring-up брати bug-fix release
  26.3.1, а не 26.3.0.
- Загальні заголовки Mesa про OpenGL 4.6 / OpenCL 3.1 / Vulkan 1.4 — це
  можливості Mesa API загалом; версія, яку реально повертає пристрій,
  залежить від конкретного драйвера. Для GP107 очікуваний NVK Vulkan API
  лишається **1.3** за per-device source logic вище.

### Vulkan Video: NVK H.264 шлях не для GP107

Початковий NVK Vulkan Video H.264 decoder, злитий для Mesa 26.3, залежить
від NVIDIA GSP; upstream-анонс прямо обмежує його Turing і новішими GPU.
Pascal GP107 не має GSP, тому **не включати NVK Vulkan Video H.264 до
очікуваних можливостей GTX 1050 Ti**. Це не заперечує наявність NVDEC
апаратного блоку або NVKM firmware hook у kernel tree: це різні рівні
підтримки. Для GP107 video decode в Nouveau залишається окремою прогалиною
(VideoAcceleration matrix), доки не з'явиться відповідний VP engine/userspace
шлях зі свідками.

### Vulkan compute: llama.cpp як application-level тест

Після успішних NVK device enumeration, Vulkan graphics smoke test і
перевірки базового compute pipeline можна додати [llama.cpp Vulkan backend](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)
як практичний workload. Проєкт офіційно документує збірку через
`GGML_VULKAN` і просить спочатку перевірити loader через `vulkaninfo`.

Приклад збірки в окремому тестовому worktree:
```sh
cmake -B build-vulkan -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-vulkan --config Release -j"$(nproc)"
./build-vulkan/bin/llama-cli --list-devices
```

Перший workload має бути невеликою квантизованою GGUF-моделлю із невеликою
кількістю GPU layers, а не повним offload одразу. У логах обов'язково
переконатися, що обраний пристрій — саме GP107 через NVK, а не CPU fallback
або інший GPU. Зберігати модель/quantization, context, кількість offloaded
layers, tokens/s, VRAM, частоти/температуру та повний startup log. Якщо
backend вимагає Vulkan extension/feature, якої GP107 не рекламує, зафіксувати
точну помилку й properties; не підміняти API version чи capabilities.

Це application-level перевірка Vulkan compute, не CUDA compatibility,
не OpenCL/Rusticl test і не доказ придатності llama.cpp для щоденної
продуктивної роботи на 4 GB GP107. До фактичного запуску всі ці результати
мають стан **UNPROVEN**.

Джерела:
- [Mesa 26.2.8 release notes (2026-11-25)](https://docs.mesa3d.org/relnotes/26.2.8.html)
- [Mesa 26.3.1 release notes (2026-11-18)](https://docs.mesa3d.org/relnotes/26.3.1.html)
- [Mesa release news: 26.3.0 was a development release](https://mesa3d.org/news/)
- [NVK Vulkan Video H.264/GSP support — Turing+ limitation](https://www.phoronix.com/news/NVK-Vulkan-Video-Mesa-26.3)
- [llama.cpp — official Vulkan build instructions](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)

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

Паралельний документ [`docs/07-next-research-direction.md`](07-next-research-direction.md)
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
[`gregkh/linux`](https://github.com/gregkh/linux) виправлення є у
`master` (файл `drivers/gpu/drm/nouveau/nouveau_display.c` містить
`nouveau_mode_config_funcs_atomic` і вибір через
`drm_drv_uses_atomic_modeset(dev)`). Перевірив також точні point-release
source commits:
- [Linux 7.3.5: `988117cc1bb17338c586a4e21ade88b5397eac33`](https://github.com/gregkh/linux/blob/988117cc1bb17338c586a4e21ade88b5397eac33/drivers/gpu/drm/nouveau/nouveau_display.c)
- [Linux 7.2.15: `497791a0a96b866d90add64041c47acdff49cae6`](https://github.com/gregkh/linux/blob/497791a0a96b866d90add64041c47acdff49cae6/drivers/gpu/drm/nouveau/nouveau_display.c)

Обидва source files повернули однаковий blob
`d71dcfc6ee66b3349cd87404aa15ea9823417d36`, у якому ще немає
`nouveau_mode_config_funcs_atomic`. Отже `Cc: stable@vger.kernel.org`
не означає, що backport уже потрапив у point release або дистрибутив.

Для нашого зафіксованого профілю Kali/kernel `7.2.15+kali-amd64` це
особливо важливо: перевірити source package/patch set самого Kali build,
а не виводити статус лише з номера upstream stable. Якщо backport відсутній
і regression відтворюється, `nouveau.atomic=0` — лише тимчасовий
діагностичний обхід; acceptance має перевіряти normal atomic KMS з fix.

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
| Mesa NVK Vulkan | Pascal supported; per-device Mesa source snapshot exposes Vulkan 1.3 on pre-Turing; conformant flag includes Kepler–Ada | board runtime UNPROVEN |
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

**Незалежне підтвердження через Khronos Conformant Products:** запис
Software Freedom Conservancy №908 від 2025-04-18 декларує
`Vulkan_1_3` і прямо включає GeForce GTX 1050 та GTX 1050 Ti до списку
продуктів. У записі вказано CTS 1.4.1.2, Intel Core i9-10980XE та
Linux 6.14.0 (Fedora 41). Це узгоджується з per-device Mesa source:
для Pascal оголошується API 1.3, а conformance оцінюється окремо.
Не плутати цей запис Software Freedom Conservancy з окремим записом
NVIDIA №805 від 2024-11-13, де Vulkan 1.4 декларувався для Pascal
у пропрієтарному драйвері. Khronos entry — upstream conformance proof
для переліченого продуктового набору, але не runtime proof нашої
конкретної плати, її subsystem/VBIOS чи встановленої версії Mesa.

Джерело:
- [Khronos Vulkan Conformant Products — Software Freedom Conservancy entry #908](https://www.khronos.org/conformance/adopters/conformant-products/vulkan)
Джерело:
- [Mesa pinned source — per-device NVK API version and conformance predicates](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/b602686e3008239284315b67f7aea226bb8d2af2/src/nouveau/vulkan/nvk_physical_device.c)


## 14. CUDA SM61 та незалежний Pascal eGPU reference

### 14.1. CUDA Toolkit 13.x більше не збирає нові binaries для Pascal SM61

NVIDIA позначає Maxwell, Pascal і Volta як feature-complete для CUDA; у CUDA Toolkit 13.0 прибрано offline compilation і library support для цих архітектур. Toolkit 12.x залишається останньою серією для створення застосунків під SM61.

Практичні наслідки для GP107:
- якщо потрібна нова CUDA-компіляція для `sm_61`, залишатися на CUDA Toolkit 12.x;
- не налаштовувати CUDA Toolkit 13.x/13.5 як компілятор для цілі SM61;
- не робити висновок, що всі вже зібрані CUDA binaries перестають запускатися: джерело описує вилучення offline compilation і library support для старих архітектур;
- CUDA залишається vendor/proprietary шляхом, не частиною відкритого Nouveau stack.

Джерела:
- [NVIDIA CUDA Features Archive — Maxwell/Pascal/Volta support](https://docs.nvidia.com/cuda/cuda-features-archive/index.html)
- [CUDA Toolkit 13.2.2 release notes](https://docs.nvidia.com/cuda/archive/13.2.2/cuda-toolkit-release-notes/index.html)
- [CUDA Toolkit Archive — version 13.5.0, November 2026](https://developer.nvidia.com/cuda-toolkit-archive/)

### 14.2. TheTom/pascal-egpu — корисна reference база, але не доказ GP107 compute

[TheTom/pascal-egpu](https://github.com/TheTom/pascal-egpu) досліджує driverless userspace access до Pascal **GP106/GTX 1060** через Thunderbolt eGPU на macOS Apple Silicon. Це інше середовище й інший GPU ID; проєкт не є Nouveau і не доводить runtime на нашому GP107.

Після перевірки `hw/compute_dispatch.py`:
- у гілці `FECS not running` сума `C=A+B` обчислюється на CPU;
- у гілці `FECS alive` FIFO + QMD submission прямо залишені як TODO, а сума знову обчислюється на CPU;
- тому `vector_add_test() = PASS` підтверджує CPU арифметику та буферний readback, а не GPU dispatch.

Проєкт містить виконувані MMIO write/reset/devinit helper-и. Це не read-only probes. Не запускати його write/reset/devinit/Falcon-код на робочій GTX 1050 Ti; використовувати лише документацію та безпечний статичний аналіз.

### 14.3. Точний Pascal compute class для GP107 уже відомий з Nouveau source

Публічні NVIDIA headers визначають:
- `PASCAL_COMPUTE_A = 0xC0C0`;
- `PASCAL_COMPUTE_B = 0xC1C0`;
- `MAXWELL_COMPUTE_B = 0xB1C0`.

Для GP107 це не припущення: перевірений Linux Nouveau `gp107.c` у class table явно вибирає `PASCAL_B` для 3D і `PASCAL_COMPUTE_B` для compute. Отже source-proven target mapping для GP107 — **`PASCAL_COMPUTE_B (0xC1C0)`**, не Maxwell `0xB1C0`.

Це важлива помилка суміжного `TheTom/pascal-egpu/PLAN.md`: у рядках 521/528 він називає `MAXWELL_COMPUTE_B (0xB1C0)` для Pascal, тоді як його ж `RESEARCH.md` правильно вказує для GP106 `PASCAL_COMPUTE_B (0xC1C0)`. Для GP107 клас додатково підтверджений безпосередньо upstream Nouveau source. Не переносити помилковий Maxwell class ID у власні probes.

Цей факт **не доводить GPU execution**. Для реального compute dispatch усе ще потрібні доведені channel/context lifecycle, signed FECS/GPCCS firmware, GPFIFO/QMD submission та синхронізація GPU. Ці етапи лишаються окремими відміченими доказами; CPU vector-add не може їх замінити.

Джерела:
- [Linux GP107 GR class selection — Pascal 3D and Compute B](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/gr/gp107.c)
- [TheTom/pascal-egpu source](https://github.com/TheTom/pascal-egpu)
- [compute_dispatch.py — CPU fallback and TODO dispatch](https://github.com/TheTom/pascal-egpu/blob/main/hw/compute_dispatch.py)
- [TheTom Pascal PLAN.md](https://github.com/TheTom/pascal-egpu/blob/main/PLAN.md)
- [TheTom Pascal RESEARCH.md](https://github.com/TheTom/pascal-egpu/blob/main/RESEARCH.md)
- [Pascal Compute A header](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/compute/clc0c0.h)
- [Pascal Compute B header](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/compute/clc1c0.h)
- [Maxwell Compute B header](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/compute/clb1c0.h)

## 15. NVENC/NVDEC: silicon capability ≠ відкритий Nouveau codec API

### Що підтримує сама GTX 1050 Ti

Офіційна NVIDIA Video Encode/Decode Support Matrix перелічує GeForce GTX
1050 / 1050 Ti як Pascal із **NVENC 6th Gen**, одним NVENC engine, та
**NVDEC 3rd Gen**, одним NVDEC engine. Це апаратна capability-матриця
виробника, не гарантія наявності userspace API у відкритому драйвері.

Для NVDEC сторінка показує два рядки з однаковою маркетинговою назвою
GTX 1050 / 1050 Ti, але з різними значеннями кількох codec columns.
Тому не переносити всі профілі/бітності одного рядка на нашу плату без
точного зіставлення VBIOS/SKU. Owner-observed subsystem `1462:3351`
(Windows `SUBSYS_33511462`) у базі LACT зіставляється з **MSI GTX 1050 Ti
Gaming X**. Це незалежне каталожне підтвердження назви board variant;
у фізичному hardware passport усе одно записати фактичні PCI subsystem IDs
та VBIOS version. NVIDIA matrix не прив'язує два NVDEC-рядки до subsystem ID,
тому конкретний набір decode profiles нашої Gaming X лишається непідтвердженим.
NVENC duplicate rows GTX 1050/1050 Ti, навпаки, мають однакові показані
codec flags; відрізняються саме два NVDEC rows.

### Що насправді реалізовано в Linux Nouveau для GP107

На pinned Linux source snapshot
[`9437ee8b6cf607e883b36e44bd755968daaebd48`](https://github.com/torvalds/linux/commit/9437ee8b6cf607e883b36e44bd755968daaebd48)
GP107 chipset profile реєструє constructors `gm107_nvenc_new` та
`gm107_nvdec_new`. Але самі engine files демонструють межу:

- [`nvenc/gm107.c`](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/nvenc/gm107.c):
  `gm107_nvenc_flcn` порожній; firmware interface містить лише
  `gm107_nvenc_nofw()`, який повертає 0, без firmware loading або
  реалізації encoder command path.
- [`nvdec/gm107.c`](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/nvdec/gm107.c):
  є базові Falcon control callbacks, але firmware interface також
  використовує лише `gm107_nvdec_nofw()`. Це не декодерний firmware
  stack і не доказ codec execution.

Отже реєстрація NVENC/NVDEC object у `nv137_chipset` означає, що kernel
знає про апаратний engine, але **не** доводить роботу відкритого
NVENCODE/NVDECODE API. Nouveau Feature Matrix для NV130 залишає video
decoding TODO; VideoAcceleration не наводить GP107/NV130 у таблиці
користувацьких VP decode engine paths. NVK Vulkan Video H.264 у Mesa 26.3
є окремою GSP-залежною реалізацією для Turing+, тому також не підходить
GP107.

### Пропрієтарний контрольний шлях — окремо від Nouveau

NVIDIA Video Codec SDK 13.1 FFmpeg integration guide формулює
fully-accelerated NVENC/NVDEC support як Turing і новіші. Попередній
SDK 13.0 guide формулює підтримку Kepler і новіших. Це зміна межі
підтримки конкретної версії SDK/FFmpeg integration, а не доказ
відсутності фізичного Pascal encoder/decoder: поточна NVIDIA support
matrix усе ще перелічує GTX 1050 / 1050 Ti як NVENC 6th Gen / NVDEC
3rd Gen.

Для FFmpeg 9.0 джерельна перевірка мінімального driver version показує:
- NVENC API 13.1 → мінімум driver 610.00;
- NVENC API 13.0 → мінімум driver 570.0.

Тому R580 580.x не відповідає вимозі FFmpeg 9 build, який використовує
NVENC API 13.1, але за номером драйвера проходить мінімум API 13.0.
Це не гарантує роботу кожного codec/profile чи конкретного FFmpeg binary.
Якщо потрібен vendor control test — використовувати окремий FFmpeg build
із NVENC API 13.0 headers, окремий prefix і точний лог. Не downgrade
системний FFmpeg і не переносити цей proprietary результат у Nouveau
capability matrix.

### Стани доказу для GP107

| Рівень | Що відомо | Статус |
|---|---|---|
| Кремній NVENC | NVIDIA matrix: Pascal, 6th Gen, 1 engine | vendor source-proven |
| Кремній NVDEC | NVIDIA matrix: Pascal, 3rd Gen, 1 engine | vendor source-proven; exact codec row needs board/SKU resolution |
| Nouveau NVENC kernel object | Constructor є, firmware/command path — nofw placeholder | source-proven placeholder, не готовий userspace encode |
| Nouveau NVDEC kernel object | Constructor є, nofw firmware interface | source-proven placeholder, не готовий userspace decode |
| Nouveau FFmpeg/VA-API/VDPAU на GP107 | Готового GP107 codec path не знайдено | не заявляти; runtime/API UNPROVEN |
| Proprietary R580 legacy codec API | Окремий vendor control path | перевіряти тільки на R580 у власній сесії |

Джерела:
- [NVIDIA Video Encode and Decode Support Matrix](https://developer.nvidia.com/video-encode-decode-support-matrix)
- [Linux GP107 NVENC placeholder](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/nvenc/gm107.c)
- [Linux GP107 NVDEC placeholder](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/nvdec/gm107.c)
- [Linux GP107 chipset registration](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/device/base.c)
- [Nouveau VideoAcceleration](https://nouveau.freedesktop.org/VideoAcceleration.html)
- [Nouveau Feature Matrix](https://nouveau.freedesktop.org/FeatureMatrix.html)
- [NVIDIA Video Codec SDK 13.1 FFmpeg guide — Turing+](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.1/ffmpeg-with-nvidia-gpu/)
- [NVIDIA Video Codec SDK 13.0 FFmpeg guide — Kepler+](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/ffmpeg-with-nvidia-gpu/)
- [FFmpeg 9.0 NVENC source — API minimum driver versions](https://www.ffmpeg.org/doxygen/9.0/nvenc_8c_source.html)



## 16. Firmware та правильний вибір GP107 на гібридній системі

### 16.1. GP107 firmware inventory: GR bring-up не є reclocking firmware

Linux Nouveau `gp107.c` оголошує GP107 GR firmware paths:
`fecs_bl`, `fecs_inst`, `fecs_data`, `fecs_sig`,
`gpccs_bl`, `gpccs_inst`, `gpccs_data`, `gpccs_sig`,
`sw_ctx` та `sw_nonctx`. `sw_bundle_init` і `sw_method_init`
у linux-firmware можуть бути посиланнями на спільні GP102 файли.
WHENCE також містить GP107 ACR/SEC2 paths та NVDEC scrubber
з перехресними посиланнями на GP102 firmware.

Для NVIDIA firmware-блоку WHENCE вказує redistributable license
(`LicenseRef-LICENCE.nvidia`). Це дозволені до розповсюдження
бінарні firmware blobs, а не відкритий вихідний код; не копіювати
їх у цей репозиторій.

**NVDEC scrubber — не codec firmware.** `nvidia/gp107/nvdec/scrubber.bin`
використовується `gp102_fb_oneinit()` як VPR/framebuffer memory scrubber
через NVDEC Falcon. Це security/memory scrub path для framebuffer
initialization, а не H.264/HEVC decode firmware та не доказ відкритого
NVDEC userspace API.

Критично розділяти:
1. **GR/ACR/SEC2 initialization firmware** — запуск графічного engine
   та firmware-dependent підсистем Nouveau.
2. **Power-management/reclocking firmware** — окрема vendor-signed
   залежність; наявність GR/ACR/SEC2 blobs не відкриває Pascal reclocking
   і не обходить NVIDIA signature policy.

Read-only перевірка на окремому native Nouveau boot:

```sh
modinfo -F firmware nouveau | grep -E '^nvidia/(gp107|gp102)/'
FWROOT=/lib/firmware
[ -d /usr/lib/firmware/nvidia/gp107 ] && FWROOT=/usr/lib/firmware
find -L "$FWROOT/nvidia/gp107" "$FWROOT/nvidia/gp102" -type f -printf '%p %s bytes\n' 2>/dev/null | sort
ls -l "$FWROOT/nvidia/gp107/gr" "$FWROOT/nvidia/gp107/sec2" "$FWROOT/nvidia/gp107/acr" 2>&1
sudo journalctl -b -k --no-pager | grep -Ei 'nouveau|nvkm|firmware|fecs|gpccs|sec2|acr'
```

`modinfo` показує оголошені firmware dependencies; фактичні запити
та їхній результат потрібно підтвердити kernel journal. Зафіксувати
версію linux-firmware package і SHA-256 наявних blobs, якщо вони
встановлені. Не завантажувати вручну firmware з proprietary driver,
не патчити підпис, не прошивати VBIOS та не змінювати firmware.

### 16.2. Intel HD 530 + GP107: примусовий вибір dGPU в Mesa

На цій платформі desktop може працювати через Intel HD 530. Звичайний
`glxinfo` або перший Vulkan physical device тому не доводить, що тестується
GTX 1050 Ti. Mesa `DRI_PRIME` вибирає конкретний GPU для OpenGL/Vulkan;
для Vulkan суфікс `!` обмежує видимі застосунку пристрої лише вибраним GPU.

Після отримання реального BDF із `lspci -Dnnk -d 10de:1c82`
використати shell-фрагмент (не закріплювати BDF назавжди):

```sh
BDF=$(lspci -Dnn -d 10de:1c82 | awk 'NR == 1 { print $1 }')
[ -n "$BDF" ] || { echo "GP107 10de:1c82 not found" >&2; exit 1; }
DRI_BDF=$(printf '%s' "$BDF" | tr ':.' '__')

DRI_PRIME="pci-$DRI_BDF" glxinfo -B
DRI_PRIME="pci-$DRI_BDF" glmark2
DRI_PRIME="pci-$DRI_BDF!" vulkaninfo --summary
DRI_PRIME="pci-$DRI_BDF!" vkcube
```

У результатах перевіряти device name, driver name/version і PCI identity.
Якщо вивід показує Intel або `llvmpipe`, це не GP107 runtime witness.
Цей тест потрібно виконувати на native Linux із Nouveau, не підміняти
ним звичайний WSL GPU-PV шлях. За потреби додати `DRI_PRIME_DEBUG=1`
для діагностики вибору пристрою.

Джерела:
- [linux-firmware WHENCE](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/WHENCE?h=main)
- [Linux GP107 GR firmware declarations, pinned](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/gr/gp107.c)
- [GP102 framebuffer VPR scrubber hook, pinned](https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/subdev/fb/gp102.c)
- [Mesa DRI_PRIME — PCI selector for OpenGL/Vulkan and Vulkan device filtering](https://docs.mesa3d.org/envvars.html#dri_prime)
- [Nouveau reclocking limitations](https://nouveau.freedesktop.org/)

## 17. Pascal 3D command classes для GP107

У [NVIDIA public class index](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/3d/README.txt) GP107 прямо перелічений як GPU, що підтримує обидва Pascal 3D класи:

- `PASCAL_A` — `clc097.h`, ID `0xC097`;
- `PASCAL_B` — `clc197.h`, ID `0xC197`.

Це опис відкритого command-class ABI й корисний орієнтир для аналізу методів/texture layout. Це не повна апаратна специфікація й не доказ, що будь-який окремий метод працює на нашій платі. Для GP107 фактичний class selection у Nouveau source окремо вказаний у розділі про `PASCAL_COMPUTE_B (0xC1C0)`.

Джерела:
- [NVIDIA Pascal 3D class mapping](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/3d/README.txt)
- [PASCAL_A class header](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/3d/clc097.h)
- [PASCAL_B class header](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/3d/clc197.h)

## 18. Пакет інструментів і послідовність для локального агента

Нижче — порядок для локального native Linux свідка. Це не інструкція
перебудовувати робочу систему; перший Nouveau тест — окремий Live USB
або окремий boot entry з гарантованим поверненням до поточного R580.

### A. Read-only паспорт під поточним драйвером

Зберегти stdout/stderr і exit code кожної команди:
```sh
date -u --iso-8601=seconds
uname -a
cat /etc/os-release
cat /proc/cmdline
lspci -Dnnk -d 10de:1c82
lspci -Dvv -d 10de:1c82
```

Для фактичного BDF із `lspci` зафіксувати
`vendor`, `device`, `subsystem_vendor`, `subsystem_device`,
`revision`, `power_state` (якщо доступний) і symlink `driver`
у `/sys/bus/pci/devices/$BDF/`. Перевірити owner-observed
`SUBSYS_33511462` (очікуване subsystem `1462:3351`), але не
стверджувати точний MSI SKU без фізичної наклейки або VBIOS identity.

Під R580, лише якщо `nvidia-smi` справді доступний:
```sh
nvidia-smi -q
nvidia-smi --query-gpu=name,pci.bus_id,pci.device_id,pci.sub_device_id,vbios_version,memory.total,driver_version --format=csv
```
Якщо утиліта/драйвер недоступні — записати `NOT_AVAILABLE`, не
встановлювати proprietary driver лише заради отримання цього виводу.

### B. Native Nouveau boot — окреме тестове завантаження

До запуску workloads:
```sh
uname -a
cat /proc/cmdline
modinfo nouveau
modinfo -F firmware nouveau | sort -u
lspci -Dnnk -d 10de:1c82
ls -l /dev/dri /dev/dri/by-path
sudo journalctl -b -k -o short-monotonic --no-pager > nouveau-kernel.log
```

Перевірити, що `Kernel driver in use: nouveau` прив'язаний саме
до `10de:1c82` і відповідний `/dev/dri/renderD*` має symlink на
той самий PCI BDF. Не плутати Intel iGPU із GP107. Не завантажувати
Nouveau одночасно з proprietary NVIDIA KMD на цій карті.

**Atomic KMS regression gate:** зафіксувати kernel source package/commit.
Mainline fix `ed7fb901fce31588bd12ab95adc36ebcb51bc8ea` увійшов у
v7.4-rc3; однак `Cc: stable` не гарантує backport у поточне distro
ядро. У перевірених stable snapshots Linux 7.3.5 (`988117cc1bb17338c586a4e21ade88b5397eac33`) та 7.2.15 (`497791a0a96b866d90add64041c47acdff49cae6`) на 2026-11-27 backport ще не було. Для Kali `7.2.15+kali-amd64` перевірити саме source package/patch set; не робити припущень за номером.
`nouveau.atomic=0` — лише тимчасовий діагностичний boot для ядра
без fix, якщо atomic regression саме відтворюється; не постійний параметр.

Read-only DRM enumeration:
```sh
drm_info
modetest -M nouveau -c -p
```
`modetest -c -p` використовується лише для переліку connectors/CRTCs/
planes; не додавати `-s` і не запускати modeset у первинному аудиті.

### C. Окремі графічні та compute smoke tests

Пакети за назвами дистрибутива: `pciutils`, `mesa-utils`,
`vulkan-tools`, `drm-info`, `libdrm-tests`, `clinfo`,
`glmark2` або `vkmark`. Відсутній пакет позначати
`NOT_AVAILABLE`, не підміняти тест CPU renderer-ом.

**OpenGL:**
```sh
glxinfo -B
glmark2
```
Перевірити renderer/vendor/device; `llvmpipe` означає software path,
а не GP107 acceleration. За headless/Wayland/remote session можливий
інший результат — фіксувати session type.

**Гібридна графіка Intel HD 530 + GP107.** На цій машині desktop може
працювати через Intel GPU, тому звичайний `glxinfo` або перший Vulkan
device не доводить, що тестується GTX 1050 Ti. Перед GL/Vulkan smoke
tests застосувати динамічний PCI BDF selector із розділу 16.2 вище;
не дублювати й не зашивати адресу `0000:01:00.0`. Перевірити, що
`deviceName`, `driverName` і PCI identity відповідають GP107, а не Intel.
Для Vulkan selector із суфіксом `!` обмежує видимі застосунку GPU
лише вибраною картою. Якщо показано Intel або `llvmpipe`, це не GP107
runtime witness. Джерело: [Mesa `DRI_PRIME` documentation](https://docs.mesa3d.org/envvars.html).

**Vulkan:**
```sh
vulkaninfo --summary
vkcube
```
Зафіксувати `deviceName`, `driverName`, `driverInfo`,
`apiVersion`, device extensions і exit status. Для GP107 за
перевіреним per-device Mesa source очікується Vulkan 1.3, але значення
з `vulkaninfo` є остаточним runtime witness.

Для окремого детального проходу NVK debug flags запускати по одному:
```sh
NVK_DEBUG=vm vkmark
NVK_DEBUG=push,push_sync vkmark
NAK_DEBUG=print vkmark
```
Не змішувати ці журнали в один прогін; `NAK_DEBUG=print` може
генерувати великий вивід.

**OpenCL/Rusticl:**
```sh
RUSTICL_ENABLE=nouveau clinfo -l
RUSTICL_ENABLE=nouveau clinfo
```
Переконатися, що OpenCL device — саме Nouveau/GP107, а не CPU/llvmpipe.
Після enumeration запустити власний vector-add і незалежно перевірити
кожен результат на CPU; лише потім — потрібний subset OpenCL CTS.
Rusticl не є CUDA. Відсутність Rusticl у distro build фіксувати як
`NOT_AVAILABLE`, не як доказ апаратної несумісності.

**Video capability (лише запити):**
```sh
vainfo
vdpauinfo
```
Для NV130 decode TODO або відсутній API — валідний результат
`NOT_AVAILABLE`; не намагатися вмикати невідомі firmware paths.

**Power/telemetry (тільки читання):**
```sh
sensors
find /sys/class/drm -maxdepth 7 -path '*/device/hwmon/*' -type f
```
Якщо доступні debugfs pstate/hwmon counters, читати їх без запису.
Відсутні частоти/температура/потужність позначати `NOT_MEASURED`;
не виводити реальні clocks із VBIOS datasheet чи номіналу виробника.

### D. Інструменти для статичного дослідження — що використовувати

- **Linux source / NVKM:** `gp107.c`, `ctxgp107.c`, `gf100.c`,
  chipset map у `device/base.c`, а також GP107-relevant FIFO/FB/MMU/
  display code. Для кожного висновку фіксувати commit SHA.
- **NVIDIA open-gpu-doc:** `classes/3d/README.txt`, `clc097.h`,
  `clc197.h`, `clc0c0.h`, `clc1c0.h`, `clc1c0qmd.h`.
  Це public class ABI/field layout, не повна hardware spec.
- **Mesa source:** `src/nouveau/vulkan/nvk_physical_device.c`,
  NVK/NAK shader paths і старий Nouveau Gallium path; зіставляти
  pinned revisions.
- **envytools:** `nvbios` для статичного декодування вже наявної копії
  VBIOS; `rnn`/RNND для відомих register/FIFO fields; `demmt`
  для парсингу вже отриманих command-stream captures. `envydis`
  не вважати повним GP107 SASS decoder.
- **Ghidra/REA:** статичний аналіз host-side R580 `libcuda.so`/ELF,
  із чітким відділенням proprietary ABI facts від Nouveau.
- **CUDA Binary Utilities 12.x:** `nvdisasm`/`cuobjdump` — закриті
  контрольні утиліти для SM61 cubin/SASS, не частина відкритого драйвера.
- **nva:** не запускати на першому bring-up. Це прямий register-access
  інструмент; будь-які MMIO write/reset/devinit/Falcon scripts заборонені
  на робочій карті в цій фазі.

Не копіювати vendor source/decompiled code або firmware blobs у цей repo.
Зберігати лише власні traces, ABI факти, посилання, hashes і мінімальні
reproducers із відповідними ліцензіями.

### E. GP107 reset/boot matrix та evidence bundle

Якщо тестовий стенд стабільний, окремо виконати cold boot, warm reboot
і suspend/resume з D3. Для кожного стану зберігати повний kernel log
і шукати `nouveau|nvkm|SEC2|409800|PRI|FAULT|TIMEOUT`. Це окремий
від atomic KMS регресії старий GP107/GP108 GR-init quirk; не писати
в регістри для його діагностики.

Повернути один evidence bundle з UTC timestamp, точним PCI BDF/subsystem,
VBIOS version/hash (якщо безпечно доступний), kernel/Mesa/LLVM/libdrm/
linux-firmware package versions, повними logs, командами, exit codes
і SHA-256 кожного артефакту. Не публікувати serials, MAC addresses,
usernames, повну конфігурацію хоста або firmware binaries.

Під час перевірки Desktop Commander усі зареєстровані пристрої були Offline,
тому фізичний test у цьому сеансі не виконаний. Цей розділ — runbook, не runtime
результат. Evidence labels лишаються `NOT_AVAILABLE`, `NOT_MEASURED`,
`FAILED`, `PASSED`, `UNPROVEN` — не зводити їх до одного PASS/FAIL.

Джерела:
- [Mesa Rusticl](https://docs.mesa3d.org/rusticl.html)
- [Mesa environment variables / RUSTICL_ENABLE](https://docs.mesa3d.org/envvars.html)
- [llama.cpp Vulkan build guide](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)
- [Linux Nouveau GP107 compute class](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/nouveau/nvkm/engine/gr/gp107.c)
- [Mesa NVK Vulkan API version selection](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/b602686e3008239284315b67f7aea226bb8d2af2/src/nouveau/vulkan/nvk_physical_device.c)
