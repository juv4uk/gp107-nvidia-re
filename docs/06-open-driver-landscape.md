# Відкритий графічний стек NVIDIA для GP107 / GTX 1050 Ti

> Стан огляду: 2026-11-27. Це початкова карта дослідження, а не твердження про повну функціональність кожної конкретної плати.

## 1. Цільова карта обладнання

Ціль цього дослідження — NVIDIA GeForce GTX 1050 Ti на Pascal GP107:

- PCI vendor/device: `10de:1c82`.
- Власний Windows hardware ID, раніше зафіксований власником: `SUBSYS_33511462`, revision `A1`; у форматі PCI це subsystem vendor/device `1462:3351` (MSI).
- LACT `res/device_ids.json` зіставляє комбінацію `10de:1c82 + 1462:3351` з назвою **MSI GTX 1050 Ti Gaming X**. Це database-correlated ідентифікація, сумісна з retail SKU MSI **GeForce GTX 1050 Ti GAMING X 4G**; стан позначається `MODEL_CORROBORATED`, а не остаточно `MODEL_PROVEN`. Підтвердити наклейкою або read-only VBIOS board name/hash.
- Офіційні характеристики MSI для SKU GAMING X 4G: GP107-400, 4 GB GDDR5, 128-bit, 6-pin і 75 W. Це характеристики retail SKU, не runtime-вимірювання цієї плати. Не використовувати паспортні Silent/Gaming/OC clocks як доказ поточних частот.
- Кодове ім'я: GP107, сімейство Pascal / NV130.
- Архітектура обчислювальних ядер: `sm_61`.
- Профіль цього репозиторію для пропрієтарного порівняння: Linux x86-64, NVIDIA R580 `580.196.11`, Kali Rolling, kernel `7.2.15+kali-amd64`, FPC 3.2.2.

