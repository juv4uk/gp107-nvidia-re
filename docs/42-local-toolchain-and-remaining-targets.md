# 42 — Локальний toolchain, залишкові цілі RE і те, що впирається в ліцензійний gate

Цей документ відповідає на два питання, які виникають щоразу перед новою сесією
дослідження:

1. **Що саме ще треба зʼясувати** для `10de:1c82` (GTX 1050 Ti, GP107) — і в
   якому порядку.
2. **Якими інструментами** це робити локально, щоб не перетворити кожен крок на
   новий набір здогадів.

Він не додає нових доказів і не змінює жодного статусу в інших документах.
Статуси лишаються там, де їх зафіксовано: [`05`](05-gp107-capability-matrix.md),
[`07`](07-next-research-direction.md), [`40`](40-rea-p1-gpu-info-uuid-direction.md),
[`41`](41-rea-p1-libcuda-userspace-uuid-source.md).

---

## 1. Три смуги робіт, і чому їх не можна змішувати

| Смуга | Що це | Ліцензійний / правовий gate | Операційний дозвіл | Доказ, який вона дає |
| --- | --- | --- | --- | --- |
| **A. Відкритий стек** | Nouveau / NVK / NAK / Mesa / Rusticl / linux-firmware та відкритий source audit | Для аналізу публічного відкритого коду окремий proprietary-RE clearance не потрібен | Read-only source audit та огляд наявних логів/інвентаризації можна виконувати. Завантаження драйвера, `vulkaninfo`/`glxinfo`, GPU enumeration/submit, stress, suspend/resume чи reboot — лише після окремого owner-approved test plan | source-proven факти; runtime-proven на власній карті — лише після дозволеного тесту |
| **B. Runtime-спостереження shipped-стеку** | власний LD_PRELOAD-shim, `strace`, `bpftrace`, sysfs/debugfs, RM API | Відсутність статичного vendor-binary RE сама по собі не створює окремого copyright-analysis gate; застосовні умови продукту й ОС усе одно діють | **Кожна конкретна сесія потребує окремого scope/owner approval.** Запуск traced application, `cuInit`, CUDA/Vulkan initialization, RM/UVM ioctl, RM alloc/control, GPU submit, ptrace attach, BPF/kprobe/ftrace/perf attach, driver switch/unbind, firmware, BAR/MMIO, BOOT0, reboot та hardware stress не дозволені цим документом | спостережувана послідовність викликів — лише після окремо дозволеного запуску; це не статичний доказ ABI |
| **C. Статичний аналіз proprietary бінарників** | REA/rizin, Ghidra по `libcuda`, `nvidia.ko`, `nvidia-uvm.ko` | **Потрібен письмовий дозвіл власника** (див. gate у [#62](https://github.com/juv4uk/gp107-nvidia-re/issues/62)) та перевірка точного дозволеного scope | Clearance на статичний аналіз не надає дозволу на runtime взаємодію з драйвером/GPU; вона потребує окремого погодження | `statically proven` факти про конкретний SHA |

Правило: **ліцензійний clearance і дозвіл на експеримент — два незалежні gate-и**.
Робота в смузі C не починається, доки власник письмово не зафіксує clearance
для конкретних артефактів і методів. До того моменту з C дозволено лише те, що
вже опубліковано в [`41`](41-rea-p1-libcuda-userspace-uuid-source.md)
(owner-approved evidence), і перевірку публічних CUDA/NVIDIA ABI-заголовків —
без нового розкриття бінарника.

Позначка «ліцензійний gate не потрібен» у смугах A/B **не є операційним дозволом**.
Цей документ не надає blanket approval на запуск інструментів, GPU workload або
драйверних інтерфейсів. Поточний безпечний обсяг без нового owner approval —
публічний source audit, аналіз уже наявних evidence та read-only inventory/log
review. Для будь-якого runtime-кроку потрібні точна команда, цільовий пристрій,
очікувані ioctl/API, межі часу/ресурсів, критерії зупинки й окреме явне
погодження власника.

Це не формальність: саме змішування смуг дає найдорожчі помилки — коли
спостереження за викликами подають як «доведений ABI», а один вдалий запуск — як
«драйвер працює».

## 2. Що вже доведено — не переробляти

За [`07`](07-next-research-direction.md) runtime-proven є рівно це:

- PCI/RM-ідентичність і шлях GPU-вузла через `minor_number`;
- RM-ланцюжок до `NV20_SUBDEVICE_0` і `MC_GET_ARCH_INFO`;
- явний `NV_ESC_RM_FREE` у зворотному порядку, включно з частковими відмовами;
- fail-closed BAR0-negative: `OPEN_DENIED`, `MMAP_DENIED`;
- `NV_PMC_BOOT_0` лишається **`UNPROVEN`** — і `arch=0x130 / impl=0x7` не є
  дозволом на MMIO.

Будь-яка нова сесія починається з цього списку, а не з нуля.

## 3. Залишкові цілі: ціль → питання → інструмент → смуга

| # | Ціль | Невідоме | Інструмент | Смуга | Критерій green |
| --- | --- | --- | --- | --- | --- |
| [#61](https://github.com/juv4uk/gp107-nvidia-re/issues/61) | userspace UUID producer для `UVM_REGISTER_GPU` | хто формує поле `device+0xc06` | REA/rizin по `libcuda` (SHA `20ad4403…`) | **C** | writer поля + ланцюг до нього, два незалежні прогони |
| [#62](https://github.com/juv4uk/gp107-nvidia-re/issues/62) | callback producer `device+0xc06`, `BDF ↔ RM gpu_id` | що встановлює `[holder+0x30]`; чи є прямий mapping | REA (статично) + `lspci -vv` / RM `GET_PROBED_IDS` (runtime) | **C** + **B** | callback writer доведено; BDF↔gpu_id або доведено, або явно `NOT_AVAILABLE` |
| E1 | порядок `ioctl`/`mmap` для `cuCtxCreate…cuLaunchKernel` | реальна послідовність викликів | власний LD_PRELOAD-shim + `strace -f -yy -e trace=ioctl,mmap,openat` | **B** | таблиця викликів, два прогони, невідомий request = окремий `UNPROVEN` рядок |
| E2 | channel/context lifecycle | які RM-класи приймає R580 | власний C-зонд `NV_ESC_RM_ALLOC`/`RM_CONTROL` | **B** | alloc → control → free у зворотному порядку; інʼєкція часткової відмови звільняє рівно створене |
| E3 | pushbuffer/GPFIFO формат | мінімальний запис команди | власні структури + `SizeOf`-asserts, submission через E2 | **B** | власний маркер submitted + звірка порядку полів із trace |
| E4 | синхронізація | семафори/fence/notifier | `bpftrace` kprobes на nouveau/nvidia, tracefs, явний timeout | **B** | два прогони з однаковим фінальним статусом; timeout не приховується |
| E5 | MMIO seam | `NV_PMC_BOOT_0` | UEFI/bare-metal або ізольований процес із підтвердженим доступом | **B** (окремий seam) | документ із власником доступу, chipset-маскою і реальним read |
| E6 | DMA/GVA + launch | UVM-алокації, GVA, параметри grid/block | інкрементальний підтверджений піднабір після E2–E4 | **B** | один підтверджений під-крок, не «драйвер одразу» |
| [#28](https://github.com/juv4uk/gp107-nvidia-re/issues/28) | матриця повноцінності й benchmark | що саме вважати PASS на відкритому стеку | `vulkaninfo --summary`, `glxinfo -B`, наявний `tests/nvk-gp107-vector-add`, власний harness | **A** | кожна клітинка матриці має стан і сирі логи |
| [#5](https://github.com/juv4uk/gp107-nvidia-re/issues/5) | RM object lifecycle | cleanup після часткової відмови | той самий C-зонд, інʼєкція відмови | **B** | жодного витоку обʼєкта після відмови |
| [#18](https://github.com/juv4uk/gp107-nvidia-re/issues/18) | legacy FIFO non-stall event index, runlist ID | індекси й ID | pinned Nouveau source (`ripgrep`), [`09`](09-gp107-fifo-nonstall-source-audit.md) | **A** | source-audit із точними файлами й рядками, без бінарників |

## 4. Порядок, який дає найбільше за найменшу ціну

1. **[#28](https://github.com/juv4uk/gp107-nvidia-re/issues/28) (смуга A)** — першим завершити матрицю з уже наявних evidence, pinned source audit та read-only inventory. Це документаційна робота; не запускати нові GPU probes під виглядом заповнення таблиці.
2. **[#18](https://github.com/juv4uk/gp107-nvidia-re/issues/18) (смуга A)** — продовжити лише source/package provenance для Nouveau FIFO/non-stall; runtime correlation не виводити з source або TOP inventory.
3. Runtime-частина смуги A (renderer enumeration, NVK harness, graphics/compute correctness, stress, suspend/resume) — тільки після owner-approved окремого boot/test plan для конкретної GTX 1050 Ti.
4. **E1 (смуга B)** — лише після окремого approval на точний app invocation і спостережувані syscalls; спершу обмежити request whitelist, timeout, output fields та sanitization. `strace`/LD_PRELOAD можуть запустити або змінити поведінку програми й не є пасивною інвентаризацією.
5. **[#5](https://github.com/juv4uk/gp107-nvidia-re/issues/5) + E2–E6 (смуга B)** — не виконувати без окремого погодження кожної операції. RM_ALLOC/CONTROL, GPU submission, kernel probes, BAR/MMIO та BOOT0 є окремими високоризиковими експериментами, а не автоматичним продовженням E1.
6. **[#61](https://github.com/juv4uk/gp107-nvidia-re/issues/61) / [#62](https://github.com/juv4uk/gp107-nvidia-re/issues/62) (смуга C)** — лише після письмового clearance на статичний proprietary RE. До того — тільки вже owner-approved evidence, публічні ABI-заголовки й зіставлення з відкритим кодом.

## 5. Локальні інструменти: що тримати під рукою

**Безпечна базова інвентаризація / source audit (без нового runtime):**

- `ripgrep` / `git grep` по pinned дереву Nouveau, NVK і Mesa — source audit смуги A;
- `sha256sum`, `readelf`, `modinfo`, `dpkg-query` — ідентичність уже наявних артефактів і package provenance;
- `lspci -nnk`, `lsusb`, `journalctl -k -b` — read-only inventory/наявні boot logs; публікувати без serial, UUID, MAC і персональних шляхів;
- `lspci -vv` може показати resource ranges, але не читає й не записує BAR contents; це не дозвіл на BAR/MMIO mapping.


**Для смуги A (відкритий стек):**

- `vulkaninfo --summary` і `glxinfo -B` можуть ініціалізувати Vulkan/OpenGL
  driver stack та GPU; запускати їх лише в окремо схваленій runtime-сесії.
  Вони фіксують renderer (NVK чи llvmpipe), але самі не доводять correctness;
- `dmesg -w` — лише спостереження за новими kernel log events; обмежити час
  та sanitize output;
- `/sys/class/drm/card*/device/hwmon/*/` — read-only temperature/frequency
  inventory; відсутність файлів означає unavailable, не нуль;
- `/sys/kernel/debug/dri/*/` — читати лише відомі read-only nodes; не робити
  debugfs writes;
- наявний `tests/nvk-gp107-vector-add` — correctness harness, але runtime mode
  виконує GPU submission і потребує окремої owner-approved test session.


**Для смуги B (лише після окремого owner-approved runtime plan):**

- власний LD_PRELOAD-shim (не копіюючи vendor-код) — лише номер `ioctl`,
  напрямок, розмір параметрів, імʼя публічної константи, статус; shim може
  змінити таймінг і control flow програми, тому потрібні timeout/stop rules;
- `strace -f -yy -e trace=ioctl,mmap,openat` лише для конкретно схваленого
  app invocation; це не «пасивний» запуск і не дозвіл на невідомі ioctl;
- `bpftrace`, kprobes/uprobes, tracefs та `perf` attach потребують окремого
  погодження на instrumentation scope; до нього не виконувати attach;
- BAR0 лишається недоторканим: жодних `resource0` mmap/read/write, `PROT_WRITE`,
  BOOT0 або firmware/VBIOS операцій без окремого owner-approved plan для E5.


**Для смуги C (лише після clearance):**

- REA (`execute_rizin_command`, rizin 0.9.1) і Ghidra 12.2 — уже зафіксовані в
  [`41`](41-rea-p1-libcuda-userspace-uuid-source.md) як робочий toolchain;
- перед кожним прогоном — повторне підтвердження SHA-256 цілі: `libcuda`
  `20ad4403…`, `nvidia-uvm.ko` `81b21527…`, `nvidia.ko` `95c5fa5a…`;
- `nvdisasm`/`cuobjdump` — для SASS/ELF, не для «розуміння драйвера».

## 6. Антипатерни, які вже коштували часу

- **`arch=0x130` як дозвіл на MMIO.** Це ідентичність, не право. BAR0 — read-only
  до E5 з явним власником доступу.
- **`rev=0xa1` як ознака готовності.** Не є. Готовність — це fence/notifier із
  явним timeout.
- **«Модуль завантажився» як «драйвер працює».** Рівні доказу різні; див.
  [`05`](05-gp107-capability-matrix.md).
- **FPS без фіксації renderer.** Якщо `vulkaninfo` каже llvmpipe, число не
  стосується GP107.
- **Змішування смуг.** Runtime-спостереження не стає `statically proven`, а один
  успішний запуск не стає `PASS` у матриці.

**Поточна авторизація:** до окремого погодження власника дозволені лише
публічний source audit, аналіз уже наявних evidence та read-only inventory /
log review. Наявність інструмента в системі чи відсутність окремого ліцензійного
gate не змінює цього операційного статусу.

## 7. Що цим документом **не** зроблено

- Жодного нового доказу не додано: усі статуси лишаються там, де були.
- Жодного аналізу proprietary бінарників не виконано — смуга C чекає на
  письмовий clearance власника.
- Жодного запуску на фізичній карті не було: усе вище — план і toolchain, не
  вимір.

## 8. Хто споживає кожну смугу — і що з цього не потребує реверсу

Смуги A/B/C описують **спосіб** роботи. Вони не відповідають на питання, яка
з них потрібна для того, що користувач може отримати сьогодні. Цей розділ
додає третій вимір — споживача.

| Споживач | Що йому потрібно | Смуга | Чи потрібен реверс |
| --- | --- | --- | --- |
| **wsm-desktop Compatibility** (пропрієтарний R580 через Nonguix `nvidia-service-type`) | робочий `nvidia.ko` + evidence на конкретному залізі | — | **Ні** |
| **Відкритий стек** (nouveau / NVK) | доказ кореляції channel ↔ event і runlist | A + B | вузько |
| **Власний драйвер Lisp-машини** | повний шлях подання команд | B + C | так, але це роки |

### Compatibility не потребує реверсу зовсім

Пропрієтарний драйвер уже працює на цій карті: `runtime-proven` у
[`05`](05-gp107-capability-matrix.md) (#2, #6, #7). Питання не в знанні, а в
пакуванні й доказах:

1. `nvidia-service-type` у профілі Compatibility — є;
2. `kernel-arguments` з `modprobe.blacklist=nouveau` і `nvidia_drm.modeset=1` — є;
3. **немає** evidence-файлу з реального заліза (Gigabyte GA-H170-Gaming 3,
   i5-6400, GTX 1050 Ti) — ось справжній блокер релізу.

Робота тут — прогнати `wsm-hwcheck` на власній машині й записати evidence
bundle. Жодного рядка реверсу це не потребує, і жодна смуга не скорочує цей
шлях.

### Відкритий стек уже виконує обчислення

NVK vector-add пройшов фізично ([`14`](14-nvk-vector-add-compute-result.md)).
Тобто смуга A вже дала результат, а не план. Незакритим лишається
`UNPROVEN` із [`13`](13-nouveau-nvk-boot-witness.md): кореляція channel ↔ event
і GR TOP runlist 0.

### Що з цього випливає для порядку роботи

Розділ 4 дає порядок за ціною. Цей розділ додає фільтр за споживачем:

- **evidence на H170** — розблоковує реліз Compatibility, не потребує смуг;
- **E1** (read-only трасування) — найдешевше в смузі B, без root і без BAR0;
- **E3** (формат pushbuffer) — має сенс лише за наявності споживача;
- **BOOT0 через MMIO, bare-metal seam, DMA/GVA, власний дисплей** — цікаві, але
  не змінюють жодної можливості, доступної сьогодні. Лишаються поза чергою,
  доки не зʼявиться продукт, якому вони потрібні.

Це не змінює статусів у [`05`](05-gp107-capability-matrix.md) і не дає дозволу
на writable BAR0. Це лише вказує, яка робота наближає продукт, а яка — ні.
