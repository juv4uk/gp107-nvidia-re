# 44 — Evidence-backed матриця відкритого стека GP107

**Призначення:** попередньо заповнити Issue [#28](https://github.com/juv4uk/gp107-nvidia-re/issues/28) лише тими клітинками, для яких уже є перевірювані свідки. Це не новий тестовий прогін і не сертифікація конкретної системи.

**Зріз доказів:** репозиторій gp107-nvidia-re на `2adb1df03e24`, 2026-11-28. Джерела кожної клітинки вказано окремо.

## 1. Три середовища, які не можна змішувати

| Контекст | Що відомо | Що не можна з цього виводити |
|---|---|---|
| Зовнішній фізичний GP107 свідок (Kali, відкрита Nouveau/NVK сесія) | Для PCI 10de:1c82 зафіксовано Nouveau binding, NVK physical-device enumeration та окремий реальний vector-add dispatch із fence і CPU readback. Див. [13](13-nouveau-nvk-boot-witness-result.md) і [14](14-nvk-vector-add-compute-result.md). | Це не доводить, що та сама Linux-конфігурація, kernel, Mesa або firmware зараз працюють на H170. |
| Зовнішній фізичний GP107 свідок (Kali, NVIDIA R580) | Є окрема історична R580 baseline та дослідницькі артефакти; див. [20](20-reliability-baseline-proprietary.md), [21](21-proprietary-performance-matrix.md), [22](22-device-local-transfer-and-compute-phases.md). | Ці результати не є NVK A/B і не доводять функціональність Compatibility профілю WSM на H170. Дані з docs/22 позначені NOT ACCEPTED до повторного build/validation/runtime. |
| Цільова система власника (Gigabyte GA-H170-Gaming 3, Intel i5-6400, GTX 1050 Ti) | Ідентифікатори й окремі hardware observations відомі з owner-side Windows inventory. | Native Linux H170 inventory, WSM hardware report, Nouveau/NVK KMS/graphics та Compatibility acceptance ще не зараховані. H170 runtime залишається NOT_RUN. |

Зовнішній witness — це фізичний GP107, але не доказ H170. Windows device ID — це не доказ роботи Linux DRM. Пакет або драйвер, присутній у каналі чи ISO, — це не runtime acceptance.

## 2. Попередньо заповнена capability matrix

Стани використовують контракт Issue #28: PASS, FAIL, NOT_AVAILABLE, NOT_MEASURED, UNPROVEN. PASS завжди має обмежений обсяг — він поширюється тільки на вказаний тест і свідка.

**Процедурна примітка до compute witness:** docs/14 фіксує реальний історичний NVK vector-add dispatch із signaled fence та правильним CPU readback/checksum. Водночас docs/18 прямо фіксує `runtime-proven deviation`: погоджений source/BTF preflight не був повністю завершений до цього dispatch. Тому результат слід читати як `HISTORICAL_EXTERNAL_GP107_COMPUTE_WITNESS / PROCEDURAL_DEVIATION`, а не як clean acceptance, щоденний stability PASS або дозвіл повторити workload. Це не змінює факт конкретного успішного dispatch, але обмежує його доказову силу.

> **Правило версій для кожної клітинки.** На цій карті версія ядра змінює
> відповідь, і це не теорія: регресія atomic modesetting у 7.3.x дає NULL deref
> під час ініціалізації дисплея саме на GP107 (звіт 2026-11-02, фікс
> `ed7fb901fce3` у mainline 2026-11-25). Тому кожен `PASS` і кожен
> `NOT_AVAILABLE` мусить називати трійку — **ядро / Mesa (або NVIDIA) / снапшот
> linux-firmware** — інакше клітинка описує невідому конфігурацію, і «KMS
> працює» без версії ядра не є твердженням. Деталі й джерела — у
> [`48`](48-gp107-open-stack-status-2026-11.md) §3.1–3.2.
>
> **Стан на 2026-11-28:** п'ять клітинок `PASS` заповнені трійкою з того, що
> реально зафіксовано в свідках (`docs/13`: ядро `7.2.15+kali-amd64`, Mesa
> `26.1.6`). **Снапшот linux-firmware не збирався ніде** — тому в цих клітинках
> стоїть `NOT_RECORDED`, а не вигадана версія. Реклочинг позначений окремо: його
> `NOT_AVAILABLE` походить з upstream-джерел, а не з прогону, тож трійка до нього
> не застосовується.

| Область | Поточний стан | Що вже доведено | Чого це не доводить / наступна межа |
|---|---|---|---|
| PCI identity / фізичне визначення GPU | **PASS — зовнішній GP107 witness** | **Версії:** ядро `7.2.15+kali-amd64`, Mesa `26.1.6`, linux-firmware — `NOT_RECORDED` ([13](13-nouveau-nvk-boot-witness-result.md) фіксує ядро й Mesa, снапшот прошивки не збирався). PCI vendor/device 10de:1c82, BDF 0000:01:00.0 та назва GTX 1050 Ti узгоджуються в sysfs і Vulkan device record. [13](13-nouveau-nvk-boot-witness-result.md), [14](14-nvk-vector-add-compute-result.md). | Точна retail-модель плати й її VBIOS identity — окремі питання; H170 native inventory — NOT_RUN. |
| Nouveau binding на GP107 | **PASS — зовнішній GP107 witness** | **Версії:** ядро `7.2.15+kali-amd64`, Mesa `26.1.6`, linux-firmware — `NOT_RECORDED` ([13](13-nouveau-nvk-boot-witness-result.md) фіксує ядро й Mesa, снапшот прошивки не збирався). У зафіксованій відкритій boot-сесії kernel driver in use — nouveau; активні модулі NVIDIA не були завантажені на момент свідка. [13](13-nouveau-nvk-boot-witness-result.md). | Один boot witness не доводить cold/warm reboot reliability, KMS stability або роботу на H170. |
| NVK physical-device enumeration | **PASS — зовнішній GP107 witness** | **Версії:** ядро `7.2.15+kali-amd64`, Mesa `26.1.6`, linux-firmware — `NOT_RECORDED` ([13](13-nouveau-nvk-boot-witness-result.md) фіксує ядро й Mesa, снапшот прошивки не збирався). Vulkan бачить NVIDIA GeForce GTX 1050 Ti (NVK GP107), driverID Mesa NVK, API 1.3.354, Mesa 26.1.6. [13](13-nouveau-nvk-boot-witness-result.md). | Enumeration не є графічним тестом, benchmark або доказом Vulkan 1.4 на цій реалізації. |
| Vulkan compute correctness | **PASS — bounded historical smoke; PROCEDURAL DEVIATION** | **Версії:** ядро `7.2.15+kali-amd64`, Mesa `26.1.6`, linux-firmware — `NOT_RECORDED` ([13](13-nouveau-nvk-boot-witness-result.md) фіксує ядро й Mesa, снапшот прошивки не збирався). Історичний зовнішній NVK dispatch, signaled fence, host readback, checksum збігається з CPU reference; negative no-op control завершується очікуваною помилкою. [14](14-nvk-vector-add-compute-result.md). [18](18-procedural-deviation-and-benchmark-reliability.md) фіксує, що погоджений source/BTF preflight не був повністю завершений до dispatch. | Це runtime-факт конкретного workload, не clean acceptance, новий baseline, довготривала стабільність, multi-context чи дозвіл на повтор. |
| DRM/KMS modeset, connectors, EDID, hotplug | **UNPROVEN** | Nouveau binding і відкритий boot witness є непрямим контекстом. [13](13-nouveau-nvk-boot-witness-result.md). | Немає окремого acceptance ledger з connector/EDID/modeset, hotplug, DPMS та перевіркою видимого scanout. Потрібні read-only DRM inventory й окремо погоджений display test. |
| OpenGL / Nouveau Gallium renderer | **NOT_MEASURED** | Відкритий стек описано в [06](06-open-driver-landscape.md). | Немає прийнятого GP107 runtime record із glxinfo renderer, GL version/extensions та correctness smoke. |
| Vulkan graphics rendering | **NOT_MEASURED** | NVK пристрій enumerates, але це тільки device properties. [13](13-nouveau-nvk-boot-witness-result.md). | Немає прийнятого graphics pipeline/render target/readback correctness test. |
| Single-dispatch queue submit / fence | **PASS — bounded historical witness; PROCEDURAL DEVIATION** | **Версії:** ядро `7.2.15+kali-amd64`, Mesa `26.1.6`, linux-firmware — `NOT_RECORDED` ([13](13-nouveau-nvk-boot-witness-result.md) фіксує ядро й Mesa, снапшот прошивки не збирався). Vector-add пройшов queue submit, fence wait/status і CPU readback в одному harness run. [14](14-nvk-vector-add-compute-result.md); процедурне обмеження зафіксовано у [18](18-procedural-deviation-and-benchmark-reliability.md). | Повторні запуски, кілька контекстів/черг, довготривала синхронізація та failure-recovery не вимірювалися; це не clean acceptance і не дозвіл на повтор. |
| OpenCL / Mesa Rusticl | **NOT_MEASURED** | Rusticl визначено як окремий потенційний шлях у [06](06-open-driver-landscape.md). | Немає GP107 device enumeration і kernel-correctness evidence; наявність OpenCL loader не зараховується. |
| NVDEC / NVENC | **NOT_MEASURED** | У наявних документах немає прийнятого runtime acceptance для відкритого GP107 stack. | Перевіряти кожен backend окремо; не оголошувати NOT_AVAILABLE без перевіреного scope/джерела. |
| Pascal reclocking | **NOT_AVAILABLE — практичний Nouveau шлях** | **Версії:** твердження походить з upstream-джерел, не з прогону на цій конфігурації, тому трійка версій до нього не застосовується; це властивість відкритого стеку, а не вимірювання. Upstream Nouveau/Mesa research вказує на firmware/signing обмеження reclocking для GP10x/Pascal. [06](06-open-driver-landscape.md). | Це не означає, що базові KMS, OpenGL або compute функції відсутні. Будь-яка частота/продуктивність має бути позначена як boot-clock чи інший фактично доведений стан. |
| Температура, clocks, power telemetry | **NOT_MEASURED** | Для збору доступних показників визначено read-only hwmon шлях у [42](42-local-toolchain-and-remaining-targets.md). | Відсутність hwmon node означає unavailable/not exposed, а не нуль. Дані ще не прийняті як виміряний baseline. |
| Suspend/resume, runtime PM, GPU reset/recovery | **NOT_MEASURED** | Немає окремого прийнятого runtime свідка; пошук по виконанню (`grep "PM: suspend"`) по репозиторію дає нуль, а `ACPI: PM: (supports S0 S3 S4 S5)` — це оголошення платформи, не цикл. | Потрібен окремий owner-approved тест-план із recovery/stop criteria; не запускати під час інвентаризації. Чернетка плану — [`48`](48-gp107-open-stack-status-2026-11.md) §3.7 (`rtcwake`, три повтори, stop criteria). |
| 30–60 хв змішаного навантаження / VRAM pressure | **NOT_MEASURED** | Наявний vector-add — короткий correctness smoke. | Немає довготривалого stability evidence, OOM/pressure або recovery results. |
| WSM H170 native hardware acceptance | **NOT_MEASURED** | Цільова конфігурація відома з owner-side hardware context. | Немає native Linux H170 inventory/log bundle та пов'язаного WSM hardware report. Зовнішній Kali witness не може закрити цей пункт; H170 runtime — NOT_RUN. |
| WSM Guix Compatibility acceptance на H170 | **NOT_MEASURED** | У WSM є окремий Compatibility profile/backend plan. | Немає H170-specific installation/boot/driver evidence. Це integration/provenance задача, не завдання для нового RM reverse engineering. |

## 3. Що це означає для WSM

1. **Compatibility path:** першою потрібна H170-specific read-only inventory і WSM hardware evidence. Це важливіше за нову RE-роботу. Не додавати неперевірені драйверні припущення до Free профілю; Compatibility залишається окремим контуром.
2. **Відкритий GPU path:** на зовнішньому GP107 є один bounded historical NVK compute witness із `PROCEDURAL DEVIATION` у preflight (docs/18). Це не clean acceptance і не baseline. Для desktop readiness окремо залишаються KMS/display, OpenGL Gallium, Vulkan graphics, thermal/stability і suspend/resume.
3. **Performance:** не використовувати старі docs/17 чи docs/22 числа як прийнятий NVK A/B. [22](22-device-local-transfer-and-compute-phases.md) прямо вимагає rebuild виправленого harness, synchronization validation і новий physical rerun. R580 docs/20–21 — тільки окремий proprietary baseline.
4. **Висновок:** ця матриця не дає статусу «повноцінний драйвер» або «daily-driver-capable». Вона лише відділяє те, що реально доведено, від того, що треба виміряти.

## 4. Інструменти локального виконавця та порядок

### До будь-якого runtime test — лише read-only inventory

На власній H170 машині після вибору доступного native Linux boot виконавець спершу збирає:

- uname/kernel release, distribution і package versions;
- lspci -Dnnk (GPU, display, audio, network, storage controllers), lsusb;
- modinfo для фактично bound GPU/network/audio/storage modules, firmware declarations;
- sha256sum і readelf -n для точного модуля, який прив'язаний до пристрою;
- journalctl -k -b із firmware request/result та driver-init messages;
- dmidecode type 0/1/2/4/9 лише за потреби; серійні номери, UUID, MAC, персональні шляхи перед передачею потрібно редагувати.

Зберігати raw stdout/stderr, exit codes, tool versions і manifest hashes. Не публікувати serial, UUID, MAC, приватні paths або інші персональні значення. Цей етап не завантажує інший драйвер і не змінює boot/firmware.

### Після окремого дозволу на конкретний runtime session

Для відкритого стека:

- drm_info і modetest — для DRM resources/connectors/modes; не виконувати modeset без узгодженого плану;
- vulkaninfo --summary — фіксувати, що пристрій саме 10de:1c82 і driverName/driverID = NVK;
- glxinfo -B — підтвердити Nouveau Gallium renderer, не llvmpipe і не Intel HD 530;
- існуючий tests/nvk-gp107-vector-add — повторно використовувати як correctness anchor; не створювати другий harness;
- dmesg -w та read-only /sys/class/drm/.../hwmon — обмежена за часом діагностика під погодженим тестом;
- graphics/stress/suspend-resume workloads — лише після окремого owner approval із time limit, stop criteria та rollback/recovery plan.

Жодна з команд, що ініціалізує GPU stack чи подає роботу на GPU, не запускається автоматично лише тому, що вона є в цьому списку.

## 5. Чого не робити зараз

- Не повторювати NVK vector-add harness і не перезапускати фізичний workload без окремого погодження.
- Не продовжувати смугу C / новий RE proprietary binaries до письмового clearance issue [#62](https://github.com/juv4uk/gp107-nvidia-re/issues/62).
- Не запускати RM/UVM ioctl, BPF/kprobe/ftrace, driver unbind/switch, firmware/VBIOS, BAR/MMIO, BOOT0 або reboot у межах цієї документаційної задачі.
- Не змінювати WSM Free/Compatibility locks або Guix system channels із боку цього репозиторію.
- Не переносити Kali/R580/NVK свідчення на H170 як ніби це один host.

## 6. Джерела доказів

- [06 — відкритий драйверний ландшафт](06-open-driver-landscape.md): upstream capability, per-device Vulkan API limit та firmware caveats.
- [13 — Nouveau/NVK boot witness](13-nouveau-nvk-boot-witness-result.md): physical device identity, Nouveau binding, NVK enumeration.
- [14 — NVK vector-add result](14-nvk-vector-add-compute-result.md): bounded physical compute correctness and negative control.
- [20 — proprietary reliability baseline](20-reliability-baseline-proprietary.md) і [21 — proprietary performance matrix](21-proprietary-performance-matrix.md): R580-only measurements.
- [22 — DEVICE_LOCAL phases](22-device-local-transfer-and-compute-phases.md): exploratory / NOT ACCEPTED until corrected rerun.
- [42 — local toolchain and remaining targets](42-local-toolchain-and-remaining-targets.md): tool boundaries and work order.
- [Issue #28 — capability matrix and benchmarks](https://github.com/juv4uk/gp107-nvidia-re/issues/28): canonical acceptance request.
