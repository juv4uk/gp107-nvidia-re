# 12 — Шаблон witness для одноразового boot на Nouveau/NVK

**Статус шаблону: `TEMPLATE / NOT_RUN`.** Цей документ не є звітом про boot.
Заповнюється **після** реальної сесії, коли користувач самостійно виконав
rollback-capable boot і повернув логи. Агент не змінює boot, драйвер, firmware,
`/etc/modprobe.d` чи `update-initramfs`, і не запускає PR #21 executable.

## 1. Передумови, які мають бути зафіксовані в `/proc/cmdline`

```text
modprobe.blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm
blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm
nouveau.debug=TOP=trace,FIFO=debug
```

`CONFIG_NOUVEAU_DEBUG >= 5` — попередньо перевірено на `7.2.15+kali-amd64`.
Якщо цих рядків немає, сесія **не кваліфікується** як trace-witness.

### Чому недостатньо самого `modprobe.blacklist=nvidia...`

Read-only інспекція показала, що `/etc/modprobe.d/nvidia-blacklists-nouveau.conf`
і `/etc/modprobe.d/nvidia.conf` містять `blacklist nouveau`. Тому блокування
nvidia не змушує nouveau завантажитися автоматично — обидва драйвери
лишаться у чорному списку. Вихід без торкання `/etc/modprobe.d`:

1. окремий пункт GRUB із маркером `wsm_open_driver=1` + blacklist nvidia;
2. умовний systemd-юніт, який робить **явний** `modprobe nouveau` тільки за
   наявності цього маркера (`ConditionKernelCommandLine=wsm_open_driver=1`).
   Explicit `modprobe` обходить `blacklist`; `modprobe -n -v nouveau` це
   підтверджує. На звичайному boot (NVIDIA) умова хибна — юніт нічого не робить.

Встановлення (виконує користувач, у якого є root):

```bash
DRY_RUN=1 bash scripts/install-grub-open-driver-choice.sh   # перегляд, без root
sudo bash scripts/install-grub-open-driver-choice.sh        # створить бекапи, update-grub
```

`GRUB_DEFAULT=0` не змінюється: nvidia лишається першим пунктом; новий пункт
додається в кінці через `/etc/grub.d/40_custom`. Скрипт не викликає
`update-initramfs` і не редагує `/etc/modprobe.d`.

## 2. Одноразовий збір

```bash
bash scripts/capture-nouveau-boot-witness.sh
# або: BOOT_OUT=/tmp/opencode/nouveau-witness bash scripts/capture-nouveau-boot-witness.sh
```

Скрипт читає-only: `lspci`, `lsmod`, `/proc/cmdline`, `journalctl -b -k`,
`sysfs`, `vulkaninfo --summary` з `VK_ICD_FILENAMES=nouveau_icd.json`, і
`strace -e trace=ioctl` **на vulkaninfo**, не на PR #21. Він не відкриває
`resource0`, не робить mmap і не виконує MMIO-записів. Вихід — каталог із
`99-manifest.txt` (SHA-256 кожного файлу) і рядком
`NOUVEAU-WITNESS-CAPTURE-OK ... boot0=unproven pr21=not-run`.

## 3. Evidence-леджер (заповнюється з маніфесту)

