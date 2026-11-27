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
виду `fifo: 000000NN: ...`. Для них потрібен `nouveau.debug=FIFO=debug`.
`RUNL_TRACE()` додає `running`/`stopped`.

### Імена debug-subdevice: перевірено по parser path

`nvkm_subdev_type[]` у `nvkm/core/subdev.c` генерується через `#ptr` із `include/nvkm/core/layout.h`. Для `NVKM_ENGINE_FIFO` останній аргумент — `fifo`, а `__nvkm_subdev_ctor()` записує це ім'я в `subdev->name`; `nvkm_dbgopt()` порівнює selector саме з цим ім'ям без урахування регістру. Тому правильний selector — **`FIFO=debug`**, не `PFIFO=debug`.

У тому самому `layout.h` немає subdevice з ім'ям `client`; `CLIENT=debug` не вибирає окремий NVKM context і не вмикає client logging. Тому не додавати його як нібито дієвий прапорець.

`nvkm_fifo_oneinit()` створює `nonstall.event` із `&fifo->engine.subdev`, тобто trace-події `nvkm_event_*` також ідуть через `fifo`. `nvkm_event_ntfy_add()`, `nvkm_event_get()` і `nvkm_event_put()` мають `nvkm_trace()` записи (`event: ntfy add`, `event: incr/decr`). Якщо першого проходу `FIFO=debug` недостатньо, можливий **окремий, більш гучний** rollback boot із `nouveau.debug=TOP=trace,FIFO=trace` для збору цих event-level повідомлень.

Важливе обмеження: `event: ntfy add` сам по собі показує event ID/bits та runlist index, але не ідентифікує `struct nvkm_chan`. Тому навіть `FIFO=trace` не є автоматичним доказом, що саме GR/compute user channel підписався на `NVIF_CHAN_EVENT_V0_NON_STALL_INTR`. Для такого висновку потрібен окремий channel-level witness на `nvkm_uchan_uevent()` (тип події + `runl->id` + ідентичність каналу/групи) — лише після перевірки доступності символу/BTF/kprobe/fentry у цільовому kernel або підготовки вузької trace-only instrumentation. До цього не запускати workload чи patch test.

Це читання вже існуючого kernel-logging шляху. Ми не викликаємо `nva`, не
читаємо BAR0/MMIO напряму, не пишемо регістри й не змінюємо firmware.

## 3. Точний read-only план на фізичній GP107 (поки `NOT_RUN`)

Передумова: окремий test boot із збереженим rollback; робоча система не
переводиться на експериментальний модуль автоматично.

1. Перевірити зібраний level і параметри модуля:

   ```bash
   set -eu
   KREL=$(uname -r)
   printf 'KERNEL=%s\n' "$KREL"
   if [ -r "/boot/config-$KREL" ]; then
     CONFIG_LINE=$(grep '^CONFIG_NOUVEAU_DEBUG=' "/boot/config-$KREL" || true)
   elif [ -r /proc/config.gz ]; then
     CONFIG_LINE=$(zcat /proc/config.gz | grep '^CONFIG_NOUVEAU_DEBUG=' || true)
   else
     echo 'KERNEL_CONFIG_UNAVAILABLE'; exit 2
   fi
   [ -n "$CONFIG_LINE" ] || { echo 'CONFIG_NOUVEAU_DEBUG_UNSET'; exit 2; }
   DEBUG_LEVEL=${CONFIG_LINE#*=}
   case "$DEBUG_LEVEL" in ''|*[!0-9]*) echo 'CONFIG_NOUVEAU_DEBUG_INVALID'; exit 2 ;; esac
   [ "$DEBUG_LEVEL" -ge 5 ] || { echo "CONFIG_NOUVEAU_DEBUG_TOO_LOW=$DEBUG_LEVEL"; exit 2; }
   printf 'CONFIG_NOUVEAU_DEBUG=%s\n' "$DEBUG_LEVEL"
   modinfo -p nouveau | grep '^debug:' || { echo 'NOUVEAU_DEBUG_PARAMETER_UNAVAILABLE'; exit 2; }
   BDFS=$(lspci -Dnn -d 10de:1c82 | awk '{print $1}')
   COUNT=$(printf '%s\n' "$BDFS" | sed '/^$/d' | wc -l)
   [ "$COUNT" -eq 1 ] || { echo "GP107_BDF_COUNT=$COUNT"; exit 2; }
   BDF=$(printf '%s\n' "$BDFS" | sed -n '1p')
   SYSFS="/sys/bus/pci/devices/$BDF"
   [ -r "$SYSFS/vendor" ] && [ -r "$SYSFS/device" ] || { echo 'GP107_SYSFS_IDENTITY_UNAVAILABLE'; exit 2; }
   printf 'GP107_BDF=%s vendor=%s device=%s\n' "$BDF" "$(cat "$SYSFS/vendor")" "$(cat "$SYSFS/device")"
   lspci -Dnnk -s "$BDF"
   ```
   Preflight сам fail-closed перевіряє compile-time ceiling `CONFIG_NOUVEAU_DEBUG >= 5`, параметр `debug` і рівно один PCI `10de:1c82`. Якщо знайдено нуль або більше однієї такої карти — зупинитися та не вгадувати BDF.

