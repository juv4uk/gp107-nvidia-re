# Мінімальний NVK compute witness для GP107

Цей harness — окремий фізичний acceptance test для GTX 1050 Ti / GP107
(PCI 10de:1c82). GitHub Actions перевіряє shader/SPIR-V/C build без GPU;
це не означає, що NVK уже працює на конкретній карті.

## Передумова безпеки

До запуску будь-якого GPU test має бути закрито issue #18:
https://github.com/juv4uk/gp107-nvidia-re/issues/18

Потрібно отримати TOP trace з фізичної GP107, встановити GR/compute runlist
і вирішити conditional FIFO non-stall event-index risk. Поки цього немає,
run script повертає exit 78 до enumeration; сам C harness теж має
compile-time fail-closed gate GP107_FIFO_NONSTALL_REVIEW_CLEARED=0.
Не створювати gate file вручну й не запускати dispatch до owner-reviewed
evidence та окремого source change.

## Що саме перевіряється після зняття gate

1. У системі рівно один PCI-пристрій 10de:1c82, і його sysfs driver link
   указує на upstream nouveau. Скрипт не unbind-ить, не blacklist-ить і
   не змінює драйвер чи конфігурацію.
2. Завантажується лише Mesa Nouveau Vulkan ICD (VK_DRIVER_FILES), а
   DRI_PRIME примусово вибирає знайдений PCI BDF.
3. Програма перевіряє vendorID=0x10de, deviceID=0x1c82 і точні
   domain:bus:device.function через VK_EXT_pci_bus_info. Вона вимагає
   NVK/Nouveau driverName та compute queue. Будь-яка неоднозначність
   завершується помилкою, а не Intel/CPU fallback.
4. Створюється compute pipeline із SPIR-V shader, виконується
   vkCmdDispatch, команда завершується fence, вихідний storage buffer
   читається хостом.
5. CPU перевіряє кожен елемент і незалежну 64-бітну суму для двох workload:
   257 елементів (tail/bounds) і 1 048 576 елементів (обсяг).

Shader: GLSL uint vector-add, local_size_x=64, bounds guard.
Без vendor extensions, subgroup, FP16, images або atomics. Vulkan API
версія зчитується з фізичного пристрою під час enumeration; для GP107
у Mesa source очікується 1.3, але harness друкує фактичне значення.

## Native Linux prerequisites

Потрібен окремий native Linux boot, у якому GP107 уже прив'язаний до
upstream Nouveau. Не запускати під Windows/WSL, не перемикати драйвер
із робочої desktop session і не виконувати тест паралельно з proprietary
NVIDIA KMD.

Для Debian/Kali/Ubuntu:

~~~sh
sudo apt install build-essential pkg-config libvulkan-dev \
  mesa-vulkan-drivers glslang-tools spirv-tools pciutils
~~~

Build-only (можна без GPU):

~~~sh
./scripts/build-nvk-gp107-compute.sh
~~~

Runtime (залишається заблокованим до закриття issue #18):

~~~sh
./scripts/run-nvk-gp107-compute.sh
~~~

Build script:
- компілює vector_add.comp у SPIR-V;
- перевіряє його через spirv-val;
- робить spirv-dis у build/nvk-gp107-compute/vector_add.spvasm;
- збирає C harness з -Wall -Wextra -Werror;
- записує SHA-256 binary/SPIR-V/disassembly.

## Standard enumeration і діагностичний override

Після зняття FIFO gate run script спершу запускає стандартне enumeration
без developer override. Якщо Vulkan не показав GP107 (окремий exit 10),
виконується другий, окремий enumeration-only запуск із:

~~~sh
NVK_I_WANT_A_BROKEN_VULKAN_DRIVER=1
~~~

У коді цей шлях друкує EXPERIMENTAL_ENUMERATION_ONLY: PASS і ніколи
не робить compute dispatch. Це лише діагностика того, чи можна
перерахувати пристрій; не означає підтримку або працездатність NVK.
Немає повторної спроби з override для BDF mismatch, чужого driver,
неоднозначності, збою loader або інших помилок. Завжди потрібен точний
PCI ID і BDF; Intel HD 530 / llvmpipe не зараховуються.

## Evidence bundle

Зберегти без редагування:

- UTC timestamp, uname -a, /etc/os-release, /proc/cmdline;
- lspci -Dnnk -s BDF, sysfs driver symlink, package/kernel/Mesa versions;
- commit SHA harness, SPIR-V SHA-256, binary SHA-256;
- повний stdout/stderr та exit code;
- journalctl -b -k -o short-monotonic навколо тесту.

Очікувані рядки після фізичного PASS:

~~~text
TARGET: 0000:01:00.0 (10de:1c82), kernel-driver=nouveau
DEVICE: ...
PCI: 0000:01:00.0 vendor=10de device=1c82
DRIVER: NVK | Mesa ...
VULKAN_API: 1.3.x
BDF-ASSERTION: PASS (10de:1c82 at 0000:01:00.0)
QUEUE_FAMILY: index=0 count=... flags=0x...
COMPUTE_QUEUE: family=... flags=...
COMPUTE_CASE: PASS elements=257 groups=5 fence=signaled cpu_checksum=...
COMPUTE_CASE: PASS elements=1048576 groups=16384 fence=signaled cpu_checksum=...
GPU-COMPUTE: PASS cases=2
~~~

Текстові значення deviceName, driverInfo, API version, queue flags і BDF
отримуються з runtime, не хардкодяться. BDF вище — лише приклад.

## Статуси та exit codes

- BUILD-ONLY: PASS — CI перевірив C і SPIR-V; GPU не використовувався.
- 0 — enumeration-only pass або після окремого зняття gate повний compute pass.
- 10 — GP107 не з'явився в стандартному Vulkan enumeration; тільки цей
  код запускає experimental enumeration retry.
- 11 — Vulkan показав PCI ID, але BDF не відповідає запитаному.
- 12 — точний PCI/BDF відповідає, але driverName не NVK/Nouveau.
- 13 — більше одного точного NVK match.
- 14 — не вдалося довести BDF через відсутній VK_EXT_pci_bus_info.
- 78 — FIFO gate ще не знятий.
- NOT_RUN / UNPROVEN — поки немає локального evidence bundle з GP107.

Workflow .github/workflows/nvk-gp107-compute-build.yml є тільки build-only:
він не запускає enumeration або GPU workload на hosted runner.
