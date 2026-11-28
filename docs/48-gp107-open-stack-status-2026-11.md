# Відкритий стек NVIDIA для Pascal GP107: статус станом на листопад 2026

**Об'єкт:** NVIDIA GP107 (GeForce GTX 1050 Ti), Pascal, PCI `10de:1c82`, Linux.
**Призначення:** вхідні дані для команди реверс-інжинірингу, що веде три смуги: (A) відкритий стек, (B) спостереження за роботою пропрієтарного стеку в рантаймі, (C) статичний аналіз — **поза межами цього звіту** (див. розділ 6).
**Дата звіту:** 2026-11-28. Усі джерела перевірені цією датою; для сторінок без власної дати публікації це позначено явно.

**Правило звіту:** твердження без датованого джерела не є твердженням. Там, де джерела немає, стоїть `UNKNOWN` і перелік того, що саме шукалося. Числових показників продуктивності в звіті немає — жодне з наведених джерел не дає вимірювань саме для GP107, а переносити чужі цифри на інше залізо заборонено правилами проєкту.

---

## 1. Зведена таблиця можливостей

| Можливість (GP107, Pascal) | Статус | Джерело з датою |
|---|---|---|
| NVK як типовий Vulkan-драйвер (увімкнений за замовчуванням) | **PASS** | Collabora, 2025-04-22 [S1]; Mesa 25.1 [S1] |
| NVK: заявлена відповідність Vulkan 1.4 | **PASS** (заявлено Mesa) | docs.mesa3d.org/drivers/nvk.html, без дати, перевірено 2026-11-28 [S2]; Phoronix, 2025-04-23 [S3] |
| NVK: запис у реєстрі Khronos для Pascal | **PARTIAL** — зареєстровано **Vulkan 1.3**, CTS 1.4.1.2, не 1.4 | Реєстр Khronos, запис Software Freedom Conservancy від 2025-04-18 (перевірено 2026-11-28) [S4] |
| Zink як **типовий** OpenGL-шлях для Pascal | **UNKNOWN** | Див. §2.3 і §7 — прямих джерел немає |
| NVK+Zink як OpenGL для Pascal узагалі (увімкнення вручну) | **PASS** (механізм існує) | Phoronix, 2024-02-21 (`NOUVEAU_USE_ZINK=1`) [S5]; XDC 2025, 2025-09-29/10-01 [S6] |
| KMS / modesetting / 2D-вивід (nouveau) | **PASS** | FeatureMatrix, NV130, без дати, перевірено 2026-11-28 [S7]; Phoronix, 2025-12-11 (GTX 1080 на Linux 6.18 + Mesa 26.0-devel) [S8] |
| Atomic modesetting за замовчуванням на NV50+ | **PARTIAL** — регресія саме на GP107 у ядрах 7.3.x, виправлена в mainline | Звіт у списку nouveau, 2026-11-02 [S9a]; патч Dave Airlie, 2026-11-11 [S9b]; фікс `ed7fb901fce3` у mainline, підтверджено 2026-11-25 [S9c] |
| Suspend / resume (S3) | **UNKNOWN** | Див. §3.4 і §7 |
| Reclocking (перехід на штатні частоти) | **NOT_AVAILABLE** | Collabora, 2025-04-22 [S1]; Phoronix, 2025-12-11 [S8]; nouveau PowerManagement, без дати, перевірено 2026-11-28 [S10] |
| Power management / керування живленням | **NOT_AVAILABLE** | nouveau PowerManagement [S10] (PM лише Turing+); Collabora, 2025-04-22 [S1] |
| NVDEC-декодування через відкритий стек (VA-API / VDPAU / Vulkan Video) | **NOT_AVAILABLE** | FeatureMatrix, NV130, рядок «video decoding accel» = TODO [S7]; Phoronix, 2026-07-31 і 2026-08-22 (лише Turing+) [S11],[S12] |
| NVENC-кодування через відкритий стек | **NOT_AVAILABLE** | FeatureMatrix (рядка про encode немає взагалі) [S7]; NVK Vulkan Video = лише декодування H.264 [S12] |
| Vulkan compute на NVK | **PASS** | Collabora, 2025-04-22 [S1]; реєстр Khronos, 2025-04-18 [S4] |
| OpenCL через Rusticl на nouveau (nvc0) | **PARTIAL** — OpenCL 3.0, потрібен `RUSTICL_ENABLE` | Phoronix, 2025-12-11 [S8]; docs.mesa3d.org/rusticl, без дати, перевірено 2026-11-28 [S13] |
| OpenCL 3.1 на Pascal через Rusticl | **UNKNOWN** — 3.1 перелічено для asahi/iris/radeonsi/llvmpipe/zink, не для nouveau | Mesa 26.2.0 release notes, 2026-08-05 [S14] |
| Підтримка з боку драйвера NVIDIA (смуга B) | **PARTIAL** — 580 остання гілка для Pascal | Phoronix, 2025-12-11 [S8]; Phoronix, 2025-12-26 [S15] |
| GSP / драйвер Nova | **NOT_AVAILABLE** (апаратно відсутній GSP) | Phoronix, 2025-12-11 [S8] |

