# 13 — Результат boot-свідка Nouveau/NVK (2026-11-27)

**Статус: `BOOT-WITNESS-CAPTURED / NVK-ENUMERATION-RUNTIME-PROVEN`.**
Це не звіт про compute-навантаження й не `Tested-by`. Вибір пункту GRUB і
перезавантаження виконав користувач; агент лише зняв read-only свідки.

## 1. Provenance

- Boot виконано користувачем у пункт `WSM open driver: nouveau + NVK trace`.
- `/proc/cmdline` містить `wsm_open_driver=1`,
  `modprobe.blacklist=nvidia,...`, `blacklist=nvidia,...`,
  `nouveau.debug=TOP=trace,FIFO=debug`.
- Збір: `2026-11-27T05:11:32Z`, ядро `7.2.15+kali-amd64`.
- `/tmp` було очищено reboot; worktree відновлено з об’єктів основного репо
  `/home/agents/GitHub/gp107-nvidia-re` у `/home/agents/open-driver-identity`.
- Логи скопійовано в `evidence/nouveau-20261127/`; хеші — у
  `99-repo-manifest.txt` (відносні шляхи) і `99-manifest.txt` (оригінальні
  абсолютні шляхи зняття).

## 2. Леджер W1–W8

| ID | Файл | SHA-256 (перші 12) | Стан |
|---|---|---|---|
| `W1:BOOT-CMDLINE` | `01-cmdline.txt` | `0c6bfced87d4` | `runtime-proven` |
| `W2:PCI-IDENTITY` | `02-lspci.txt` | `6cd6ac6518eb` | `runtime-proven` |
| `W3:NVIDIA-MODULES-ABSENT` | `03-lsmod.txt` | `bf6f1d2a9a77` | `runtime-proven negative` |
| `W4:KERNEL-LOG` | `04-kernel-log.txt` | `751e8386f4f7` | `runtime-proven` |
| `W5:DEBUGFS` | `06-debugfs-files.txt` | `7093c1611fc4` | `best-effort / unavailable` |
| `W6:MMIO-DEFERRED` | `08-mmio.txt` | `faf3ee2af8e0` | `UNPROVEN` (свідомо) |
| `W7:NVK-DRIVER-ID` | `09-vulkaninfo.txt` | `2a0900d13017` | `runtime-proven` |
| `W8:IOCTL-TRACE` | `11-drm-ioctl.txt` | `edf849caaa67` | `runtime-proven` (з іменами strace) |

## 3. Ключові runtime-факти

### 3.1 Залізо й драйвер

```text
0000:01:00.0 ... [10de:1c82]
Kernel driver in use: nouveau
Kernel modules: nouveau, nvidia_drm, nvidia
```

`lsmod` у момент зняття: жодного рядка `nvidia`, `nvidia_uvm`, `nvidia_drm`,
`nvidia_modeset`. `nvidia*` лишається в `Kernel modules` як **можливість**, а не
як активний драйвер.

### 3.2 NVK саме на GP107

```text
GPU0:
    vendorID    = 0x10de
    deviceName  = NVIDIA GeForce GTX 1050 Ti (NVK GP107)
    driverID    = DRIVER_ID_MESA_NVK
    driverName  = NVK
    apiVersion  = 1.3.354
    driverVersion = 26.1.6
```

`NVIDIA_PROPRIETARY`, `llvmpipe`, `softpipe` у висновку **відсутні**. Отже
`interpretation` з doc 11 про «чисту підміну ICD» тепер має runtime-підтвердження
для саме `10de:1c82`: NVK підхопив фізичний пристрій.

### 3.3 DRM-шлях замість RM

