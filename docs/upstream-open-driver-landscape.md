# Відкритий графічний стек для GP107 / GeForce GTX 1050 Ti

> Дата перевірки джерел: 27 листопада 2026 року. Це карта екосистеми та план перевірок, а не специфікація драйвера і не доказ того, що кожна функція працює на конкретній платі.

## 1. Ідентифікація цілі

| Поле | Значення |
|---|---|
| GPU | NVIDIA GP107 |
| Модель | GeForce GTX 1050 Ti |
| PCI vendor/device | 10de:1c82 |
| Архітектура | Pascal |
| Compute capability | SM 6.1 (значення з поточного дослідницького профілю репозиторію) |
| Ціль Linux-стека | upstream nouveau + Mesa |
| Vulkan userspace | Mesa NVK |
| Референсний закритий стек у цьому репо | NVIDIA R580.196.11 |

Envytools прямо зіставляє PCI ID 0x1c82 з GP107 / GeForce GTX 1050 Ti. У дереві Linux є окрема реалізація GR engine для GP107 (gp107.c) і контекстний код (ctxgp107.c). NVIDIA open-gpu-doc має класи Pascal, у списку GPU яких є GP107.

## 2. Висновок

Для GTX 1050 Ti є робочий відкритий напрямок, але це **не NVIDIA Open GPU Kernel Modules**.

Рекомендований відкритий стек:

1. Linux kernel DRM-драйвер nouveau для PCI/KMS, пам'яті, GPU virtual memory і подання команд.
2. Mesa Nouveau Gallium для OpenGL на старих поколіннях.
3. Mesa NVK для Vulkan; актуальна документація Mesa включає Kepler і новіші GPU та вимагає Linux 6.6+.
4. linux-firmware для потрібних GP107 firmware blobs, де їх вимагає конкретний шлях ініціалізації.

**Не плутати три різні речі:**

- NVIDIA open-gpu-kernel-modules — відкритий варіант саме NVIDIA kernel driver, але офіційно лише для Turing і новіших GPU.
- Nouveau/NVK — незалежний відкритий стек Linux + Mesa, який підтримує Pascal.
- Цей репозиторій — clean-room дослідження ioctl/RM ABI закритого NVIDIA R580-драйвера. Він поки не є Nouveau-драйвером і не реалізує незалежне керування GPU.

## 3. Що вже існує upstream

### Linux: Nouveau / NVKM

Nouveau — DRM kernel driver. Його внутрішній NVKM шар містить апаратні підсистеми і керує ресурсами, пам'яттю, живленням та поданням команд. У kernel tree є, зокрема:

