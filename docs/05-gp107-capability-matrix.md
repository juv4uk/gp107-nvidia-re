# 05 — Матриця можливостей GP107/GTX 1050 Ti під R580

Це **неавторитетний research-довідник**. Він фіксує, які дії власними
clean-room зондами справді виконано на цій машині, а які лише описані,
припущені або не перевірені. Документ **не змінює** SENS, CML, `wsm-os-lisp`,
його ABI-pin, ADR чи target contract. Перенесення будь-якої capability в
систему вимагає окремого рішення власника.

## Профіль доказової бази

| Параметр | Значення | Стан |
|---|---|---|
| GPU | `10de:1c82 @ 0000:01:00.0`, GTX 1050 Ti (GP107) | runtime-proven, PCI sysfs + `NV_ESC_CARD_INFO` |
| Драйвер | `580.196.11` (`/proc/driver/nvidia/version`) | runtime-proven, у preflight гейту |
| Компілятор | FPC `3.2.2` (`3.2.2+dfsg-51`), x86_64/linux | runtime-proven через `-iV/-iTP/-iTO` |
| CUDA tooling (історичний шлях) | `nvcc` 12.6.85 / CUDA 12.6.3 | runtime-proven у попередньому зрізі; тут не використовується |
| Hosted стан | активний `nvidia.ko`, `/dev/nvidiactl`, `/dev/nvidia0` | runtime-proven |
| Бар'єр | BOOT0 прямим MMIO не прочитано | UNPROVEN, normative |

## Статуси фактів

