# gp107-nvidia-re

Дослідницькі матеріали про протокол взаємодії з драйвером NVIDIA Pascal **GP107** (GeForce GTX 1050 Ti) у Linux: вузли пристроїв, номери `ioctl`, класи команд Resource Manager (RM) і шлях від публічних точок входу CUDA до `/dev/nvidia*`. Репозиторій — дослідницька база знань із невеликими незалежно написаними пробниками мовами C і Free Pascal. Це **не** заміна CUDA Runtime і **не** сховище декомпільованого коду виробника.

## Середовище, на якому перевірено результати

| Параметр | Значення |
|---|---|
| GPU | `01:00.0 NVIDIA Corporation GP107 [GeForce GTX 1050 Ti] [10de:1c82]` |
| Архітектура | Pascal, SM 6.1 (`sm_61`) |
| Драйвер | `580.196.11` (модуль ядра та простір користувача) |
| Ядро | `7.2.15+kali-amd64` |
| Дистрибутив | Kali GNU/Linux Rolling 2026.3, glibc 2.43, GCC 16.2.0 |
| CUDA Toolkit (лише для контрольних тестів) | 12.6.3, `nvcc` V12.6.85 |
| REA/Ghidra | Ghidra 12.2 через REA; `libcuda.so.580.196.11`, SHA-256 `20ad440390dad2c5fd06c14e518990512a8e7b31f8b6add7bb1581832fd4d331` |

> Внутрішні структури RM змінюються між основними гілками драйвера. Якщо не зазначено інше, вважайте кожну таблицю чинною для **R580 / GP107**.

## Документація