---

## 2. NVK: Vulkan на Pascal

### 2.1. Увімкнення та конформанс

NVK став конформантним драйвером Vulkan на Maxwell, Pascal і Volta 22 квітня 2025 року і з Mesa 25.1 увімкнений на цих GPU за замовчуванням. [S1] Тоді ж Collabora прямо назвала причину, чому це «пізніше, ніж хотілося»: «Most of Maxwell, Pascal, and Volta are stuck forever at boot clocks due to firmware limitations which the Nouveau kernel module can't practically work around». [S1]

Документація Mesa станом на 2026-11-28 формулює так: NVK підтримує Kepler і новіші аж до Ada плюс споживчий Blackwell, і «NVK is a conformant Vulkan 1.4 implementation for all officially supported GPUs». [S2]

### 2.2. Розбіжність, яку треба зафіксувати в матриці

Реєстр конформансу Khronos містить запис **Software Freedom Conservancy від 2025-04-18, `Vulkan_1_3`, номер 908**, з переліком Pascal-карт, серед яких явно присутня **GeForce GTX 1050 Ti**, CTS 1.4.1.2, Linux 6.14 (Fedora 41). [S4] Тобто офіційно зареєстрований рівень для NVK на Pascal — **Vulkan 1.3**, тоді як документація Mesa і преса говорять про 1.4. [S2],[S3] Для матриці це дві різні клітинки: «заявлено Mesa» і «зареєстровано Khronos». Згортати їх в одну цифру не можна.

### 2.3. Zink як типовий OpenGL для Pascal — стан невідомий

Що відомо достовірно:

- Turing+ отримали NVK+Zink за замовчуванням з Mesa 25.1 (березень 2025, MR від Collabora). [S5]
- У анонсі Mesa 25.2.0 (2025-08-06) сказано буквально: «Kepler users will still get the old Nouveau GL driver as it is still the default **pre-Turing**». [S16] Тобто на момент 25.2 Pascal ще на старому Nouveau GL.
- Collabora, 2025-08-04: «We may still move pre-Turing GPUs to Zink eventually but that won't happen in this release». [S17]
- Слайди XDC 2025 (29.09–01.10.2025): «Turing+ now uses Zink by default… **Kepler through Volta will come later**». [S6]
- Анонс Mesa 25.3.1 (2025-12-04) обмежує вилучення старого драйвера явно Turing і новішими: «the old driver no longer officially supports Turing or later… This affects most nvidia gpus from 2018 or later». [S18]

**Чого знайти не вдалося:** жодного джерела 2026 року, яке б підтверджувало або спростовувало перехід Pascal (NV130) на Zink за замовчуванням у Mesa 26.0–26.3. Перевірено: release notes Mesa 26.0.0 (2026-02-11), 26.1.0 (2026-05-06), 26.2.0 (2026-08-05), 26.3.0 (2026-11-09) — згадок про зміну типового OpenGL-драйвера для pre-Turing немає [S19],[S20],[S14],[S21]; пошук по Phoronix і Collabora за 2026 рік — теж нічого. Отже статус — `UNKNOWN`, і його треба виміряти на місці, а не припускати.