- [GP107 GR engine](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/nouveau/nvkm/engine/gr/gp107.c)
- [GP107 GR context](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/nouveau/nvkm/engine/gr/ctxgp107.c)
- [Nouveau kernel documentation](https://github.com/torvalds/linux/blob/master/Documentation/gpu/nouveau.rst)
- [Nouveau Kbuild: memory, VMM, exec, scheduler, channel and DMA components](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/nouveau/Kbuild)

Це означає, що для GP107 уже існує значний upstream-код. Не потрібно починати з нульового PCI driver або самостійно винаходити весь memory manager / command submission stack. Найкращий внесок для власного дослідження — спочатку відтворювати і перевіряти поведінку upstream Nouveau, а потім виправляти конкретні GP107 дефекти або додавати вимірювані свідки.

### Mesa: OpenGL і Vulkan

Офіційна сторінка Nouveau заявляє OpenGL для підтримуваних Nouveau GPU та Vulkan для Kepler і новіших поколінь. Актуальна документація Mesa для NVK включає Kepler і новіші покоління до Ada та consumer Blackwell; для NVK потрібне ядро Linux не старіше 6.6.

Для GP107 це дає таке розділення:

- **OpenGL:** використовувати Nouveau Gallium path для старих поколінь.
- **Vulkan:** використовувати NVK. У документації NVK backend shader compiler має діагностичні прапорці NAK_DEBUG.
- Не переносити на Pascal твердження про NVK+Zink як стандартний OpenGL path: документація Mesa окремо вказує, що цей default почався з Turing+ у Mesa 25.1.

Офіційні джерела: [Nouveau status](https://nouveau.freedesktop.org/), [Mesa NVK](https://docs.mesa3d.org/drivers/nvk.html).

### NVIDIA Open GPU documentation

NVIDIA публікує Pascal 3D class headers:

- PASCAL_A — clc097.h, GPU list включає GP107.
- PASCAL_B — clc197.h, GPU list також включає GP107.

Це цінний публічний опис класів/методів для перевірки командного інтерфейсу, але не повний опис MMIO, firmware чи всіх внутрішніх блоків GPU.

Джерела: [3D class index](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/3d/README.txt), [NVIDIA open-gpu-doc](https://github.com/NVIDIA/open-gpu-doc).

### Envytools

[envytools](https://github.com/envytools/envytools) — незалежний набір інструментів реверс-інжинірингу NVIDIA:

- envydis — дизасемблер/асемблер GPU ISA.
- rnndb / rnn — база MMIO-регістрів, FIFO methods та структур пам'яті.
- nvbios — декодування структур VBIOS.
- nva — низькорівневий інструмент доступу до регістрів.

Його PCI ID database підтверджує 1c82 = GP107 [GeForce GTX 1050 Ti]. Це джерело для перехресної перевірки назв і структур, а не привід виконувати небезпечні register writes. Під час першого етапу використовувати лише статичне декодування VBIOS та безпечні read-only функції.

## 4. Чому Open GPU Kernel Modules не підходять

NVIDIA вказує сумісність відкритих kernel modules лише з Turing і новішими GPU. Відкриті модулі залежать від GPU System Processor (GSP), який з'явився в Turing. Для Maxwell, Pascal і Volta NVIDIA вимагає proprietary kernel-module flavor.

Отже:

- не намагатися зібрати NVIDIA/open-gpu-kernel-modules для GP107 як заміну Nouveau;
- не переносити GSP-specific код із Turing+ на Pascal;
- використовувати документацію відкритих модулів лише там, де вона описує спільні зовнішні interfaces, а не як implementation target для GP107.

Джерела: [NVIDIA open kernel modules README](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/main/README.md), [NVIDIA kernel modules guide](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/kernel-modules.html), [open-module limitations](https://download.nvidia.com/XFree86/Linux-x86_64/580.95.05/README/kernel_open.html).

## 5. Firmware: доступна, але не відкрита

Пакети linux-firmware містять окремі GP107 blobs. Серед опублікованих шляхів:

- nvidia/gp107/gr/fecs_*.bin
- nvidia/gp107/gr/gpccs_*.bin
- nvidia/gp107/gr/sw_ctx.bin
- nvidia/gp107/gr/sw_nonctx.bin
- nvidia/gp107/sec2/{desc,image,sig}*.bin
- nvidia/gp107/nvdec/scrubber.bin

У gp107.c Linux Nouveau ці GR firmware paths оголошені через MODULE_FIRMWARE; init path посилається на GR/ACR firmware handlers. Пакетне розповсюдження дозволяє драйверу завантажити потрібні blobs, але не означає, що firmware source code відкритий або що її можна модифікувати/перепідписати.

Для нашого дослідження: фіксувати, які саме файли завантажено, їхню версію/хеш і повідомлення kernel log. Не копіювати firmware blobs до цього репозиторію без окремої перевірки ліцензій; достатньо посилань на пакет і контрольних сум у локальному лабораторному журналі.

Джерела: [Arch linux-firmware-nvidia file list](https://archlinux.org/packages/core/any/linux-firmware-nvidia/files/), [Ubuntu linux-firmware file list](https://packages.ubuntu.com/noble/ppc64el/linux-firmware/filelist), [upstream GP107 GR source](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/nouveau/nvkm/engine/gr/gp107.c).

## 6. Головне апаратне обмеження: reclocking

Сторінка Nouveau повідомляє:

- automatic reclocking підтримується для Turing і новіших GPU через GSP firmware;
- ручний вибір performance level доступний для GM10x Maxwell, Kepler та деяких старіших GPU;
- для GM20x, GP10x і GV100 перспективи reclocking обмежені необхідністю firmware, підписаного NVIDIA.

GP107 є GP10x. Отже, не планувати керування P-state/частотами як гарантовану функцію відкритого стека. Спочатку спостерігати за фактичним станом; не пробувати примусове перепрограмування частот або firmware. Це обмеження не дорівнює відсутності OpenGL/Vulkan acceleration.

Джерело: [Nouveau current status](https://nouveau.freedesktop.org/).

## 7. Актуальність proprietary fallback

R580 — остання Linux driver series NVIDIA з підтримкою Maxwell, Pascal і Volta. Для GeForce на цих архітектурах NVIDIA припинила звичайні Game Ready оновлення у жовтні 2025 року; critical security updates заявлені до жовтня 2028 року.

Це корисний тимчасовий fallback і контрольна база для порівнянь, але не стратегія довгострокового відкритого драйвера.

Джерела: [NVIDIA Unix legacy support timeframe](https://nvidia.custhelp.com/app/answers/detail/a_id/3142), [GeForce Maxwell/Pascal/Volta support plan](https://nvidia.custhelp.com/app/answers/detail/a_id/5676).

## 8. WSL2 не є тестовим середовищем Nouveau

Для WSL2 NVIDIA документує Windows host GPU driver як єдиний потрібний driver layer і прямо забороняє встановлювати Linux display driver усередині WSL. Гостьова Linux-система користується GPU через WSL virtualization interface, а не через звичайний Linux bare-metal PCI/Nouveau path.

Отже:

- WSL можна використовувати для редагування коду, збірки userspace tools і статичного аналізу;
- WSL не можна вважати доказом, що Nouveau/NVK працює безпосередньо з GTX 1050 Ti;
- апаратний bring-up виконувати в нативній Linux-сесії на фізичному комп'ютері (або в окремому середовищі з реальним PCI passthrough, якщо воно справді надає пристрою прямий доступ).

Джерела: [NVIDIA CUDA on WSL guide](https://docs.nvidia.com/cuda/wsl-user-guide/), [Ubuntu WSL GPU guide](https://ubuntu.com/wsl/docs/stable/howto/gpu-cuda/), [Microsoft GPU paravirtualization](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/gpu-paravirtualization).

## 9. Що перевіряти на фізичному GP107

Перший етап — лише інвентаризація і read-only свідки. Не починати з MMIO writes, змін firmware або розгону.

### Ідентифікація і прив'язка драйвера

~~~bash
lspci -nnk -s 01:00.0
modinfo nouveau
lsmod | grep -E 'nouveau|nvidia'
~~~

Зафіксувати PCI BDF, vendor/device, subsystem IDs, kernel driver in use, версію ядра та пакет Mesa.

### Firmware і ініціалізація

~~~bash
sudo dmesg -T | grep -Ei 'nouveau|nvidia|firmware|fifo|gr|sec2|nvdec'
find /lib/firmware/nvidia/gp107 -type f -print 2>/dev/null | sort
~~~

Фіксувати missing firmware, помилки engine init, VBIOS parse і причину fallback. Наявність файлу в каталозі не є доказом, що kernel його успішно завантажив.

### Графічний стек

~~~bash
glxinfo -B
vulkaninfo --summary
~~~

Окремо перевірити KMS/display, OpenGL renderer, Vulkan physical device/API version, простий Vulkan workload і стабільність після suspend/resume. Усі результати записувати разом з точними kernel/Mesa/firmware versions.

### P-state / температури

Спочатку лише читати доступну діагностику, наприклад /sys/kernel/debug/dri/0/pstate, якщо debugfs і цей вузол існують. Не записувати значення в sysfs/debugfs. Не трактувати відсутність вузла як несправність GPU.

## 10. Черговість робіт

| Етап | Результат | Критерій завершення |
|---|---|---|
| A. Bare-metal baseline | Повний опис карти та зв'язки з nouveau | PCI identity, kernel/Mesa, firmware log, KMS/OpenGL/Vulkan збережені |
| B. Feature matrix | Працюючі/непрацюючі функції саме цієї плати | Кожна функція має команду, версії, log і стан доказу |
| C. Upstream gap analysis | Конкретні GP107 дефекти або відсутні функції | Мінімальний відтворюваний тест і відповідний upstream path |
| D. Внесок у Nouveau/Mesa | Патчі до upstream або окремий тестовий MR | CI + hardware witness; не лише статичний перегляд |
| E. Незалежний драйверний експеримент | Лише вузький модуль/підсистема, якщо upstream шлях не покриває мету | Окремий дизайн, ізоляція, fail-closed init, перевірка на фізичній карті |

Пріоритет — не писати новий повний драйвер паралельно Nouveau. Спочатку отримати на GP107 відтворюваний baseline і знайти конкретну прогалину upstream. Mesa NVK уже дозволяє не писати власний shader compiler, якщо мета — kernel/driver bring-up.

## 11. Межа з поточним дослідженням RM ABI

Поточні FPC probes цього репозиторію спілкуються з вузлами NVIDIA proprietary driver (/dev/nvidiactl, /dev/nvidiaN) і досліджують vendor Resource Manager ABI. Це корисна референсна база, але вона не є інтерфейсом Nouveau.

Поточний доказ RM arch-info на R580 (arch=0x130, impl=0x07, rev=0xa1, subrev=0x02) не доводить прямого читання регістра NV_PMC_BOOT_0. BOOT0 залишається UNPROVEN. BAR0 probe залишається read-only і fail-closed. Не послаблювати ці обмеження заради отримання «зеленого» результату.

Не переносити висновки з цього протоколу до wsm-os-lisp target ABI без окремого owner-рішення та contract review.

## 12. Первинні джерела

1. [Nouveau project status](https://nouveau.freedesktop.org/) — апаратне покриття, Vulkan/OpenGL, reclocking.
2. [Mesa NVK documentation](https://docs.mesa3d.org/drivers/nvk.html) — підтримувані GPU та мінімальне ядро.
3. [Linux GP107 GR implementation](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/nouveau/nvkm/engine/gr/gp107.c) — GP107 engine and firmware interface.
4. [Linux GP107 context implementation](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/nouveau/nvkm/engine/gr/ctxgp107.c).
5. [Linux Nouveau Kbuild](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/nouveau/Kbuild) — memory/VM/exec/scheduler/command-submission implementation.
6. [NVIDIA Open GPU Documentation](https://github.com/NVIDIA/open-gpu-doc) — публічні hardware class headers.
7. [Pascal 3D classes](https://github.com/NVIDIA/open-gpu-doc/blob/master/classes/3d/README.txt) — GP107 у PASCAL_A/PASCAL_B.
8. [Envytools PCI ID database](https://github.com/envytools/envytools/blob/master/docs/hw/pciid.rst) — 1c82 = GTX 1050 Ti.
9. [Envytools project](https://github.com/envytools/envytools) — disassembly, RNND database, VBIOS tooling.
10. [NVIDIA open kernel module README](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/main/README.md) — Turing+ restriction.
11. [NVIDIA WSL guide](https://docs.nvidia.com/cuda/wsl-user-guide/) — Windows host driver only; no Linux display driver inside WSL.
12. [GP107 firmware package inventory](https://archlinux.org/packages/core/any/linux-firmware-nvidia/files/) — набір firmware paths у Linux distribution.

---
*Цей документ фіксує стан джерел на 2026-11-27. Перед кожною реалізацією перевіряти актуальні upstream revisions; це не постійно оновлюваний API-контракт.*