2. У **одноразовому** test boot передати параметр модулю через тимчасовий boot entry:

   ```text
   nouveau.debug=TOP=trace,FIFO=debug
   ```

   Наприклад, у меню GRUB відредагувати лише поточний запис клавішею `e`,
   додати параметр до рядка `linux` і завантажити цей запис через Ctrl+X/F10.
   Це діє лише для поточного boot. Не створювати постійний файл
   `/etc/modprobe.d`, не виконувати `update-initramfs` і не змінювати
   основний boot entry. Перед цим перевірити `modinfo nouveau` та
   `CONFIG_NOUVEAU_DEBUG >= 5` саме для обраного kernel. Зберегти окремий
   rollback entry; proprietary NVIDIA driver не повинен одночасно володіти GPU.
3. Після завантаження з Nouveau зібрати лог:

   ```bash
   OUT="$HOME/gp107-trace-$BDF-$(date +%Y%m%d-%H%M%S)"
   mkdir -p "$OUT"
   uname -a > "$OUT/uname.txt"
   cat /proc/cmdline > "$OUT/cmdline.txt"
   lspci -Dnnk -s "$BDF" > "$OUT/lspci.txt"
   modinfo -p nouveau > "$OUT/nouveau-module-params.txt"
   if [ -r "/boot/config-$(uname -r)" ]; then
     cp "/boot/config-$(uname -r)" "$OUT/kernel.config"
   elif [ -r /proc/config.gz ]; then
     zcat /proc/config.gz > "$OUT/kernel.config"
   fi
   sudo journalctl -b -k -o short-monotonic --no-pager > "$OUT/kernel.log"
   grep -Ei 'nouveau.*(top:|fifo:|event:)|runlist|nvkm' "$OUT/kernel.log" > "$OUT/relevant-lines.log" || true
   printf 'EVIDENCE_DIR=%s\n' "$OUT"
   ```

   Зберігати `kernel.log` повністю; `relevant-lines.log` — лише індекс для читання, не заміна оригіналу. У першому проході очікувані TOP/FIFO записи; `CLIENT`-рядки не очікуються, бо в NVKM layout немає CLIENT subdevice.

   Шукати decoded записи у `relevant-lines.log`, але всі висновки звіряти з повним `kernel.log`:

   ```text
   nouveau ...: top: ... engine  0 runlist N ...  # лише TOP inventory
   nouveau ...: fifo: ...                       # RUNL_DEBUG / FIFO context
   nouveau ...: fifo: event: ntfy add ...       # можливий event-level рядок лише з FIFO=trace
   ```

   TOP row — інвентаризація engine/runlist, а не доказ прив'язки конкретного user channel чи non-stall subscription. Не трактувати `N=0` або `N!=0` як channel verdict без окремої кореляції. Зберегти повний `kernel.log`, kernel config, BDF, `modinfo` та час boot.

4. Порядок кваліфікації witness:

   - `TOP_GR_RUNLIST_OBSERVED=N` — лише inventory із decoded TOP record; це не channel witness;
   - `RUNLIST_ID_NOT_OBSERVED`, якщо потрібного TOP record немає;
   - `CHANNEL_RUNLIST_CORRELATED` — тільки коли конкретний GR/compute user channel прив'язаний source-backed/runtime до цього runlist;
   - `NONSTALL_EVENT_SUBSCRIPTION_OBSERVED` — лише коли channel-level trace доводить виклик `nvkm_uchan_uevent()` із `args->v0.type == NVIF_CHAN_EVENT_V0_NON_STALL_INTR` та відповідним `runl->id`; інакше лишати `NONSTALL_EVENT_SUBSCRIPTION_NOT_OBSERVED`;
   - TOP row із `runlist 0` чи nonzero сам по собі не переводить channel/event стани в ZERO/ACTIVE;
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