Практичний наслідок: `NOUVEAU_USE_ZINK=1` / `NOUVEAU_USE_ZINK=0` лишаються робочим способом явно обрати шлях (змінна з'явилася ще в Mesa 24.1). [S5],[S6]

### 2.4. Специфічні застереження для Pascal

- **Компілятор і «хвости» pre-Turing досі правляться.** У Mesa 26.1.5 (2026-07-15) є фікс «nvk: Handle large indirect stride pre-Turing» — тобто pre-Turing-код у 2026 році ще отримував виправлення. [S22]
- **Ядро важливіше за Mesa.** Слайд XDC 2025 прямо каже: «There are Nouveau kernel bugs NVK hits harder than NGL — This means Zink hits those bugs». [S6] Для Pascal це означає, що збій у тестах треба спершу локалізувати в драйвері ядра, а не в NVK.
- **Zink болючий саме для композиторів.** За тим самим джерелом: ядро рендерингу було стабільним, а «compositors, the X server, and web browsers were tricky», і станом на вересень 2025 лишався баг із мерехтінням Firefox. [S6] Якщо проєкт тестує Zink на Pascal — це той клас застосунків, де регресії найімовірніші.
- **Стиснення кадрового буфера (DCC) на Pascal не заявлене.** На XDC 2026 (30.09.2026) стиснення в NVK обговорювалося як таке, що вимагає великих сторінок і ще не готове до шипу; для Pascal окремого твердження немає. [S23] Статус для GP107 — `UNKNOWN`, не «працює».

---

## 3. Драйвер ядра Nouveau на Pascal

### 3.1. Що працює

FeatureMatrix проєкту nouveau для стовпця **NV130** (це і є GP10x/Pascal) дає: basic 2D (EXA) — DONE, fast 2D (XRender) — DONE, play videos (Xv) — DONE, Kernel Mode Setting — DONE, MST (Multi-stream) — DONE, SST — DONE, laptop discrete graphics / hybrid outputs — DONE, примітиви, текстури, vertex/fragment/geometry/tessellation — DONE. [S7] Сторінка не датована і сама попереджає, що «the matrix is updated rarely»; дата перевірки — 2026-11-28.

Дати підтвердження з боку преси: у грудні 2025 року Phoronix підняв GTX 1080 (Pascal) на Nouveau з ядром Linux 6.18 і Mesa 26.0-devel і отримав робочу систему (окремі проблеми були з POST на конкретній платі, а не з драйвером). [S8]

### 3.2. Регресія 2026 року, що б'є саме по GP107

Це найважливіша новина розділу. **2 листопада 2026** у списку розсилки nouveau з'явився звіт Eric Kim: на ноутбуці з **GP107** (гібрид з Intel iGPU) ядра після коміту `2652aca460dcfdd0d169bbfa358aa15804dc736b` («enable atomic modesetting by default for NV50+ gpus») падають у NULL pointer dereference під час ініціалізації дисплея в `drm_atomic_commit`; завантаження з `nouveau.atomic=0` проблему знімає. [S9a] Причину автор описав точно: `atomic_(check|commit)` відсутні в `nouveau_mode_config_funcs`, бо коміт `6c65db809796` відкотив їх через ненадійність на pre-atomic залізі.

Це вже **друга** спроба того самого виправлення, і перша впала на старішому залізі: у січні 2026 Lyude Paul додала `atomic_(check|commit)` безумовно (коміт `448a2071a843`), це потрапило в stable 6.18.8 і зламало **NV04** — на pre-nv50 немає відповідних atomic-хелперів, і 2026-02-01 надійшов звіт про NULL deref [S38]. Патч відкотили (`6c65db809796`), і саме тому листопадовий фікс Airlie задає **окремий** набір `drm_mode_config_funcs` лише для atomic-шляху, а не чіпає спільний.

Далі події розвивалися так: **11 листопада 2026** Dave Airlie надіслав патч, який задає окремий набір `drm_mode_config_funcs` для atomic-шляху [S9b]; **25 листопада 2026** звіт закрито — фікс `ed7fb901fce31588bd12ab95adc36ebcb51bc8ea` увійшов у mainline [S9c]. Тобто станом на 2026-11-28 регресія виправлена в mainline, але **не обов'язково в тому ядрі, яке стоїть у вас**: усе залежить від того, чи є фікс у вашій гілці.

Наслідок: **на 2026-11-28 «KMS/display» — це PASS із застереженням**, а не безумовний PASS; конкретна версія ядра стає частиною результату тесту.

### 3.3. Що не працює: reclocking і power management

- Collabora (2025-04-22): більшість Maxwell/Pascal/Volta «stuck forever at boot clocks due to firmware limitations which the Nouveau kernel module can't practically work around». [S1]
- Сторінка nouveau PowerManagement: керування живленням через `nouveau.config=NvGspRm=1` доступне **починаючи з Turing і Ampere** (з Linux 6.7), на Ada і новіших — за замовчуванням. [S10] Pascal у цьому переліку відсутній.
- Phoronix (2025-12-11): лише Maxwell першого покоління (GTX 750) має reclocking у відкритому стеку; на GM200 і новіших (тобто й на Pascal) вимоги до підписаної прошивки блокують належне керування живленням, тому карта працює на «very slow boot clock frequencies». [S8]

### 3.4. Поточне пояснення обмеження і що з ним робилося у 2026

Пояснення не змінилося: Nouveau не має практичного способу обійти вимогу підписаної прошивки PMU, а GSP, який зняв би цю проблему, з'явився лише в Turing. [S1],[S8],[S10]

Що варто знати про спроби це зламати:

- **GP10B (Tegra X2) — не наш випадок.** У серпні 2025 року Aaron Kling надіслав патч на ~200 рядків, який вмикає reclocking для Pascal **GP10B** у складі Tegra, бо там «gpu clock handling is done by the bpmp». [S24] Це SoC-шлях, який для дискретного GP107 не застосовний; посилатися на нього як на «reclocking для Pascal» некоректно.
- **Запит до NVIDIA від 2026-10-10** — це публічне прохання користувача видати підписану прошивку саме для **GP107**, яка дозволила б відкритий reclocking. [S25] Тобто станом на жовтень 2026 такої прошивки немає; джерело фіксує саме відсутність, а не прогрес.
- **Nouveau-DKMS (2026-10-26)** — позадеревне відгалуження, зосереджене на Fermi, з дорожньою картою, де є надії й на Pascal. [S26] Це downstream, у Guix-снепшот воно не входить; для смуги A це не опора, а спостережуваний факт.

### 3.5. Suspend / resume

`UNKNOWN`. Жодного джерела, яке б стосувалося S3 саме на Pascal у 2026 році, знайти не вдалося. Шукалося: «nouveau suspend resume Pascal GP107 works», «nouveau Pascal fbsr non-GSP suspend resume», списки nouveau@lists.freedesktop.org за 2026 рік. Усі знайдені матеріали 2026 року про suspend/resume nouveau стосуються **GSP-прошивки R570**, тобто Turing і новіших: баг із `bEnteringGCOff` / FBSR, описаний Dave Airlie 2026-02-04 і виправлений у drm-misc-fixes. [S27] Переносити ці висновки на Pascal не можна — там інший шлях збереження VRAM і немає GSP.

---

## 4. Відео: NVDEC і NVENC на Pascal у відкритому стеку

### 4.1. NVDEC — декодування

**Через класичний відкритий стек (VA-API/VDPAU у Mesa/nouveau): NOT_AVAILABLE.**
FeatureMatrix для NV130 у рядку «video decoding accel (VDPAU/XvMC)» ставить **TODO** (для NV50/NVC0/NVE0/NVF0/NV110 там EXTFW, тобто «працює за наявності прошивки»; для Pascal — ні). [S7] Варто зафіксувати окремо, що VDPAU-стейт-трекер узагалі вилучено з Mesa в 25.3 (анонс 2025-12-04), тож цей шлях закритий не лише для Pascal. [S18]

**Через Vulkan Video у NVK: NOT_AVAILABLE для Pascal.**
H.264-декодування в NVK злито для Mesa 26.3 (Phoronix, 2026-08-22), і воно **залежить від GSP**, тому «only Turing and newer GPUs will support Vulkan Video support on NVK». [S12] Додатково потрібен патч Nouveau, що з'явився в Linux 7.3 (Phoronix, 2026-07-31; патч Dave Airlie, надісланий Daniel Almeida 2026-07-25). [S11] Функція в 26.3 позначена як експериментальна і вмикається `NVK_EXPERIMENTAL=video`. [S28] H.265 ще не готовий (наразі «wedges the GSP»). [S12]

Формулювання для матриці: *апаратний декодер GP107 фізично існує (NVIDIA документує NVDEC для Pascal: H.264, HEVC Main/Main10, VP8, VP9), але жоден компонент відкритого стеку не виставляє його для Pascal.* [S29] Це два різні факти, і плутати їх не можна.

### 4.2. NVENC — кодування

**NOT_AVAILABLE.** У FeatureMatrix немає рядка про кодування взагалі. [S7] Єдина відеофункція, додана у відкритий стек у 2026 році, — **декодування** H.264 у NVK (і те лише Turing+). [S12] Твердження «NVENC працює через відкритий стек на Pascal» не підкріплене жодним джерелом; писати його не можна. Кодування на GP107 доступне лише через пропрієтарний драйвер (смуга B), і це не є можливістю смуги A.

---

## 5. Обчислення

### 5.1. Vulkan compute на NVK

**PASS.** Конформантність Vulkan (1.3 за реєстром Khronos [S4], 1.4 за документацією Mesa [S2]) покриває й обчислювальні пайплайни; окремих обмежень для Pascal у джерелах не зафіксовано. Межа тут не функціональна, а швидкісна: частоти — boot clocks. [S1],[S8]

Окремо: розширення на кшталт `VK_KHR_cooperative_matrix` (матричні операції) у джерелах 2025–2026 описуються для сучасніших поколінь; **твердження про їхню наявність на Pascal немає** — для матриці це `UNKNOWN`, а не «є».

### 5.2. OpenCL через Rusticl

**PARTIAL.** Phoronix (2025-12-11) у тесті відкритого стеку проти NVIDIA 580 фіксує: «The Rusticl Gallium3D driver does provide OpenCL 3.0 support for NVIDIA GPUs on Nouveau», при цьому «the Maxwell and Pascal support struggles due to the lack of re-clocking support on Nouveau». [S8] CUDA через відкритий стек недоступний узагалі. [S8]

Обмеження, які треба врахувати в матриці:

- Rusticl **не** виставляє пристрої за замовчуванням: потрібен `RUSTICL_ENABLE` (документація Mesa, перевірено 2026-11-28). [S13] Дистрибутив може змінити це опцією збірки `gallium-rusticl-enable-drivers`. [S13]
- OpenCL **3.1** у Mesa 26.2 перелічено для rusticl на asahi, iris, radeonsi, llvmpipe і zink — **nouveau у переліку немає**. [S14] Тобто для Pascal через nvc0 очікуваний рівень — 3.0, а не 3.1; фактичний `CL_DEVICE_VERSION` треба зчитувати з `clinfo`, а не припускати.
- Rusticl через `zink`/NVK на Pascal — окремий шлях, для якого датованого підтвердження саме для Pascal немає → `UNKNOWN`.

---

## 6. Що змінилося у 2026 році (важливе для Guix-снепшоту 2026)

1. **Лінійка Mesa.** 2026-02-11 — Mesa 26.0.0; 2026-05-06 — 26.1.0; 2026-08-05 — 26.2.0; 2026-11-09 — 26.3.0 (анонс 2026-11-12). [S19],[S20],[S14],[S21] У Guix станом на 2026-11-28 — **mesa 26.2.6** (Repology, перевірено 2026-11-28). [S30] Для Pascal це не проблема: усе, що стосується GP107, уже є в 26.2; єдина велика відеоновинка 26.3 (Vulkan Video в NVK) Pascal не стосується взагалі. [S12]
2. **Регресія atomic modesetting на NV50+** (коміт `2652aca460dc…`): звіт по GP107 від 2026-11-02, патч 2026-11-11, фікс `ed7fb901fce3` у mainline з 2026-11-25. [S9a],[S9b],[S9c] Це головний ризик «оновімось на свіже ядро» у 2026 році.
3. **Vulkan Video в NVK** (Mesa 26.3) + патч NVDEC-каналів у Nouveau для Linux 7.3 — функція є, але тільки для Turing+ через залежність від GSP. [S11],[S12] Для проєкту це означає: не планувати відеосмугу на GP107 у смузі A.
4. **NVIDIA 590 прибрав Pascal.** Серія NVIDIA 590 виводить Maxwell і Pascal з основної гілки; 580 — остання, що їх підтримує. [S8],[S15] Відповідно, будь-яка смуга B (спостереження за пропрієтарним стеком) на GP107 у 2026 році фіксується на 580.
5. **Пакування прошивок.** Ubuntu розділила `linux-firmware` на пакети за вендорами: завантаження `linux-firmware-nvidia-graphics` зі сплітом — 2026-01-23, опис пакета прямо каже «This package provides firmware used by Linux kernel drivers nouveau» [S31]; у вересні 2026 спліт дійшов і до 24.04 (повідомлення від 2026-09-09) [S32]. Arch має `linux-firmware-nvidia 20261124-1` (збірка 2026-11-25). [S33] У Guix головний канал не містить цих блобів: `linux-firmware` приходить із каналу **nonguix**, де він оновлений до 20261124, і саме там сказано, що для вільного драйвера nouveau треба налаштувати `linux-firmware`. [S34] Це критично: **на Pascal nouveau потребує підписаних блобів NVIDIA** (ACR/FECS/GPCCS через `linux-firmware`), тобто «вільний» стек на GP107 без цих файлів не дасть апаратного 3D. [S1],[S34]
6. **Ядро в Guix — і виправлення до попередньої редакції цього пункту.** Реліз Guix 1.5.0 (2026-01-23) постачався з Linux 6.17.12 [S35], і саме на цій підставі тут раніше стояло, що «Guix-снепшот 2026 року нижчий за вікно регресії atomic». **Для WSM це неправильно.** `wsm-desktop/drivers/profiles/h170-free.json` фіксує не реліз 1.5.0, а коміт `4e5195be` (2026-11-25), який вибирає **linux-libre 7.3.5** — тобто рівно всередині вікна 7.3.x, де зарепортовано NULL deref на GP107.

   **Перевірено далі — і відповідь негативна.** Linux 7.3.5 вийшов **2026-11-17** (анонс Greg Kroah-Hartman) [S36], а фікс `ed7fb901fce3` увійшов у mainline **2026-11-25** [S9c]. Stable-гілка не може містити коміт, якого ще немає в mainline, тож **linux-libre 7.3.5 фіксу не має**. 7.3.6 (2026-11-23) теж передує йому [S37]. Тобто пін `4e5195be` дає ядро **з регресією і без виправлення**.

   Наслідок для релізу: або пін на ядро, у якому фікс уже є (перша stable-версія після 2026-11-25), або `nouveau.atomic=0` у параметрах завантаження як задокументований обхід, або явна примітка в релізі, що дисплей на GP107 у цьому вікні не гарантований. Мовчазний третій варіант — не варіант: збій виглядатиме як апаратна несправність.
7. **Смуга C.** У 2026 році з'явилося більше публічних матеріалів про внутрішню будову відеоенгейнів NVIDIA (зокрема робота Daniel Almeida, що спиралася на реверс-інжиніринг для H.264 у NVK). [S12] Це факт про походження коду, а не рекомендація щодо статичного аналізу — див. нижче.

### Поза межами звіту

Статичний аналіз пропрієтарних бінарників (смуга C) тут не розглядається і не рекомендується: ця смуга відкривається лише за письмовим дозволом правовласника. Усе вище — про смуги A і B.

---

## 7. Що це змінює для проєкту

### 7.1. Для бенчмарк-матриці

1. **Розділити вісь «функціональна коректність» і вісь «продуктивність».** Для GP107 вони майже не корелюють: Vulkan-конформанс є [S1],[S4], а частоти — boot clocks [S1],[S8]. Одна таблиця зі змішаними оцінками дасть хибний висновок «драйвер поганий», хоча драйвер коректний.
2. **Жодного рядка «parity з пропрієтарним драйвером».** Це не «поганий результат», це `N/A`: без reclocking порівняння вимірює різницю частот, а не різницю реалізацій. [S1],[S8]
3. **Клітинки, які треба заповнювати `N/A`, а не «FAIL»:** reclocking, power/thermal, boost-поведінка, сталі частоти під навантаженням, NVENC, NVDEC (будь-який шлях), CUDA.
4. **Клітинка конформансу — дві, не одна:** «заявлено Mesa (1.4)» [S2] і «зареєстровано Khronos (1.3, CTS 1.4.1.2, 2025-04-18)» [S4]. Розбіжність — це дані, а не шум.
5. **Клітинка OpenGL — дві конфігурації:** типова (яка б вона не була — `UNKNOWN` [S17],[S18]) і примусово Zink (`NOUVEAU_USE_ZINK=1` [S5]). Інакше результат буде невідтворюваним між машинами з різними Mesa.
6. **Кожна клітинка мусить нести трійку версій: ядро / Mesa / снапшот linux-firmware.** У 2026 році це не формальність: регресія atomic залежить від ядра [S9a]–[S9c], набір доступних розширень — від Mesa [S19]–[S21], а наявність блобів — від пакування [S31]–[S34].
7. **Для OpenCL зчитувати фактичний рівень** (`clinfo` → `CL_DEVICE_VERSION`) замість очікуваного: 3.0 підтверджено для nouveau [S8], 3.1 — ні [S14].
8. **Окремий рядок «display init на 7.3.x»** зі значенням `nouveau.atomic=0` як задокументованим обхідним шляхом [S9a]–[S9c] — інакше частина прогонів просто не стартує, і це виглядатиме як апаратна несправність.

### 7.2. Для розділення релізів Free / Compatibility

Ключовий висновок: **на GP107 «повністю вільний» реліз із апаратним 3D неможливий.** Nouveau на Pascal потребує підписаних блобів NVIDIA з `linux-firmware` [S1],[S34]; у Guix вони живуть лише в каналі nonguix [S34]. Це треба вирішити явно, а не замовчати.

- **Free-реліз.** Або (а) без блобів — і тоді GP107 працює на llvmpipe/софтверному рендерингу, а всі клітинки апаратного прискорення стають `N/A`; або (б) з явною декларацією firmware-винятку (`linux-firmware` з nonguix, снапшот 20261124 [S34]). Мовчазний варіант «(б) без згадки» — це некоректний Free-реліз.
- **Free-реліз не повинен містити `nvda-580`** — інакше смуги A і B змішуються, і результати вимірювань стають непорівнюваними.
- **Compatibility-реліз.** Фіксує: пропрієтарний драйвер **580** (остання гілка з Pascal; 590 і далі Pascal не підтримують [S8],[S15]), nonguix-профіль із підтримкою Pascal (у nonguix Pascal є і в колонці Nouveau, і в колонці nvda-580 [S34]), і окремо — політику ядра.
- **Політика ядра в обох релізах.** Мінімум — Linux ≥ 6.6 для NVK [S2]. Вікно регресії atomic (7.3.x) — не абстракція: пін `4e5195be` у `h170-free.json` дає linux-libre **7.3.5**, тобто всередині вікна, і без перевірки наявності фіксу `ed7fb901fce3` у цій stable-гілці. Тому «пити ядро» — не аргумент саме по собі: пін або нижче вікна, або з `nouveau.atomic=0`, або з явною приміткою про обмеження.
- **Політика Mesa.** 26.2.x (у Guix — 26.2.6 [S30]) достатньо для всього, що стосується GP107; гнатися за 26.3 немає сенсу, бо єдина велика новинка — Vulkan Video — Pascal не стосується [S12]. Це зменшує поверхню ризику в Compatibility-релізі.
- **Політика прошивок у власному образі.** Пакування `linux-firmware` розділене (Ubuntu — з 2026-01-23 [S31],[S32]; Arch — `linux-firmware-nvidia` [S33]), тому треба явно перевіряти наявність файлів `nvidia/gp107/*` у `/lib/firmware`, а не покладатися на «пакет linux-firmware стоїть».

### 7.3. Для смуги B (спостереження за пропрієтарним стеком)

Фіксація на 580 — не тимчасова незручність, а межа: наступні гілки Pascal не підтримують. [S8],[S15] Отже будь-який протокол спостереження, що прив'язаний до версії драйвера, треба заморозити разом із 580, інакше він «зламається» не через помилку, а через відсутність підтримки.

---

## 8. Прогалини у доказах (свідомо залишені)

| Питання | Чому `UNKNOWN` | Що шукалося |
|---|---|---|
| Чи є Zink типовим OpenGL для Pascal у Mesa 26.x | Немає жодного джерела 2026 року; останні твердження (08.2025, 10.2025, 12.2025) кажуть «pre-Turing — старий драйвер», «Kepler through Volta will come later» [S16],[S6],[S18] | Release notes Mesa 26.0/26.1/26.2/26.3 [S19],[S20],[S14],[S21]; Phoronix і Collabora за 2026; запити про «pre-Turing Zink default» |
| Suspend/resume (S3) на GP107 у 2026 | Знайдені матеріали 2026 року стосуються GSP (Turing+) [S27] | «nouveau suspend resume Pascal GP107», «nouveau fbsr non-GSP suspend», списки nouveau за 2026 |
| OpenCL 3.1 на Pascal через Rusticl | У переліку 3.1 немає nouveau [S14] | Mesa 26.2.0/26.3.0 release notes; XDC 2026 rusticl update (перелічує лише panfrost/freedreno як нові default-драйвери) [S36] |
| Стиснення (DCC) у NVK на Pascal | На XDC 2026 описано як незавершене загалом, без прив'язки до Pascal [S23] | XDC 2026 «NVK in 2026» [S23]; release notes 26.1.7 (компресія згадана для Turing) [S22] |
| Vulkan compute-розширення (cooperative matrix тощо) на Pascal | Джерела описують їх для новіших поколінь, без Pascal | XDC 2025/2026 слайди [S6],[S23] |

---

## 9. Джерела

| ID | Джерело | Дата | URL |
|---|---|---|---|
| S1 | Faith Ekstrand, Collabora — «NVK enabled for Maxwell, Pascal, and Volta GPUs» | 2025-04-22 | https://www.collabora.com/news-and-blog/news-and-events/nvk-enabled-for-maxwell,-pascal,-and-volta-gpus.html |
| S2 | Mesa documentation — «NVK» (без дати публікації; перевірено 2026-11-28) | — | https://docs.mesa3d.org/drivers/nvk.html |
| S3 | Phoronix — «Mesa 25.1-rc2 Released With NVK Vulkan 1.4 Conformance For Older NVIDIA GPUs» | 2025-04-23 | https://www.phoronix.com/news/Mesa-25.1-rc2-Released |
| S4 | Khronos Group — реєстр конформантних продуктів Vulkan; запис Software Freedom Conservancy, Vulkan_1_3 №908, CTS 1.4.1.2 (перевірено 2026-11-28) | 2025-04-18 | https://www.khronos.org/conformance/adopters/conformant-products/vulkan |
| S5 | Phoronix — «Open-Source NVIDIA Driver Moving To NVK + Zink For OpenGL On Newer GPUs» (`NOUVEAU_USE_ZINK=1`) | 2024-02-21 | https://www.phoronix.com/news/Zink-NVK-For-NVIDIA-OpenGL |
| S6 | Faith Ekstrand, XDC 2025 — «Nouveau/NVK Update» (слайди) | 2025-09-29 / 2025-10-01 | https://indico.freedesktop.org/event/10/contributions/401/attachments/264/352/2025-09-29%20-%20XDC%202025%20-%20Nouveau%20NVK%20Update.pdf |
| S7 | nouveau.freedesktop.org — FeatureMatrix (без дати; «updated rarely»; перевірено 2026-11-28) | — | https://nouveau.freedesktop.org/FeatureMatrix.html |
| S8 | Phoronix — «NVIDIA GTX 980 Through RTX 5080: Open-Source Nouveau/Mesa Drivers vs. NVIDIA 580 Linux Drivers» | 2025-12-11 | https://www.phoronix.com/review/nvidia-980-5080-linux |
| S9a | Список nouveau — звіт Eric Kim «[REGRESSION] drm/nouveau: NULL pointer dereference in drm_atomic_commit during GP107 initialization», `#regzbot introduced: 2652aca460dc` | 2026-11-02 | https://lists.freedesktop.org/hyperkitty/list/nouveau@lists.freedesktop.org/message/UFUKGEC6WNJGZJMBOWBL2GPTFDP6AHTF/ |
| S9b | lore.freedesktop.org — «[PATCH] drm/nouveau/disp: Set drm_mode_config_funcs.atomic_(check\|commit) (attempt 2)», Dave Airlie | 2026-11-11 | https://lore.freedesktop.org/nouveau/20261111-nouveau-atomic-fix-v1-1-118e65d3a2f5@redhat.com/T/ |
| S9c | Список linux-kernel — звіт закрито, фікс `ed7fb901fce31588bd12ab95adc36ebcb51bc8ea` у mainline | 2026-11-25 | https://lists.openwall.net/linux-kernel/2026/11/25/765 |
| S36 | Список linux-kernel — анонс «Linux 7.3.5» (Greg Kroah-Hartman) | 2026-11-17 | https://lists.openwall.net/linux-kernel/2026/11/17/1538 |
| S37 | kernel.org — індекс `pub/linux/kernel/v7.x/`: ChangeLog-7.3.5 (17.11.2026), ChangeLog-7.3.6 (23.11.2026) | 2026-11-23 | https://www.kernel.org/pub/linux/kernel/v7.x/ |
| S38 | Список nouveau — Bruno Prémont, «NV04, 6.18.8 crashes on NULL pointer dereference», бісекція до `448a2071a843` | 2026-02-01 | https://lore.freedesktop.org/nouveau/20260201231451.1ef0128c@hemera.lan.sysophe.eu/ |
| S10 | nouveau.freedesktop.org — PowerManagement (без дати; перевірено 2026-11-28) | — | https://nouveau.freedesktop.org/PowerManagement.html |
| S11 | Phoronix — «Nouveau Patch For Linux 7.3 Allows For NVK Vulkan Video Atop NVIDIA NVDEC» | 2026-07-31 | https://www.phoronix.com/news/Linux-7.3-Nouveau-NVDEC |
| S12 | Phoronix — «NVK Vulkan Video Merged For Mesa 26.3» | 2026-08-22 | https://www.phoronix.com/news/NVK-Vulkan-Video-Mesa-26.3 |
| S13 | Mesa documentation — «Rusticl» (без дати; перевірено 2026-11-28) | — | https://docs.mesa3d.org/rusticl |
| S14 | Mesa 26.2.0 Release Notes | 2026-08-05 | https://docs.mesa3d.org/relnotes/26.2.0.html |
| S15 | Phoronix — «Nova Driver Progress & Other NVIDIA Linux News From 2025» (підтвердження, що 580 — остання гілка для Maxwell/Pascal/Volta) | 2025-12-26 | https://www.phoronix.com/news/NVIDIA-Linux-2025-Highlights |
| S16 | [ANNOUNCE] mesa 25.2.0 (Eric Engestrom) | 2025-08-06 | https://lists.freedesktop.org/archives/mesa-announce/2025-August/000815.html |
| S17 | Faith Ekstrand, Collabora — «Mesa 25.2 brings new hardware support for Nouveau users» | 2025-08-04 | https://www.collabora.com/news-and-blog/news-and-events/mesa-25.2-brings-new-hardware-support-for-nouveau-users.html |
| S18 | [ANNOUNCE] mesa 25.3.1 (містить записи 25.3.0; вилучення VDPAU; межа Turing+ для старого драйвера) | 2025-12-04 | https://lists.freedesktop.org/archives/mesa-announce/2025-December/000829.html |
| S19 | Mesa 26.0.0 Release Notes | 2026-02-11 | https://docs.mesa3d.org/relnotes/26.0.0.html |
| S20 | Mesa 26.1.0 Release Notes | 2026-05-06 | https://docs.mesa3d.org/relnotes/26.1.0.html |
| S21 | Mesa 26.3.0 Release Notes | 2026-11-09 | https://docs.mesa3d.org/relnotes/26.3.0.html |
| S22 | Mesa 26.1.5 Release Notes («nvk: Handle large indirect stride pre-Turing»; «nvk: Reenable compression support on Turing») | 2026-07-15 | https://docs.mesa3d.org/relnotes/26.1.5.html |
| S23 | Mel Henning, XDC 2026 — «NVK in 2026» (слайди) | 2026-09-30 | https://indico.freedesktop.org/event/12/contributions/531/attachments/387/554/nvk_in_2026.pdf |
| S24 | Phoronix — «Nouveau Driver Receives Patch For GPU Reclocking With The Pascal GP10B» | 2025-08-23 | https://www.phoronix.com/news/Nouveau-GP10B-Reclocking |
| S25 | NVIDIA Developer Forums — «Request for a signed GP107 firmware enabling open reclocking» | 2026-10-10 | https://forums.developer.nvidia.com/t/request-for-a-signed-gp107-firmware-enabling-open-reclocking/385520 |
| S26 | Phoronix — «Nouveau-DKMS Aims For Better NVIDIA Open-Source Experience On Old GPUs» | 2026-10-26 | https://www.phoronix.com/news/Nouveau-DKMS |
| S27 | Dave Airlie — «nouveau: a tale of two bugs» (suspend/resume на GSP-прошивці R570) | 2026-02-04 | https://airlied.blogspot.com/2026/02/nouveau-tale-of-two-bugs.html |
| S28 | TechGefrickel — «Mesa 26.3: Anti-Lag für RADV, Jay-Compiler für Intel» (H.264 у NVK за `NVK_EXPERIMENTAL=video`, Turing+) | 2026-11-16 | https://techgefrickel.com/artikel/mesa-263-anti-lag-fuer-radv-intel-stellt-auf-den-jay-compiler-um |
| S29 | NVIDIA — NVDEC Application Note (можливості NVDEC для Pascal) | 2026 (версія 13.0; перевірено 2026-11-28) | https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/nvdec-application-note/index.html |
| S30 | Repology — версії пакета mesa; GNU Guix = 26.2.6 (перевірено 2026-11-28) | — | https://repology.org/project/mesa/versions |
| S31 | Ubuntu Launchpad — `linux-firmware-nvidia-graphics` 20260123.git1b7b9f6c-0ubuntu1 («firmware used by Linux kernel drivers nouveau»; спліт пакета) | 2026-01-23 | https://launchpad.net/ubuntu/+source/linux-firmware-nvidia-graphics/20260123.git1b7b9f6c-0ubuntu1 |
| S32 | Ubuntu Discourse — «Linux firmware split in Noble and Resolute» | 2026-09-09 | https://discourse.ubuntu.com/t/linux-firmware-split-in-noble-and-resolute/87528 |
| S33 | Arch Linux — `linux-firmware-nvidia 20261124-1` | 2026-11-25 (збірка) | https://archlinux.org/packages/core/any/linux-firmware-nvidia/ |
| S34 | Nonguix (канал Guix) — README: firmware/`linux-firmware` для nouveau, таблиця підтримки Pascal; `linux-firmware` оновлено до 20261124 (перевірено 2026-11-28) | 2026-11-24 | https://gitlab.com/nonguix/nonguix |
| S35 | DistroWatch — Guix System 1.5.0 (реліз 2026-01-23, linux 6.17.12) | 2026-01-23 | https://distrowatch.com/table.php?distribution=guixsd |
| S36 | Karol Herbst, XDC 2026 — «rusticl status update» (слайди) | 2026-09-28 | https://indico.freedesktop.org/event/12/contributions/554/attachments/358/517/rusticl.html |