PCI ID перевіряється за [envytools PCI ID database](https://github.com/envytools/envytools/blob/master/docs/hw/pciid.rst). Hardware ID `SUBSYS_33511462` / subsystem `1462:3351` — owner-observed; [LACT device database](https://github.com/ilya-zlobintsev/LACT/blob/master/res/device_ids.json) корелює його з MSI Gaming X, а [офіційна сторінка MSI](https://www.msi.com/Graphics-Card/GeForce-GTX-1050-Ti-GAMING-X-4G/Specification) описує SKU GAMING X 4G. VBIOS version/hash і наклейка залишаються остаточними локальними свідками.

## 2. Висновок: відкритий драйвер уже існує

Для GP107 базовий відкритий стек — **Linux `nouveau` + Mesa**:

1. **Ядро Linux / DRM Nouveau** — PCI probe, modesetting, керування пам'яттю, GPU objects, каналами команд, перериваннями й апаратними підсистемами через NVKM.
2. **Mesa Nouveau Gallium** — OpenGL для старіших NVIDIA GPU, включно з Pascal.
3. **Mesa NVK** — відкритий Vulkan-драйвер; підтримку Pascal оголошено 22 квітня 2025 року.
4. **NAK** — backend-компілятор шейдерів, який використовується NVK.
5. **Zink** — OpenGL поверх Vulkan. Документація Mesa вказує, що NVK+Zink став типовим OpenGL шляхом для Turing і новіших GPU; для GP107 не слід припускати, що Zink є типовим шляхом. Для GP107 досліджуємо традиційний Nouveau Gallium OpenGL окремо від NVK Vulkan.

Офіційна сторінка Nouveau описує Vulkan як підтримуваний на Kepler і новіших GPU; Mesa вказує мінімум Linux 6.6 для NVK. Важливо не переносити загальне формулювання Mesa про Vulkan 1.4 на Pascal без перевірки per-device API version: у поточному `src/nouveau/vulkan/nvk_physical_device.c` функція `nvk_get_vk_version()` повертає Vulkan 1.3 для всіх `cls_eng3d < TURING_A`, оскільки `hostImageCopy`, необхідний для Vulkan 1.4, у цій реалізації доступний лише на Turing+. GP107/Pascal належить до цієї гілки й тому має повідомляти **Vulkan 1.3**, а не 1.4. Окремо `nvk_is_conformant()` допускає discrete GPUs від Kepler до Ada, тож Pascal входить у conformant-набір, але з API version 1.3. Остаточний runtime proof для нашої плати — `apiVersion` із `vulkaninfo --summary` або Vulkan physical-device properties на реальному GP107.

Поточний код для цього висновку зафіксований на snapshot commit [`41cf87c44dde834b1fcd5817bb6712f97875e891`](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/41cf87c44dde834b1fcd5817bb6712f97875e891/src/nouveau/vulkan/nvk_physical_device.c): перевірки `cls_eng3d < MAXWELL_A` → 1.2, `cls_eng3d < TURING_A` → 1.3, інакше → 1.4; окрема conformance-функція включає Kepler–Ada та Blackwell B.

Незалежний conformance-свідок — [Khronos Vulkan Conformant Products, entry #908](https://www.khronos.org/conformance/adopters/conformant-products/vulkan): Software Freedom Conservancy, 2025-04-18, **Vulkan_1_3**, CTS Version **1.4.1.2**; перелік продуктів явно містить GeForce GTX 1050 Ti. CTS version — версія тестового набору, не версія Vulkan API. Не плутати з окремим NVIDIA-vendor entry #858 від 2024-12-27, який декларує Vulkan 1.4 для Pascal: це proprietary NVIDIA implementation, не NVK. Цей Khronos запис доводить conformance NVK/SFC на зазначеній конфігурації загалом, але не runtime саме нашої плати; локальний `vulkaninfo` лишається обов'язковим.

Джерела:
- [Nouveau — current status](https://nouveau.freedesktop.org/)
- [Mesa — NVK](https://docs.mesa3d.org/drivers/nvk.html)
- [Collabora: NVK enabled for Maxwell, Pascal and Volta, 2025-04-22](https://www.collabora.com/news-and-blog/news-and-events/nvk-enabled-for-maxwell,-pascal,-and-volta-gpus.html)
- [Linux kernel — Nouveau driver documentation](https://github.com/torvalds/linux/blob/master/Documentation/gpu/nouveau.rst)
- [Mesa NVK physical-device API-version and conformance logic (pinned source snapshot)](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/41cf87c44dde834b1fcd5817bb6712f97875e891/src/nouveau/vulkan/nvk_physical_device.c)
- [Mesa NVK physical-device queue-family flags (same pinned source snapshot)](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/41cf87c44dde834b1fcd5817bb6712f97875e891/src/nouveau/vulkan/nvk_physical_device.c#1664)

### Khronos Conformance Registry: GTX 1050 Ti є у записі Vulkan 1.3

У Vulkan Conformant Products Registry є окремий запис **#908** від
Software Freedom Conservancy, датований 2025-04-18. Він явно перелічує
GeForce GTX 1050 і GTX 1050 Ti серед продуктів із рівнем **Vulkan_1_3**;
для нього вказано CTS Version **1.4.1.2**, Linux 6.14 (Fedora 41) та
Intel i9-10980XE. Це незалежне формальне підтвердження, що Pascal / GTX
1050 Ti входили до Vulkan 1.3 conformant submission у тій тестовій
конфігурації.

Не плутати рівень API **Vulkan_1_3** із версією тестового набору
**CTS 1.4.1.2**: це різні значення. Запис #908 не підтверджує runtime на
нашій конкретній платі, її firmware, kernel або поточній збірці Mesa.
У тому самому реєстрі є й окремі NVIDIA vendor submissions, зокрема
Pascal із Vulkan 1.4; це не слід приписувати NVK. Для GP107/NVK наше
очікування за per-device Mesa source лишається **apiVersion 1.3**.

Джерела:
- [Khronos Vulkan Conformant Products — entry #908](https://www.khronos.org/conformance/adopters/conformant-products/vulkan)
- [Mesa NVK per-device API version selection (pinned source)](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/41cf87c44dde834b1fcd5817bb6712f97875e891/src/nouveau/vulkan/nvk_physical_device.c)

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

## 2.2. NOCL: OpenCL/Rusticl поверх proprietary CUDA — не Nouveau

NOCL (раніше CLUDA) — інший compute-напрям Mesa: **compute-only Gallium
driver → Rusticl/OpenCL → NVIDIA CUDA Driver API (`libcuda.so`)**. Це не
Nouveau kernel driver і не відкритий firmware/KMD шлях. Runtime викликає
CUDA Driver API; `libcuda.so` завантажується через `dlopen`, CUDA SDK
потрібний під час build, а не як CUDA Runtime dependency. Backend
перекладає Mesa NIR у PTX, після чого PTX JIT компілює його NVIDIA driver.

Первинні матеріали Karol Herbst на XDC 2026 (2026-09-28) повідомляють:
OpenCL 3.1, понад 99% проходження тодішнього CTS-піднабору, CUDA 6.5+
як заявлену нижню межу «теоретично для всіх CUDA-capable GPU». Але ті
саме слайди кажуть, що MR ще не merged, image support відсутній, є
global/implicit stream та synchronization complications. Це стан
тестового стенда автора, не Khronos conformance certificate і не
результат на GTX 1050 Ti.

**Критична межа для нашої SM61:** доступний огляд MR !37831 від
2026-09-08 повідомляє про hardcoded `SM86` target у тодішньому diff;
NIR→PTX path не враховував SM-рівень. Це Ampere target, а не Pascal
GP107 / SM61. Огляд MR також фіксує image support як TODO. Отже, на
підставі доступного diff evidence NOCL треба позначати
**SM61 UNPROVEN / not ready for GP107**, навіть попри загальну фразу
«all CUDA capable GPUs (in theory)». Перш ніж витрачати час на build,
локальний аудит має перевірити поточний MR head, чи зник `SM86`
hardcode, як вибирається PTX `.target`, які CUDA entrypoints/version
потрібні та чи R580 PTX JIT приймає ціль для SM61.

Стан MR: XDC-слайди від 2026-09-28 казали «not merged yet», Phoronix
29.09.2026 також повідомляв MR як pending. У нашій перевірці 2026-11-27
GitLab MR сторінка/API віддала anti-bot verification, тому **поточний
open/merged state незалежно не підтверджено**. Це останній публічно
доступний статус, а не твердження про live GitLab state.

Тримати три compute шляхи окремо:

| Шлях | Kernel/compute backend | Що це означає для 1050 Ti |
|---|---|---|
| Nouveau Gallium → Rusticl | Відкритий Nouveau KMD + Mesa Gallium | Основний open-driver track; GP107 runtime UNPROVEN |
| NOCL → Rusticl → `libcuda.so` | Proprietary NVIDIA KMD/CUDA Driver API | Перспективний OpenCL frontend, але SM61 наразі UNPROVEN через SM86 target у доступному MR snapshot |
| NVIDIA OpenCL ICD | Пропрієтарний vendor OpenCL | Контрольний baseline під R580, не відкритий драйвер |

**Рекомендація локальному агенту:** поки не збирати NOCL для GP107 і не
вгадувати Meson driver token або `RUSTICL_ENABLE` значення. Спочатку
прочитати актуальний [Mesa MR !37831](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/37831)
і його останній diff; перевірити, чи підтримує він runtime capability
detection для `sm_61`, PTX target відповідного покоління, image support,
точні build options і залежності. Якщо target усе ще зафіксований як
SM86 — відкласти фізичний тест. Якщо SM61 шлях реально з'явився, робити
окремий Mesa/Rusticl build prefix під R580, не змінюючи системний
NVIDIA driver або системну Mesa; acceptance — device enumeration,
vector-add із незалежним CPU checksum, потім OpenCL CTS subset. Результат
NOCL ніколи не зараховувати як Nouveau kernel-driver PASS.

Джерела:
- [XDC 2026 primary slides — NOCL design/status](https://indico.freedesktop.org/event/12/contributions/542/attachments/350/507/nocl.html)
- [XDC 2026 session description](https://indico.freedesktop.org/event/12/contributions/542/)
- [Mesa MR !37831](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/37831)
- [Khronos — NOCL progress, 2026-10-07](https://www.khronos.org/news/permalink/nocl-making-progress-as-mesa-gallium-opencl-atop-nvidia-cuda)
- [Phoronix — NOCL status, 2026-09-29](https://www.phoronix.com/news/NOCL-OpenCL-CUDA)
- [MR !37831 SM86/image-support analysis, 2026-09-08](https://itn.lv/programmatura/mesa-draiveris-nocl-dod-opencl-uz-nvidia-cuda-luxmark-57-702-pret-64-009/)

## 2.3. Актуальна Mesa baseline та межа Vulkan Video

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
- [Linux 7.3.6: Nouveau display source](https://github.com/gregkh/linux/blob/v7.3.6/drivers/gpu/drm/nouveau/nouveau_display.c)
- [Linux 7.3.5: `988117cc1bb17338c586a4e21ade88b5397eac33`](https://github.com/gregkh/linux/blob/988117cc1bb17338c586a4e21ade88b5397eac33/drivers/gpu/drm/nouveau/nouveau_display.c)
- [Linux 7.2.15: `497791a0a96b866d90add64041c47acdff49cae6`](https://github.com/gregkh/linux/blob/497791a0a96b866d90add64041c47acdff49cae6/drivers/gpu/drm/nouveau/nouveau_display.c)

Усі три перевірені source files повернули однаковий blob
`d71dcfc6ee66b3349cd87404aa15ea9823417d36`, у якому немає
`nouveau_mode_config_funcs_atomic`, `.atomic_commit` або
`.atomic_check`. Отже навіть stable 7.3.6 станом на 2026-11-27 не містить
цього fix; `Cc: stable@vger.kernel.org` саме по собі не доводить backport.

Для нашого зафіксованого Kali/kernel `7.2.15+kali-amd64` обов'язково
перевірити source package/patch set або callbacks у зібраному Nouveau,
а не робити висновок лише з номера upstream stable. Якщо backport
відсутній і регресія відтворюється, `nouveau.atomic=0` — лише тимчасова
діагностика; acceptance має перевіряти normal atomic KMS на ядрі з fix.

Джерела:
- [GP107 regression report and follow-up (2026-11-02 — 2026-11-25)](https://kernelthread.org/t/OS7PR01MB1391484D564CF93DFBB4C1DCE966A2@OS7PR01MB13914.jpnprd01.prod.outlook.kr)
- [Nouveau work item #517: GP107 atomic modesetting regression](https://gitlab.freedesktop.org/drm/nouveau/-/work_items/517)
- [Introduced: atomic modesetting by default for NV50+](https://github.com/torvalds/linux/commit/2652aca460dcfdd0d169bbfa358aa15804dc736b)
- [Fix: add atomic DRM mode-config callbacks](https://github.com/torvalds/linux/commit/ed7fb901fce31588bd12ab95adc36ebcb51bc8ea)

### Важлива різниця в назвах: GK107 (Kepler) ≠ GP107 (Pascal)

У списках патчів Nouveau трапляється серія
[`drm/nouveau: fix GK107 VDPAU regressions`](https://lists.openwall.net/linux-kernel/2026/09/13/863).
Вона стосується **GK107 / Kepler** (legacy MSVLD/MSPDEC/MSPPP video engines,
FIFO engine-context mapping та nonstall-event handling), а не **GP107 /
Pascal** із GTX 1050 Ti. Попри схожий рядок моделі, це інші чипи та інші
engine paths. Не переносити ці патчі й не рахувати їх як виправлення
NV130/GP107 video decode.

Цей пошук ще раз підкреслює правило: фільтрувати upstream issues/patches
за точним chipset code (`GK107` проти `GP107`), а не лише за числом `107`
або загальним словом «Nouveau». Для нашої карти NV130 video decode лишається
TODO у Feature Matrix; GP107 NVDEC kernel object і `scrubber.bin` hooks не
є доказом готового VDPAU/VA-API codec path.

Джерела:
- [GK107 VDPAU patch series (Kepler, 2026-09-13)](https://lists.openwall.net/linux-kernel/2026/09/13/863)
- [Follow-up discussion and test results (GK208B/Kepler)](https://www.mail-archive.com/dri-devel%40lists.freedesktop.org/msg646346.html)
- [Nouveau Feature Matrix](https://nouveau.freedesktop.org/FeatureMatrix.html)
### Feature matrix: що ще не готове або залежить від покоління

Офіційна [Nouveau Feature Matrix](https://nouveau.freedesktop.org/FeatureMatrix.html)
пояснює, що її статуси — великі зрізи функціональності, оновлюються рідко,
а `EXTFW` означає залежність від firmware з бінарного драйвера. Сторінка
має дату останньої редакції 2026-10-19. У колонці NV130 вона позначає:
- accelerated video decoding (VDPAU/XvMC): `TODO`;
- power management: `TODO`;
- compute: `WIP`;

Важлива межа: `Compute: WIP` у загальній Nouveau Feature Matrix не слід
ототожнювати з відсутністю Vulkan compute у Mesa NVK. У перевіреному Mesa
source snapshot нижче NVK оголошує queue family з `VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT`.
Це статичний source evidence для Vulkan API path, а не доказ успішного
виконання compute workload на конкретній GTX 1050 Ti: потрібні runtime
queue properties, мінімальний compute dispatch і перевірка результату.

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
[`41cf87c44dde834b1fcd5817bb6712f97875e891`](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/41cf87c44dde834b1fcd5817bb6712f97875e891/src/nouveau/vulkan/nvk_physical_device.c):

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
- [Mesa pinned source — per-device NVK API version and conformance predicates](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/41cf87c44dde834b1fcd5817bb6712f97875e891/src/nouveau/vulkan/nvk_physical_device.c)


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
точного зіставлення VBIOS/SKU. У нас є owner-observed subsystem
`1462:3351`, але точний board variant ще потребує фізичної наклейки
або перевірки VBIOS identity.

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



**Нюанс офіційної NVIDIA NVDEC matrix:** GTX 1050 / 1050 Ti зустрічається у двох однаково названих рядках з різними значеннями окремих codec/profile колонок. Не виводити 10-bit, 4:2:2 або 4:4:4 можливості нашої плати з узагальненої маркетингової назви. Потрібно звірити точний SKU/VBIOS, а потім перевірити фактичний decoder API на контрольному R580; жоден із цих hardware rows не є доказом Nouveau userspace decode.

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
device не доводить, що тестується GTX 1050 Ti. Після окремого Nouveau
boot отримати BDF динамічно; не копіювати у звіт чи скрипт попередній
BDF із прикладу:
```sh
BDF=$(lspci -Dnn -d 10de:1c82 | awk 'NR == 1 { print $1 }')
[ -n "$BDF" ] || { echo "GP107 10de:1c82 not found" >&2; exit 1; }
DRI_BDF=$(printf '%s' "$BDF" | tr ':.' '__')

DRI_PRIME_DEBUG=1 DRI_PRIME="pci-$DRI_BDF" glxinfo -B
DRI_PRIME="pci-$DRI_BDF" glmark2
DRI_PRIME_DEBUG=1 DRI_PRIME="pci-$DRI_BDF!" vulkaninfo --summary
DRI_PRIME="pci-$DRI_BDF!" vkcube
```
Для Vulkan суфікс `!` обмежує видимі застосунку пристрої вибраним GPU.
У кожному виводі перевірити `deviceName`, `driverName`, `driverInfo`
та PCI identity; якщо показано Intel або llvmpipe, це не GP107 runtime
witness. Джерело: [Mesa `DRI_PRIME` documentation](https://docs.mesa3d.org/envvars.html).
**Vulkan:**
```sh
vulkaninfo --summary
vkcube
```
Зафіксувати `deviceName`, `driverName`, `driverInfo`,
`apiVersion`, device extensions і exit status. Для GP107 за
перевіреним per-device Mesa source очікується Vulkan 1.3; у тому самому
pinned NVK source queue family має graphics + compute + transfer flags.
Але це лише source evidence: потрібні runtime queue-family properties
та окремий реальний compute dispatch з перевіркою результату на CPU.
`vkcube` перевіряє graphics/presentation, **не** доводить compute.

Після звичайного Vulkan smoke test зробити окремий діагностичний прогін:
```sh
MESA_VK_ABORT_ON_DEVICE_LOSS=1 DRI_PRIME="pci-$DRI_BDF!" vkcube
```
Цей Mesa прапорець примушує драйвер викликати `abort()` відразу після
виявлення device loss. Запускати окремо від benchmark і зберігати exit
status/core (якщо політика хоста дозволяє) та повний kernel journal.
Не вмикати `NVK_I_WANT_A_BROKEN_VULKAN_DRIVER`: це override для GPU з
неперевіреною/зламаною підтримкою, а GP107 має офіційний NVK Pascal path.

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
- [Mesa NVK Vulkan API version and queue-family selection](https://chromium.googlesource.com/external/gitlab.freedesktop.org/mesa/mesa/+/41cf87c44dde834b1fcd5817bb6712f97875e891/src/nouveau/vulkan/nvk_physical_device.c)


## 19. Compute paths для GP107: що відкрите, а що залежить від R580

Для GTX 1050 Ti існують кілька різних compute/API шляхів. Не об'єднувати
їх під ярликом «відкритий драйвер»: вони мають різні kernel backends,
userspace frontends та залежності від NVIDIA proprietary driver.

| Шлях | Kernel/runtime backend | Open-source частина | Статус для GP107 |
|---|---|---|---|
| NVK Vulkan compute | Nouveau kernel + Mesa NVK/NAK | Відкритий kernel і userspace driver | Khronos Vulkan 1.3 conformance entry містить GTX 1050 Ti; наша плата runtime UNPROVEN |
| Nouveau Gallium → Rusticl/OpenCL | Nouveau kernel + Gallium | Відкритий kernel/userspace OpenCL frontend | `nouveau` має upstream Rusticl support, але потребує opt-in; GP107 runtime/CTS UNPROVEN |
| NOCL → Rusticl/OpenCL → CUDA | NVIDIA proprietary R580 KMD + CUDA Driver API | Відкриті Mesa Gallium/Rusticl/NOCL шари; закритий CUDA driver backend | Reviewed MR snapshot: SM61 blocked by SM86 target; live MR state NOT_VERIFIED |
| NVIDIA OpenCL ICD | NVIDIA proprietary KMD + userspace ICD | Закритий vendor stack | Khronos OpenCL 3.0 entry #377 (2021-09-08) містить GTX 1050 Ti; використовувати як vendor control, не як open-driver evidence |

### 19.1. NVK Vulkan compute — відкритий шлях без CUDA

Після успішного NVK device enumeration перевірити Vulkan compute не лише
графічним `vkcube`, а невеликим Vulkan compute sample з readback та
CPU checksum. Для Pascal очікуваний advertised API — Vulkan 1.3;
Khronos SFC entry #908 засвідчує Vulkan 1.3 conformance на GTX 1050 Ti,
але не є runtime свідком нашої плати. За потреби наступний workload —
окремий llama.cpp Vulkan build, тільки після базового device/compute test.
Не порівнювати Vulkan API version з NVIDIA proprietary Vulkan 1.4 entry.

### 19.2. Nouveau Gallium → Mesa Rusticl → OpenCL

Це повністю відкритий шлях на рівні kernel/userspace driver, але його
GP107 OpenCL runtime і conformance ще не доведені. Rusticl використовує
Gallium, не CUDA; пристрої не експонуються автоматично. Порядок перевірки:

```sh
RUSTICL_ENABLE=nouveau clinfo -l
RUSTICL_ENABLE=nouveau clinfo
```

Якщо видно саме GP107/Nouveau device, виконати власний vector-add,
перевірити результат CPU checksum, потім потрібний OpenCL CTS subset.
Якщо немає device — перевірити, чи пакет Mesa зібраний з Rusticl і чи
цей конкретний Nouveau build доступний; порожній `clinfo` без opt-in
не є тестом несумісності. Не трактувати Rusticl як CUDA compatibility.

### 19.3. NOCL: відкритий OpenCL frontend поверх закритого CUDA driver

**NOCL** (раніше CLUDA) — compute-only Gallium driver для Rusticl,
що реалізує OpenCL поверх NVIDIA CUDA Driver API. Це не Nouveau KMD,
не Nova і не відкритий шлях до firmware/MMIO. Він може бути корисним
саме для цієї Pascal карти, бо використовує наявний proprietary R580
CUDA driver backend, але поки це окремий development track.

У презентації Karol Herbst на XDC 2026 (2026-09-28) зафіксовано:
- NOCL реалізує OpenCL 3.1; автор повідомив про понад 99% CTS pass rate
  на тестованій конфігурації, але конкретна GTX 1050 Ti там не названа;
- потрібен CUDA Driver API 6.5 або новіший; автор зазначив підтримку
  всіх CUDA-capable GPU «in theory» — це не GP107 runtime proof;
- `libcuda.so` завантажується через `dlopen` із proprietary driver;
  CUDA SDK потрібен для build-time, але CUDA toolkit не є runtime backend;
- compiler path: NIR passes → PTX → CUDA JIT;
- image support ще має суттєву прогалину: CUDA використовує unified
  image/sampler handle, тоді як OpenCL/Vulkan потребують independent
  image/sampler representation. Це обмежує image workloads і є однією
  з незавершених ділянок.

Phoronix 2026-09-29 повідомляв, що Mesa GitLab MR !37831 ще очікував
merge. Прямий GitLab MR у цьому проході повертав anti-bot access page,
а свіжішого незалежного підтвердження merge не знайдено; тому точний
стан MR треба перевірити перед build, не припускаючи, що NOCL уже є
в Mesa release. Не створювати системний build наосліп.

**SM61 gate за останнім доступним source review (08.09.2026):** детальний
розбір MR !37831 повідомляє, що reviewed snapshot мав hardcoded SM86
(Ampere) у hardware/test target profile, а NIR→PTX generator ще не
враховував рівень SM. Це не доводить, що кожна гілка компілятора завжди
видає `.target sm_86`, але означає, що Pascal target у цьому snapshot
не підтверджений. Для нашого GP107 (compute capability 6.1 / SM61) NOCL
не можна вважати сумісним, доки source audit не покаже target-aware
lowering і коректний PTX для SM61. NVIDIA PTX JIT сумісність спрямована
вперед: PTX target може запускатися на рівному або вищому compute
capability, але не назад; отже PTX, націлений на `sm_86`, не JIT-иться
на SM61. Не замінювати literal SM86 на SM61 механічно: перевірити NIR
opcodes, feature gates, PTX `.version`, `.target`, та відсутність
Ampere-only інструкцій. До завершення аудиту статус для нашої карти —
`NOT_SUPPORTED_BY_REVIEWED_SOURCE_SNAPSHOT / SM61_UNPROVEN`.

Огляд !37831 від 08.09.2026 наводить 12 commits, 34 files, 102 comments,
останню зміну коду 09.11.2025, reduced CTS 3886 pass / 4 fail / 0 crash
і LuxMark 57,702 проти 64,009 на RTX A6000. Це Ampere/SM86 test evidence,
не тест GTX 1050 Ti. На XDC 28.09.2026 автор також повідомив, що MR ще
не merged і image support залишався незавершеним. Поточний MR endpoint
не вдалося незалежно прочитати через GitLab anti-bot challenge, тому
ці дані — останній перевірений snapshot, не live status на 27.11.2026.

**R580 API gate окремо від SM61 gate:** NVIDIA release notes для
580.196.11 (2026-11-23) декларують CUDA 13.x підтримку, включно з
Pascal; CUDA 13.0 GA має мінімальну вимогу Linux driver 580.65.06.
Це підтверджує придатність R580.196.11 як загального CUDA Driver API
baseline, але не доводить NOCL сумісність. XDC-слайди показують
`cuGetProcAddress_v2`; його фактичний export/ABI та інші entrypoints
треба перевірити у конкретній `libcuda.so`, а значення
`cuDriverGetVersion()` — прочитати runtime probe. CUDA Driver Entry
Point Access API доступний починаючи з CUDA 11.3; окремо звірити
конкретну ABI-версію функції `_v2`.

Локальна перевірка лише читання:
```sh
LIBCUDA=$(readlink -f "$(ldconfig -p | awk '/libcuda\.so\.1 / {print $NF; exit}')")
readelf -Ws "$LIBCUDA" | grep -E 'cu(GetProcAddress(_v2)?|DriverGetVersion)'
objdump -T "$LIBCUDA" | grep -E 'cu(GetProcAddress(_v2)?|DriverGetVersion)'
```
Після цього потрібен мінімальний власний `dlopen` probe, що викликає
`cuInit(0)`, `cuDriverGetVersion()` та резолвить фактичні required
entrypoints. Symbol grep сам по собі не є runtime PASS. Не оновлювати
R580 і не встановлювати CUDA Toolkit у системний prefix заради цього.

Джерела:
- [ITN: review MR !37831, 2026-09-08](https://itn.lv/programmatura/mesa-draiveris-nocl-dod-opencl-uz-nvidia-cuda-luxmark-57-702-pret-64-009/)
- [NVIDIA PTX JIT compatibility](https://developer.nvidia.com/blog/understanding-ptx-the-assembly-language-of-gpu-computing/)
- [NVIDIA PTX ISA 8.7: .target semantics](https://docs.nvidia.com/cuda/pdf/ptx_isa_8.7.pdf)
- [NVIDIA R580.196.11 release notes](https://docs.nvidia.com/datacenter/tesla/tesla-release-notes-580-196-11/index.html)
- [CUDA 13.0.3 minimum driver version](https://docs.nvidia.com/cuda/archive/13.0.3/cuda-toolkit-release-notes/index.html)
- [CUDA Driver Entry Point Access, introduced in CUDA 11.3](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/driver-entry-point-access.html)
- [XDC NOCL slides](https://indico.freedesktop.org/event/12/contributions/542/attachments/350/507/nocl.html)

**Якщо MR merged або є придатний тестовий branch**, локальний агент має:
1. В окремому worktree/prefix зафіксувати Mesa commit і MR head.
2. Перевірити build dependencies/flags NOCL у самому source tree і
   версію CUDA SDK, яку очікує саме цей commit; не використовувати
   system Mesa як build destination.
3. Переконатися, що R580 надає CUDA Driver API і Pascal device
   compute capability 6.1. Не припускати, що `CUDA 6.5+` у презентації
   гарантує сучасний NOCL build або кожну функцію API на R580.
4. Через Rusticl device enumeration перевірити, що backend названий
   NOCL/CUDA, а PCI identity — `10de:1c82`; потім vector-add із CPU
   checksum та відповідний CTS subset.
5. Окремо відзначити image APIs як `NOT_AVAILABLE`/непідтримані,
   якщо вони ще не реалізовані.

Цей шлях може дати відкриту реалізацію OpenCL frontend на GP107,
але kernel-mode driver, PTX JIT та GPU firmware залишаються NVIDIA
proprietary. Не рахувати його як повністю відкритий NVIDIA driver.

### 19.4. NVIDIA OpenCL ICD — контрольний закритий baseline

Khronos OpenCL Conformant Products містить NVIDIA entry #377 від
2021-09-08 із **OpenCL_3_0**; product list прямо включає GeForce GTX 1050 Ti
на NVIDIA proprietary Linux OpenCL driver. Це доводить vendor conformance
для сімейства/заявленої конфігурації, не runtime поточної плати та не
сумісність NOCL.

Для порівняльного vendor control під R580:
```sh
nvidia-smi --query-gpu=name,pci.bus_id,driver_version --format=csv
clinfo -l
clinfo
```
Після ідентифікації NVIDIA OpenCL platform виконати той самий vector-add
і відповідний CTS subset, які будуть використані для Rusticl/NOCL. Цей
baseline потрібен для порівняння, але залишається повністю proprietary.

Джерела:
- [XDC 2026: NOCL talk and slides](https://indico.freedesktop.org/event/12/contributions/542/)
- [NOCL presentation: architecture, status, CTS, CUDA API and image limitations](https://indico.freedesktop.org/event/12/contributions/542/attachments/350/507/nocl.html)
- [Phoronix: NOCL MR status as reported 2026-09-29](https://www.phoronix.com/news/NOCL-OpenCL-CUDA)
- [Khronos: GeForce GTX 1050 Ti in NVIDIA OpenCL 3.0 conformance entry #377](https://www.khronos.org/conformance/adopters/conformant-products/opencl)
- [Khronos: GTX 1050 Ti in Software Freedom Conservancy Vulkan 1.3 entry #908](https://www.khronos.org/conformance/adopters/conformant-products/vulkan)
- [Mesa Rusticl build/runtime documentation](https://docs.mesa3d.org/rusticl.html)