| # | Факт / capability | Стан | Свідок або межа |
|---:|---|---|---|
| 1 | PCI-ідентичність `10de:1c82` збігається між `NV_ESC_CARD_INFO` і sysfs config | **runtime-proven** | `CROSS-CHECK-OK: pci-config == NV_ESC_CARD_INFO` у `02_bar_identity.pas` |
| 2 | GPU-вузол обчислюється з `minor_number`, а не хардкодується | **runtime-proven** | `NV_ESC_CARD_INFO target ... minor=0` → `GPU device node : /dev/nvidia0`; 0 або >1 збігів дає `RM-ARCH-FAIL` |
| 3 | `NV_ESC_SYS_PARAMS` приймає `block_size_bytes = 0x08000000` | **runtime-proven** | sysfs → `NV_ESC_SYS_PARAMS  : memblock_size = 134217728 bytes` |
| 4 | `NV_IOC_CARD_INFO=$c90046c8`, `NV_IOC_SYS_PARAMS=$c00846d6`, `NV_IOC_REGISTER_FD=$c00446c9` | **statically proven + self-check** | `NvIOC_RDWR()` у `nv_abi.pas`, звірка до першого ioctl |
| 5 | Розкладки `Tnv_pci_info=12`, `Tnv_card_info=72`, `Tnvos00=16`, `Tnvos54=32`, `Tnvos64=48`, `Tarch_info_params=16` | **statically proven** | compile-time `SizeOf`-assertи + два negative witnesses у гейті |
| 6 | RM-ланцюжок `ROOT_CLIENT → GPU_ATTACH_IDS → NV01_DEVICE_0 → NV20_SUBDEVICE_0` | **runtime-proven** | `GPU_ATTACH_IDS : gpu=0x100 status=0 ...`, обидва `NV_ESC_RM_ALLOC` з `status=0` |
| 7 | `MC_GET_ARCH_INFO` (`0x20801701`) повертає `arch=0x130 impl=0x7 rev=0xa1 subrev=0x2` | **runtime-proven** | маркер `NV2080_CTRL_MC_GET_ARCH_INFO` у `03_rm_arch_info.pas`; раніше звірено з libcuda-shimом |
| 8 | `0x130` → GP100-родина, `0x7` → GP107 | **interpretation** |Публічні імена констант; це не читання апаратного регістру |
| 9 | `0x137000A1` як «BOOT0» | **string-only** | рядок у libdrm `cl0080.h`; на цій машині регістр не читався |
| 10 | Збіг `rev=0xa1` із молодшим байтом `0x137000A1` | **interpretation** | не є доказом BOOT0; статус лишається UNPROVEN |
| 11 | `resource0 open` звичайним користувачем → `EACCES`, `mmap` не виконувався | **runtime-proven** | `BAR0-STATE: OPEN_DENIED`, `BOOT0: UNPROVEN (open denied; MMIO not attempted)` |
| 12 | Root `open(resource0)` OK → `mmap(PROT_READ\|MAP_SHARED)` → `EINVAL` | **runtime-proven в earlier-сесії** | опційний `scripts/test-root-witness.sh`; у поточній сесії `sudo -n` недоступний, базовий гейт його не вимагає |
| 13 | Причина `EINVAL` — ексклюзивне володіння BAR0 драйвером | **UNPROVEN / interpretation** | програма друкує `MMAP-DENIAL-CAUSE: UNPROVEN (errno alone proves no cause)` |
| 14 | `EACCES` на `resource0` доводить ексклюзивне володіння BAR0 | **UNPROVEN** | гейт забороняє перетворювати `EACCES` на твердження про власника |
| 15 | Явний `NV_ESC_RM_FREE` з `NVOS00` звільняє subdevice → device → client з `status=0` | **runtime-proven** | `RM-FREE-OK ... status=0` ×3, `RM-CLEANUP-COMPLETE objects=3`, порядок перевіряється фірволом |
| 16 | Cleanup після часткової відмови звільняє 1/2/3 обʼєкти | **runtime-proven через інʼєкцію** | `WSM_RM_FAIL_STEP=after_alloc_client\|after_alloc_device\|after_alloc_subdev` → exit 2, `RM-CLEANUP-COMPLETE objects=1\|2\|3` |
| 17 | Закриття fd само по собі звільняє всі RM-обʼєкти | **UNPROVEN, не стверджується** | у зонді є явний `RM_FREE`; причина будь-якого RM-статусу не досліджувалася |
| 18 | `devpars.device_id = 0` є PCI device id `0x1c82` | **UNPROVEN / хибне ототожнення** | значення `0` збережено; семантика окремо не підтверджена |
| 19 | Усі три бінарники — STATIC ELF, без `PT_INTERP`, `.dynamic`, `PT_DYNAMIC`, `DT_NEEDED` | **statically proven, ELF** | `BINARY-PROOF-OK elf-static=yes no-dynamic-deps=yes libc-dynamic=no` |
| 20 | Бінарники не залежать від libc | **statically proven на рівні артефакта** | немає `libc.so`, `GLIBC_*`, `__libc_start_main` у символах/тілі; FPC RTL лишається |
| 21 | Несумісний хост не видає зелений результат | **runtime-proven negative** | `FPC_EXPECTED=9.9.9` → `PASCAL-PROBE-UNSUPPORTED reason=fpc-version=3.2.2 expected=9.9.9`, exit 3 |
| 22 | Command submission / pushbuffer / channel / context init / GPU sync | **UNPROVEN** | у цьому спринті не реалізовано й не вимірювалося |
| 23 | MMIO-мапа BAR0, DMA/GVA, doorbell, kernel launch | **UNPROVEN** | Немає жодного успішного read-only мапінгу, жодного writable шляху |
| 24 | Display / GOP / framebuffer у Lisp-машині | **UNPROVEN, поза межею** | hosted DRM і compute-канал не ототожнюються |
| 25 | Bare-metal/UEFI пряме читання BOOT0 | **UNPROVEN** | належить окремому seam; тут активний `nvidia.ko` |
| 26 | Перенесення `PciConfig`/`Mmio`/`RmControl` у `wsm-os-lisp` | **UNPROVEN, не авторизовано** | ABI-pin v8 і v9 не змінювалися; потрібне owner-рішення |
| 27 | `valid_cards == 1` перед RM-алокацією | **source guard CI PASS; FPC 3.2.2 compile pending; multi-GPU runtime negative NOT_RUN** | static guard + mutation-negative пройшли в [run #46078211864](https://github.com/juv4uk/gp107-nvidia-re/actions/runs/46078211864); новий hardware-free workflow додатково компілює Pascal-пробники з FPC 3.2.2, але цей результат очікується окремо; workflow не запускає їх і не доводить multi-GPU runtime fixture; кореляцію `PCI BDF ↔ RM gpu_id` не доведено |

## Що реально дає репозиторій

1. **Доведено й відтворювано**: ідентичність картки, параметри RM,
   архітектурні константи через RM, явний lifecycle RM-обʼєктів,
   fail-closed BAR0-negative, статичні бінарники без libc-залежності.
2. **Не дає**: прямого доступу до регістрів, дозволу на запис у BAR0,
   доведення причини відмов ядра, робочого compute-конвеєра або будь-якої
   системної ABI-зміни.
3. **Не авторизує**: оновлення target-ABI pin, прийняття `0x137000A1`
   як факт, заміну ADR або перехід FPC-зондів у нову основу Lisp-машини.

## Точні команди перевірки

```bash
cd /home/agents/GitHub/gp107-nvidia-re
bash -n scripts/test-pascal-probe.sh
bash scripts/test-pascal-probe.sh
```

Очікувані ключові маркери останнього прогону:

```text
HOST-PROFILE-OK bdf=0000:01:00.0 driver=580.196.11 block=8000000 bar0=0x00000000ee000000
BAR0-STATE: OPEN_DENIED
BOOT0: UNPROVEN (open denied; MMIO not attempted)
RM-CLEANUP-COMPLETE objects=3
RM-ARCH-OK
BINARY-PROOF-OK elf-static=yes no-dynamic-deps=yes libc-dynamic=no
PASCAL-PROBE-GATE-OK fpc=3.2.2 static=yes no-libc=yes gpu=10de:1c82 bar0=fail-closed rmarch=runtime-proven boot0=unproven
```

Негативні перевірки:

```bash
FPC_EXPECTED=9.9.9 bash scripts/test-pascal-probe.sh
# exit 3; PASCAL-PROBE-UNSUPPORTED reason=fpc-version=3.2.2 expected=9.9.9

for s in after_alloc_client after_alloc_device after_alloc_subdev; do
  WSM_RM_FAIL_STEP=$s ./pascal/03_rm_arch_info
done
# exit 2; RM-CLEANUP-COMPLETE objects=1 / 2 / 3

sudo -n bash scripts/test-root-witness.sh
# тільки якщо sudo доступний; MMAP_DENIED/EINVAL, причина UNPROVEN
```

## Відповідальні коміти цього спринту

- `841fa3c` — розділення `OPEN_DENIED` і `MMAP_DENIED`; EACCES не стверджує власника BAR0.
- `ff74ac8` — шлях `/dev/nvidia<N>` з `NV_ESC_CARD_INFO`, унікальний GP107.
- `7a2317f` — явний `NV_ESC_RM_FREE`, зворотний порядок, partial-failure cleanup.
- `81b1e7b` — окремі ELF-докази та `PASCAL-PROBE-UNSUPPORTED` для несумісного хоста.

Попередня база: `2c2b746` — власний FPC RM arch-info звірений із libcuda-shimом.