| Файл | Призначення |
|---|---|
| [`01-cuInit-flow.md`](docs/01-cuInit-flow.md) | Шлях `cuInit`: виявлення RM-пристроїв, вузли та `ioctl` |
| [`02-cuMemAlloc-and-launch.md`](docs/02-cuMemAlloc-and-launch.md) | Виділення пам'яті через UVM і запуск GPU-ядра без `ioctl` під час самого launch |
| [`03-fpc-clean-room-probe.md`](docs/03-fpc-clean-room-probe.md) | FPC 3.2.2 як основа clean-room пробника, стани доказів і фіксація toolchain |
| [`04-bar-identity.md`](docs/04-bar-identity.md) | Свідки G0/G1: PCI identity проти `NV_ESC_CARD_INFO`, fail-closed для BAR0 |
| [`05-gp107-capability-matrix.md`](docs/05-gp107-capability-matrix.md) | Матриця можливостей GP107 за фактичним станом доказів |
| [`06-open-driver-landscape.md`](docs/06-open-driver-landscape.md) | Огляд відкритого стека Nouveau/Mesa/NVK/Rusticl для GP107 |
| [`07-next-research-direction.md`](docs/07-next-research-direction.md) | План досліджень подання команд RM і синхронізації GPU (E1–E6) |
| [`08-final-sprint-report.md`](docs/08-final-sprint-report.md) | Історичний підсумок пропрієтарних R580 RM-зондів; не є прийманням Nouveau/NVK |
| [`09-gp107-fifo-nonstall-source-audit.md`](docs/09-gp107-fifo-nonstall-source-audit.md) | Аудит вихідного коду FIFO/non-stall і план read-only трасування |
| [`10-open-driver-capability-identity.md`](docs/10-open-driver-capability-identity.md) | Дослідницький контракт identity-capability для відкритого драйвера лісп-машини |
| [`11-proprietary-shipped-artifact-abi-facts.md`](docs/11-proprietary-shipped-artifact-abi-facts.md) | REA-факти з `nvidia.ko` та пропрієтарного ICD без декомпільованого псевдокоду |
| [`12-nouveau-nvk-boot-witness.md`](docs/12-nouveau-nvk-boot-witness.md) | Шаблон одноразового boot-свідка Nouveau/NVK |
| [`13-nouveau-nvk-boot-witness-result.md`](docs/13-nouveau-nvk-boot-witness-result.md) | Фізичне Nouveau/NVK identity та Vulkan enumeration runtime-proven; GR TOP runlist 0, channel/event correlation лишається UNPROVEN (compute result — у docs/14) |
| [`14-nvk-vector-add-compute-result.md`](docs/14-nvk-vector-add-compute-result.md) | Результат clean-room NVK vector-add: фізичний compute-тест пройдено |
| [`15-rea-static-markers-nonstall-runlist-event.md`](docs/15-rea-static-markers-nonstall-runlist-event.md) | Статичні маркери non-stall, channel/runlist та event у пропрієтарному модулі |
| [`16-nvidia-settings-autostart-open-driver-fix.md`](docs/16-nvidia-settings-autostart-open-driver-fix.md) | Виправлення автозапуску NVIDIA Settings у відкритому boot |
| [`17-vulkan-compute-benchmark-open-vs-proprietary.md`](docs/17-vulkan-compute-benchmark-open-vs-proprietary.md) | Історичний NVK ↔ NVIDIA R580 A/B до reliability fixes у docs/18; не є поточним acceptance baseline |
| [`18-procedural-deviation-and-benchmark-reliability.md`](docs/18-procedural-deviation-and-benchmark-reliability.md) | Процедурне відхилення, надійність вимірювань і межі evidence; старий A/B у docs/17 лишається історичним |
| [`19-rea-icd-boundary-and-memory-controls.md`](docs/19-rea-icd-boundary-and-memory-controls.md) | Статичні REA-факти про межу proprietary ICD та RM memory/submit controls; не доводить runtime memory path |
| [`20-reliability-baseline-proprietary.md`](docs/20-reliability-baseline-proprietary.md) | Надійна NVIDIA R580 HOST_VISIBLE/HOST_COHERENT baseline після виправлень harness; не VRAM bandwidth і не NVK A/B |
| [`21-proprietary-performance-matrix.md`](docs/21-proprietary-performance-matrix.md) | 108 proprietary NVIDIA HOST_VISIBLE/HOST_COHERENT points для workgroup × submit batching; не VRAM bandwidth і не NVK A/B |
| [`22-device-local-transfer-and-compute-phases.md`](docs/22-device-local-transfer-and-compute-phases.md) | DEVICE_LOCAL staging/compute/readback; попередні результати NOT ACCEPTED, виправлений код очікує build, validation та physical rerun |
| [`23-rea-p1-function-level-memory-channel-maps.md`](docs/23-rea-p1-function-level-memory-channel-maps.md) | Цільовий R580 UVM→RM RE: function-level memory/VA та channel/submit maps з Evidence ID; memory class, BAR1/VA, notifier/fence lifecycle лишаються UNPROVEN |
| [`24-rea-p1-rm-dispatch-window.md`](docs/24-rea-p1-rm-dispatch-window.md) | Вузьке Rizin-вікно RM dispatch у `nvidia.ko`: адреси, xrefs і межі; не causal proof NVK/NVIDIA performance gap |
| [`25-rea-p1-uvm-caller-map.md`](docs/25-rea-p1-uvm-caller-map.md) | Call-site карти `nvUvmInterfaceMemory*`/`Channel*` у shipped `nvidia-uvm.ko`; runlist, notifier, RM class і BOOT0 лишаються UNPROVEN |
| [`26-rea-p1-uvm-alloc-enum-and-alignment.md`](docs/26-rea-p1-uvm-alloc-enum-and-alignment.md) | Enum-розгалуження `uvm_rm_mem_alloc` і виправлення disalignment у `channel_pool_add`; RM-семантика лишається UNPROVEN |
| [`27-rea-p1-uvm-object-field-aliasing.md`](docs/27-rea-p1-uvm-object-field-aliasing.md) | Offset `+0x1e0` має різні базові об'єкти в `nvidia-uvm.ko`; RM-handle/feature-flag лишаються UNPROVEN |
| [`28-rea-p1-uvm-channel-manager-callers.md`](docs/28-rea-p1-uvm-channel-manager-callers.md) | 5 call-site `uvm_channel_manager_create`: `rdi=gpu`, `rsi=&gpu+0x19f8` (тип уточнено в docs/34–35); RM-семантика лишається UNPROVEN |
| [`29-userspace-capability-driver.md`](docs/29-userspace-capability-driver.md) | C11 sysfs identity + gated C/ASM MMIO API; фізичний MMIO NOT AUTHORIZED / NOT RUN |
| [`30-userspace-capability-ledger.md`](docs/30-userspace-capability-ledger.md) | PCI config-header і capability ledger; software gate ≠ owner approval, RM/BOOT0 UNPROVEN |
| [`31-x86-64-assembly-slice.md`](docs/31-x86-64-assembly-slice.md) | Власний x86-64 read-only asm-примітив з еквівалентністю до C; не release, hardware MMIO NOT_RUN |
| [`tests/nvk-gp107-vector-add/README.md`](tests/nvk-gp107-vector-add/README.md) | NVK GP107 vector-add harness: compile-only CI, fail-closed gates; фізичний GPU тест NOT_RUN |
| [`32-freepascal-primary-slice.md`](docs/32-freepascal-primary-slice.md) | Free Pascal 3.2.2 як основна реалізація; C/asm лишаються еталонами, hardware MMIO NOT_RUN |
| [`33-asm-first-target-contract.md`](docs/33-asm-first-target-contract.md) | opcode-послідовність як авторитетний артефакт під залізо власника; Pascal/C — обгортка/oracle, не реліз |
| [`34-rea-p1-parent-object-and-test-context.md`](docs/34-rea-p1-parent-object-and-test-context.md) | батько з `g_uvm_global+0x28`, чотири call-site в `uvm_test_channel_sanity`; typed-ланцюг уточнено в docs/35 |
| [`35-rea-p1-btf-type-proof.md`](docs/35-rea-p1-btf-type-proof.md) | BTF shipped-артефакта доводить `parent_gpus → uvm_parent_gpu_t → gpus → uvm_gpu_t → channel_manager`; роль `rdi` у гілці `r8==0` — UUID-джерело; caller-и див. docs/37 |
| [`36-r580-artifact-pairing.md`](docs/36-r580-artifact-pairing.md) | `runtime-proven` pairing REA-тарґета `81b21527…` зі встановленим і завантаженим `nvidia_uvm` через version/srcversion/Build ID; без MMIO й vendor source |
| [`37-rea-p1-add-gpu-call-sites.md`](docs/37-rea-p1-add-gpu-call-sites.md) | `statically proven`: рівно два прямі `call add_gpu` — `0x0801eb42` і `0x0801ebf7` в `uvm_gpu_retain_by_uuid`; `rdi` = UUID-джерело, `r8` = база `parent->gpus[]`; хибні адреси явно retracted |
| [`38-rea-p1-register-gpu-uuid-chain.md`](docs/38-rea-p1-register-gpu-uuid-chain.md) | `statically proven`: ланцюг ioctl → `uvm_va_space_register_gpu` → `uvm_gpu_retain_by_uuid` → `add_gpu`; UUID = перше поле ioctl-параметра; походження в userspace / `BDF ↔ RM gpu_id` — `UNPROVEN` |
| [`39-gp107-nouveau-firmware-dependency-map.md`](docs/39-gp107-nouveau-firmware-dependency-map.md) | Pinned Nouveau source/WHENCE map for GP107 FECS/GPCCS, ACR, SEC2, NVDEC firmware, shared symlink closure and Free/Compatibility licensing boundary; source-only, not H170 runtime evidence |
| [`40-rea-p1-gpu-info-uuid-direction.md`](docs/40-rea-p1-gpu-info-uuid-direction.md) | `statically proven`: UUID — вхідний аргумент `nvUvmInterfaceGetGpuInfo`, далі forwarded у `rm_gpu_ops_get_gpu_info` → `_nv046828rm`; гіпотеза про генерацію UUID цим інтерфейсом `retracted`; `BDF ↔ RM gpu_id` — `UNPROVEN` |
| [`41-rea-p1-libcuda-userspace-uuid-source.md`](docs/41-rea-p1-libcuda-userspace-uuid-source.md) | `statically proven`: UUID для `UVM_REGISTER_GPU` і `cuDeviceGetUuid` читається з `device+0xc06` у shipped `libcuda`; кінцевий виробник поля й `BDF ↔ RM gpu_id` — `UNPROVEN`; хибна чернеткова мапа — `retracted observation` |
| [`42-local-toolchain-and-remaining-targets.md`](docs/42-local-toolchain-and-remaining-targets.md) | три смуги робіт (відкритий стек / runtime-спостереження / статичний RE), ліцензійний gate, таблиця «ціль → питання → інструмент» і порядок дій для #61, #62, E1–E6, #28, #5, #18 |
| [`44-open-stack-capability-matrix.md`](docs/44-open-stack-capability-matrix.md) | evidence-backed попередньо заповнена матриця Nouveau/NVK: зовнішній GP107 witness, bounded compute PASS, межі H170 та WSM acceptance |
| [`43-gp107-nonstall-mainline-indexing.md`](docs/43-gp107-nonstall-mainline-indexing.md) | Pinned Linux master source chain: GP107 global non-stall event index versus per-runlist user-channel ID; nonzero runlist risk remains conditional, H170 user-channel correlation UNPROVEN |
| [`ioctl-map.md`](docs/ioctl-map.md) | Зведений довідник `ioctl` та команд RM |

