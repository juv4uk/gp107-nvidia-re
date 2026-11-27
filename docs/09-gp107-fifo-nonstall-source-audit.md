# 09 — GP107 FIFO non-stall: source audit і read-only trace plan

Цей документ продовжує [issue #18](https://github.com/juv4uk/gp107-nvidia-re/issues/18).
Він **не** стверджує помилку на нашій платі й не є hardware witness.
Поточний стан: `SOURCE_CONFIRMED_CONDITIONAL / GP107_RUNLIST_ID_NOT_OBSERVED / BOARD_RUNTIME_UNPROVEN`.

Pinned source: Linux `gregkh/linux` `linux-7.3.y`, зріз перевірено 2026-11-27.
Посилання нижче — на public kernel source, не на vendor source й не на Ghidra-псевдокод.

## 1. Що вже доведено з source (`statically proven, source`)

| Факт | Файл | Що саме |
|---|---|---|
| GP107 (`nv137_chipset`) обирає `gp100_fifo_new()` і `gk104_top_new()` | `drivers/gpu/drm/nouveau/nvkm/engine/device/base.c` | chipset dispatch |
| `gp100_fifo` задає `.nonstall = &gf100_fifo_nonstall`, але не має `nonstall_ctor` | `drivers/gpu/drm/nouveau/nvkm/engine/fifo/gp100.c` | умова для `index_nr = 1` |
| `nvkm_fifo_oneinit()` ставить `ret = 1` і викликає `nvkm_event_init(..., index_nr = 1, ...)` | `drivers/gpu/drm/nouveau/nvkm/engine/fifo/base.c` | event має лише один index |
| `nvkm_uchan_uevent()` для `NVIF_CHAN_EVENT_V0_NON_STALL_INTR` викликає `nvkm_uevent_add(..., &runl->fifo->nonstall.event, runl->id, ...)` | `drivers/gpu/drm/nouveau/nvkm/engine/fifo/uchan.c` | індекс береться з `runl->id`, а не з `0` |
| `nvkm_event_get()` / `nvkm_event_put()` індексують `refs[index * types_nr + type]` без локальної межової перевірки | `drivers/gpu/drm/nouveau/nvkm/core/event.c` | шлях підписки/відписки не захищений `nvkm_event_ntfy()` |
| `gk104_top_parse()` читає hardware TOP table і заповнює `info->runlist` з `ENUM` слова | `drivers/gpu/drm/nouveau/nvkm/subdev/top/gk104.c` | runtime ID надходить з TOP table |
| `gk104_fifo_runl_ctor()` створює runlists за `tdev->runlist` | `drivers/gpu/drm/nouveau/nvkm/engine/fifo/gk104.c` | `runl->id == tdev->runlist` |
| `nouveau_channel_ctor()` ставить `args->runlist = __ffs64(runm)`; `nvkm_uchan_new()` шукає `nvkm_runl_get(fifo, args->v0.runlist, 0)` | `drivers/gpu/drm/nouveau/nouveau_chan.c`, `nvkm/engine/fifo/uchan.c` | канал користувача прив'язаний до конкретного runlist ID |

Висновок із source: **якщо** канал, який підписується на non-stall interrupt, має
`runl->id != 0`, індекс event може вийти за межі одноелементного масиву.
Це умовний source lead, не доведена поведінка плати.

## 2. Чому logging може дати ID без direct MMIO

`gk104_top_parse()` друкує:

- `nvkm_trace(subdev, "%02x: %08x\n", i, data)` — сирі слова TOP table;
- `nvkm_debug(subdev, "%02x.%d (%8s): addr ... engine %2d runlist %2d intr %2d reset %2d\n", ...)` —
  розібрані записи з `runlist`.

`nvkm_debug` у `include/nvkm/core/subdev.h` використовує `dev_info`, а не dynamic debug:
умова — `CONFIG_NOUVEAU_DEBUG >= NV_DBG_DEBUG (4)` і level для subdev `top`.
За замовчуванням `CONFIG_NOUVEAU_DEBUG=5`, `CONFIG_NOUVEAU_DEBUG_DEFAULT=3`
(`drivers/gpu/drm/nouveau/Kconfig`), тобто `nouveau.debug=TOP=debug` достатньо для
розібраних рядків, а `TOP=trace` додає сирі слова. Важливо: `trace` вимагає
compile-time стелі `CONFIG_NOUVEAU_DEBUG >= 5`; це треба перевірити в конфігурації
саме цільового ядра, а не лише в upstream default. `nvkm_dbgopt()` у
`nvkm/core/option.c` порівнює назви без регістру; subdev name для TOP — `top`
з `nvkm/core/layout.h`. Вузький варіант `TOP=trace` є кращим за глобальне
`nouveau.debug=trace`, бо не піднімає level для всіх NVKM subdev-ів.

`RUNL_DEBUG()` у `nvkm/engine/fifo/runl.h` друкує через `fifo` subdev рядки
виду `fifo: 000000NN: ...`. Для них потрібен `nouveau.debug=PFIFO=debug`.
`RUNL_TRACE()` додає `running`/`stopped`.

Це читання вже існуючого kernel-logging шляху. Ми не викликаємо `nva`, не
читаємо BAR0/MMIO напряму, не пишемо регістри й не змінюємо firmware.

## 3. Точний read-only план на фізичній GP107 (поки `NOT_RUN`)

Передумова: окремий test boot із збереженим rollback; робоча система не
переводиться на експериментальний модуль автоматично.

1. Перевірити зібраний level і параметри модуля:

   ```bash
   uname -r
   grep -E 'CONFIG_NOUVEAU_DEBUG(=|_DEFAULT)' /boot/config-"$(uname -r)"
   modinfo nouveau | grep -E '^(parm|description):.*(debug|config)'
   lspci -vv -d 10de:1c82 | sed -n '1,40p'
   cat /sys/bus/pci/devices/0000:01:00.0/vendor
   cat /sys/bus/pci/devices/0000:01:00.0/device
   ```

   Очікуваний BDF тут лише приклад із нашого однокарткового witness;
   для іншого хоста BDF треба взяти з `lspci`, не підставляти.

2. У test boot передати module option (не kernel command line, якщо `nouveau` — модуль):

   ```bash
   # лише після перевірки CONFIG_NOUVEAU_DEBUG >= 5 у цільовому ядрі
   printf 'options nouveau debug=TOP=trace,PFIFO=debug\n' \
     | sudo tee /etc/modprobe.d/gp107-fifo-trace.conf
   sudo update-initramfs -u
   sudo reboot
   ```

3. Після завантаження з Nouveau зібрати лог:

   ```bash
   dmesg -T | grep -E 'nouveau .*(top|fifo):' > /tmp/opencode/gp107-top-fifo.log
   ```

   Шукати в `gp107-top-fifo.log`:

   ```text
   top: ... engine  0 runlist  0 ...   # GR на runlist 0 — умова не активна
   top: ... engine  0 runlist  1 ...   # GR на nonzero — умова активна, але event subscription ще треба довести
   fifo: 00000001: ...                  # RUNL_DEBUG для runlist 1
   ```

   Кожен рядок зберегти разом із kernel version, BDF, `modinfo` і часом boot.

4. Порядок кваліфікації witness:

   - `RUNLIST_ID_NOT_OBSERVED`, якщо розібраного `runlist` рядка немає;
   - `RUNLIST_ID_ZERO`, якщо GR/compute має `runlist 0`;
   - `RUNLIST_ID_NONZERO_OBSERVED`, лише якщо є рядок із конкретним ID;
   - окремо `NONSTALL_EVENT_SUBSCRIPTION_OBSERVED` — поки `NOT_OBSERVED`;
   - жодного `Tested-by` від агента/LLM.

## 4. Поточний стан на цій hosted-машині

| Перевірка | Результат | Стан |
|---|---|---|
| `vulkaninfo --summary` бачить `10de:1c82` | `NVIDIA GeForce GTX 1050 Ti`, `driverID = DRIVER_ID_NVIDIA_PROPRIETARY`, driverInfo `580.196.11` | `runtime-proven`, proprietary ICD |
| NVK як ICD для цієї плати | у списку device лише proprietary NVIDIA + llvmpipe CPU | `NOT_RUN/UNPROVEN` |
| nouveau debug log | не збиралось; GPU під `nvidia.ko` | `NOT_RUN` |
| TOP runlist IDs | не спостерігались | `RUNLIST_ID_NOT_OBSERVED` |
| non-stall event subscription | не спостерігалась | `NOT_OBSERVED` |
| patch 2/2 у mainline/stable | у pinned snapshot `uchan.c` досі `runl->id`; merged-стан окремого backport не доведений | `source-only` |

Мінімальний compute harness для подальшого NVK witness ведеться окремо в
[Draft PR #21](https://github.com/juv4uk/gp107-nvidia-re/pull/21) і тут не
дублюється. Його build/CI перевірено без GPU; dispatch/readback на цій платі
не виконувався.

## 5. Межі

- Не робити MMIO/BAR writes, `nva`, кастомний reset, VBIOS/firmware flash.
- Не додавати patch 1 (Kepler legacy video) до GP107 без окремого обґрунтування.
- Не називати `vkcube`/графічний Vulkan compute witness.
- Не переносити цей source audit у SENS/CML/wsm-os-lisp і не міняти ABI-pin.
- Не змінювати системний driver, конфігурацію хоста або завантаження без owner-дії.