`strace -e trace=ioctl` на `vulkaninfo --summary` (не на PR #21) показав,
зокрема:

```text
ioctl(3, DRM_IOCTL_NOUVEAU_CHANNEL_ALLOC, ...) = 0
ioctl(3, DRM_IOCTL_NOUVEAU_CHANNEL_FREE, ...)  = 0
ioctl(3, DRM_IOCTL_SYNCOBJ_CREATE, ...)       = 0
ioctl(3, DRM_IOCTL_GET_CAP, ...)              = 0
```

Це прямий runtime-контраст до пропрієтарного RM-шляху з doc 11. Деякі рядки
`GET_PARAM` у strace мають розмитий список аліасів — для них конкретну назву
**не стверджуємо**.

### 3.4 TOP/FIFO trace

```text
top: 00.0 (      gr): addr 400000 ... runlist  0 ...
top: 13.2 (      ce): addr 104000 ... runlist  5 ...
fifo:000000:00[      gr]:
fifo:000005:05[     ce2]:
fifo:000000:00[      gr]: 10031003: busy 0 faulted 0 chsw 0 save 0 load 0 tsgid 3 -> tsgid 3
```

Поле `fault` у цих рядках — частина TOP-trace, а не помилка збірки. GR у
стартовому trace має `runlist 0`; ненульові runlist-и спостережено для
CE/NVDEC/NVENC/SEC2.

### 3.5 Спроба пропрієтарного модуля

У kernel log є три спроби `nvidia-nvlink` завантажитися о `07:10:43–07:10:50`,
кожна закінчилась `NVRM: No NVIDIA devices probed` і `Unregistered Nvlink Core`.
Поточний `lsmod` чистий. `interpretation`: пропрієтарний стек не зміг забрати
плату в Nouveau; це **не** означає, що `nvidia.ko` видалено з системи.

### 3.6 `137000a1`

```text
nouveau 0000:01:00.0: NVIDIA GP107 (137000a1)
```

Це `runtime-proven kernel-log string`, а **не** вичитка регістра `BOOT0`.
`BOOT0` лишається `UNPROVEN`; `0x137000A1` не підвищується до MMIO-факту.

## 4. Кваліфікація маркерів doc 09

| Маркер | Стан | Підстава |
|---|---|---|
| `TOP_GR_RUNLIST_OBSERVED` | `runtime-proven` | `top: 00.0 (gr): ... runlist 0` |
| `RUNLIST_ID_NONZERO_OBSERVED` | `runtime-proven` | `runlist 5` (ce), `1/2/3/4/6` для інших двигунів |
| `CHANNEL_RUNLIST_CORRELATED` | `PARTIAL / UNPROVEN` | FIFO показує `fifo:000005:05[ce2]` і GR `tsgid 3`, але явного зв’язку з конкретним користувацьким каналом із strace немає |
| `NONSTALL_EVENT_SUBSCRIPTION_OBSERVED` | `UNPROVEN` | у логах немає рядків `event`/`ntfy`; порожній результат не є відсутністю в драйвері |
| `BOARD_RUNTIME_UNPROVEN` | `false` для identity/enumeration | NVK + nouveau на реальній платі спостережено |
| `BOOT0` | `UNPROVEN` | навмисно не читався |

## 5. Межа головної мети

`runtime-proven`: на лісп-машині GPU `10de:1c82` працює з відкритим стеком на
рівні **ідентифікації та Vulkan-енумерації** — nouveau тримає драйвер, NVK
віддає фізичний пристрій, DRM-канал реально алокується без пропрієтарного ICD.

`NOT_RUN`: власне обчислювальний workload (vector-add через `vkCmdDispatch`,
fence, host readback, CPU checksum), який і визначає «продуктивно працює».
Тому остаточну мету **`PHYSICAL_COMPUTE_TEST=NOT_RUN`** не знято. Наступний
крок — NVK vector-add harness, не ще один REA-прохід.

## 6. Заборони, що збереглись

- Жодного MMIO-read/write, `nva`, custom reset, `/dev/nvidia*`.
- PR #21 executable не запускався.
- Жодного `Tested-by`, release/tag, пушу чи transfer без owner-дії.
- Конфігурація `/etc/modprobe.d`, firmware й ABI-pin не змінювались цією сесією.