Документація експериментів:

- [`experiments/nvk-compute-smoke/README.md`](experiments/nvk-compute-smoke/README.md) — функціональна перевірка NVK vector-add.
- [`experiments/vk-compute-bench/README.md`](experiments/vk-compute-bench/README.md) — відтворюваний Vulkan compute-бенчмарк для обох ICD.

Сирі логи, знімки стану системи, JSON-докази та SHA-256 маніфести зберігаються в `evidence/` й каталогах `experiments/*/artifacts*/`. Їхній вміст не перекладається: це першоджерела, які мають залишатися точними для повторної перевірки.

## Структура репозиторію

- `docs/` — дослідницькі документи та зведені довідники.
- `evidence/nouveau-20261127/` — сирі логи boot-свідка та SHA-256 маніфести.
- `evidence/rea-20261127/` — JSON-пакети доказів REA.
- `experiments/nvk-compute-smoke/` — функціональний NVK compute harness і його артефакти.
- `experiments/vk-compute-bench/` — порівняльний Vulkan compute harness і його артефакти.
- `probes/` — незалежний C-пробник без `libcuda`.
- `pascal/` — clean-room пробники Free Pascal та описи ABI.
- `scripts/` — збір свідків, декодування `ioctl` і fail-closed гейти.

## Швидкий старт