| Witness-ID | Файл | Classification | Marker, який шукаємо | Результат |
|---|---|---|---|---|
| `W1:BOOT-CMDLINE` | `01-cmdline.txt` | `runtime-proven` | `nouveau.debug=TOP=trace,FIFO=debug` + blacklist | `TODO` |
| `W2:PCI-IDENTITY` | `02-lspci.txt` | `runtime-proven` | `0000:01:00.0 10de:1c82`, `Kernel driver in use: nouveau` | `TODO` |
| `W3:NVIDIA-MODULES-ABSENT` | `03-lsmod.txt` | `runtime-proven negative` | жодного `^nvidia(_uvm\|_drm\|_modeset\|_peermem)?` | `TODO` |
| `W4:KERNEL-LOG` | `04/05-*-log.txt` | `runtime-proven` | рядки `nouveau` з нової сесії | `TODO` |
| `W5:DEBUGFS` | `06-debugfs.*` | `runtime-proven / best-effort` | доступні файли; `DENIED` не є відсутністю | `TODO` |
| `W6:MMIO-DEFERRED` | `07/08-*` | `UNPROVEN` | `BOOT0: UNPROVEN`, `MMIO-RIGHT: none` | `TODO` |
| `W7:NVK-DRIVER-ID` | `09-vulkaninfo.txt` | `runtime-proven` | `DRIVER_ID_MESA_NVK`, відсутні `NVIDIA_PROPRIETARY`/`llvmpipe` | `TODO` |
| `W8:IOCTL-TRACE` | `10/11-*-ioctl.txt` | `runtime-proven` (після звірки номерів з headers) | DRM ioctl-номери; **назви не стверджуємо без перевірки** | `TODO` |

Кожен рядок доповнюється `SHA-256` з `99-manifest.txt`.

### Про REA Evidence-ID

REA-ідентифікатори (`ev_<64 hex>`) видаються **аналізом артефактів**, а не
текстовими логами. Тому в цьому леджері для логів використовуються локальні
`W*-ID` + SHA-256. REA-ID додається окремо лише якщо ми повторно аналізуємо
якийсь двійковий артефакт (наприклад, `libvulkan_nouveau.so`) і отримуємо
Evidence від REA. Не підміняти `W*-ID` під REA-ID.

## 4. Кваліфікація фактів з doc 09

Після заповнення леджера окремо позначаємо:

| Маркер | Що має бути в логах | Стан |
|---|---|---|
| `TOP_GR_RUNLIST_OBSERVED` | trace `/TMGR`/`GR` з runlist- ідентифікатором | `TODO` |
| `CHANNEL_RUNLIST_CORRELATED` | канал і його runlist у debugfs/trace зіставлені | `TODO` |
| `NONSTALL_EVENT_SUBSCRIPTION_OBSERVED` | `nvkm_event_ntfy_add()` → `nvif_event_allow()` у trace | `TODO` |
| `RUNLIST_ID_NONZERO_OBSERVED` | ненульовий `RUNLIST_ID` у trace | `TODO` |
| `BOARD_RUNTIME_UNPROVEN` | якщо будь-який маркер вище відсутній | `TODO` |

Порожній trace **не** означає «маркера немає в драйвері» — це `UNPROVEN` за
наявного логу.

## 5. Межі, які зберігаються навіть після успішного boot

- `BOOT0` лишається `UNPROVEN`, доки не зроблено окремий readout із явним
  звʼязком `PCI BDF ↔ RM gpu_id`.
- `0x137000A1` — `string-only`, не стає runtime-фактом автоматично.
- Відсутність GSP-прошивки для Pascal у `nvidia.ko` — `interpretation`
  (стативно proven лише те, що в `.modinfo` є тільки `gsp_tu10x`/`gsp_ga10x`).
- «Підміна ICD JSON-маніфесту без зміни логіки резолву» — `interpretation`,
  поки `W7` не покаже `DRIVER_ID_MESA_NVK` для саме `10de:1c82`.
- Жодного `Tested-by`, release/tag чи transfer; жодного пушу без owner-дії.

## 6. Критерій закриття

```text
NOUVEAU-BOOT-WITNESS-OK  вимагає одночасно:
  W2=nouveau  AND  W3=absent  AND  W7=DRIVER_ID_MESA_NVK
  AND  BOOT0=UNPROVEN  AND  pr21-executable=NOT-RUN
```

Якщо виконується лише частина — пишемо
`NOUVEAU-BOOT-WITNESS-PARTIAL` і лишаємо `PHYSICAL_GPU_TEST=NOT_RUN`.