```bash
make -C probes
sudo ./probes/01_min_cuinit          # або запустити користувачем із групи video
echo 0xc90046c8 | python3 scripts/decode_ioctl.py

make test                            # FPC 3.2.2 pin + static ELF + runtime-свідки трьох пробників
make test-valid-cards-static         # лише fail-closed source guard; без FPC/GPU/RM
make gate-root                       # необов'язковий root-свідок: mmap EINVAL, BOOT0 UNPROVEN
sudo ./pascal/02_bar_identity        # ручний root-свідок
```

## Методика та перевірка

1. **Статичний аналіз:** REA/Ghidra 12.2 дослідив публічні експорти `libcuda.so.580.196.11`. Зафіксовано лише потоки керування, графи викликів, числові константи та розкладки структур.
2. **Динамічний аналіз:** мінімальні програми з `dlopen`/`dlsym` викликали `cuInit`, `cuMemAlloc_v2`, `cuLaunchKernel` і `cuMemFree_v2` під `strace`; додатковий перехоплювач `LD_PRELOAD` виводив слова параметрів RM. Він виявив точний ланцюжок `GPU_ATTACH_IDS` → `NV01_DEVICE_0` → `NV20_SUBDEVICE_0`; `03_rm_arch_info.pas` відтворює його незалежно.
3. **Перехресна звірка:** константи перевірено за публічними заголовками драйвера (`nv-ioctl-numbers.h`, `nv-ioctl.h`, `nv_escape.h`, `uvm_ioctl.h`, `ctrl2080*.h`) з відповідного дерева вихідного коду `580.196.11`.
4. **Стани доказів:** кожне твердження має позначку `statically proven`, `runtime-proven` або `string-only`; якщо регістр недоступний для читання, він залишається `UNPROVEN`, а не виводиться з текстового рядка.

Жоден фрагмент декомпільованого коду з першого кроку дослівно не відтворюється в цьому репозиторії.

## Мовна політика документації

Українська є основною мовою документації, пояснень, висновків і назв розділів. Без перекладу залишаються назви API та ABI, ідентифікатори, символи драйвера, команди, шляхи, фрагменти вихідного коду, власні назви проєктів і точні машинні повідомлення. Сирі журнали та артефакти доказів не редагуються й не локалізуються, щоб не змінювати першоджерела. Назви файлів документації збережено для сумісності посилань.

## Юридичні примітки та межі

- Проєкт дотримується принципу **Clean Room Design**: документацію написано на основі спостережуваної поведінки й опублікованих фактів ABI; псевдокод Ghidra, вихідний код виробника та двійкові файли виробника до репозиторію не додаються.
- Власні текст і код репозиторію поширюються за ліцензією **ВОЛЬНІСТЬ**, наведеною у [LICENSE](LICENSE). Заголовки драйвера NVIDIA використовувалися лише як довідка для числових констант і розкладок ABI; вони не поширюються разом із цим репозиторієм.
- NVIDIA, CUDA та GeForce — торговельні марки NVIDIA Corporation. Проєкт не пов'язаний із NVIDIA та не схвалений нею.

## Що не є метою проєкту

- Повторна реалізація Resource Manager, UVM або API драйвера CUDA.
- Підтримка архітектур, відмінних від Pascal GP107 (хоча більшість номерів escape-команд спільні між гілками драйвера).
- Обхід механізмів безпеки драйвера, перевірки підпису чи контролю доступу.
