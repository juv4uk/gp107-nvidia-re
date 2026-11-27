# GP107 TOP runlist trace: безпечний preflight

Мета — отримати hardware-derived runlist IDs із TOP table GP107 без
nva, setpci, /dev/mem, BAR/MMIO read/write або register-poking утиліт.

## Джерельний ланцюжок

У перевіреному upstream Linux source snapshot
9437ee8b6cf607e883b36e44bd755968daaebd48:

- nouveau_drm.c оголошує read-only module parameter debug типу charp
  і передає рядок у NVKM device creation.
- nvkm_dbgopt(device->dbgopt, subdev->name) розбирає глобальний рівень
  або адресований рівень subdevice. Порівняння префікса case-insensitive;
  TOP збігається з subdevice name top / top0.
- gk104_top_parse() виводить raw TOP words через nvkm_trace() (TRACE=5)
  і decoded engine/type/instance/runlist через nvkm_debug() (DEBUG=4).
  Глобальний trace підніме рівень усіх subdevices; вузьке
  nouveau.debug=TOP=trace,FIFO=debug піднімає рівень TOP до TRACE, а FIFO до DEBUG.
- Kconfig NOUVEAU_DEBUG задає compile-time ceiling; trace доступний лише
  коли CONFIG_NOUVEAU_DEBUG >= 5. Distro kernel може мати інше значення,
  ніж upstream default.

Pinned source:
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nouveau_drm.c
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/core/option.c
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/core/subdev.c
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/include/nvkm/core/subdev.h
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/subdev/top/gk104.c
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/Kconfig

## Read-only preflight

У native Linux, до будь-якого reboot:

~~~sh
./scripts/preflight-gp107-nouveau-top-trace.sh
~~~

Скрипт перевіряє kernel release, наявність kernel build config,
CONFIG_NOUVEAU_DEBUG >= 5, module parameter nouveau.debug та рівно один
PCI пристрій 10de:1c82. Він лише показує поточний sysfs driver binding,
не вимагає його змінювати й не виконує жодної операції запису.

Якщо потрібний config або debug parameter недоступний, скрипт завершується
NOT_READY і не рекомендує boot argument. Він не змінює GRUB, initramfs,
kernel modules, system driver, firmware чи GPU registers.

## Окремий rollback-capable boot

Лише коли preflight повернув READY, у тимчасовому boot entry додати:

~~~text
nouveau.debug=TOP=trace,FIFO=debug
~~~

Не записувати аргумент у постійний GRUB config. Використати окремий
native Linux boot із upstream Nouveau й можливістю повернутися до
попереднього робочого boot entry.

Після boot:

~~~sh
cat /proc/cmdline
journalctl -b -k -o short-monotonic --no-pager > nouveau-top-trace.log
grep -Ei 'top:|runlist|nvkm|fifo|engine.*(GR|CE)' nouveau-top-trace.log
~~~

Зберегти незмінений full journal, UTC timestamp, kernel package/commit,
kernel config, Nouveau package/version, PCI BDF і exit status capture.

## Source mapping від TOP table до вибору GR channel runlist

Після того як TOP rows отримані, runlist для типового GR channel можна
обчислити з upstream-коду без створення channel:

1. `gk104_top_parse()` декодує hardware `tdev->runlist` для engine.
2. `gk104_fifo_runl_ctor()` створює `nvkm_runl` з
   `runl->id = tdev->runlist` і `runl->addr = tdev->runlist`, потім додає
   engine цього TOP record до відповідного runlist.
3. `nvkm_fifo_info(NV_DEVICE_HOST_RUNLIST_ENGINES)` повертає engine mask
   для кожного `runl->id`.
4. `nvif_fifo_runlist()` будує mask `runm` усіх runlists, які містять GR.
5. `nouveau_channel_ctor()` встановлює `args->runlist = __ffs64(runm)`;
   отже стандартний GR channel вибирає наймолодший встановлений ID.
6. `nvkm_uchan_uevent()` бере `runl` із channel group і передає
   `runl->id` до `nvkm_uevent_add()` для NON_STALL_INTR.

Джерела:
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvif/fifo.c
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/fifo/base.c
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nvkm/engine/fifo/gk104.c
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nouveau_chan.c
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nouveau_drm.c
- https://github.com/torvalds/linux/blob/9437ee8b6cf607e883b36e44bd755968daaebd48/drivers/gpu/drm/nouveau/nouveau_abi16.c

Межа доказу: TOP hardware data + code path визначать runlist, який
звичайний GR channel обере для конкретної плати. Це ще не доводить, що
NVK compute реально створив такий channel або що він викликав
NVIF_CHAN_EVENT_V0_NON_STALL_INTR. Позначати event subscription як
NOT_OBSERVED, доки її invocation не буде підтверджено окремим evidence;
не створювати channel тільки заради перевірки до закриття conditional risk.

## Критерій

Потрібні decoded TOP rows для GR та CE* з engine/type/instance/runlist.
Зв'язати GR/compute engine з channel/runlist mapping у точному source
snapshot; не виводити channel ID лише з назви engine.

- Non-zero GR/compute runlist + доведений channel event registration —
  candidate для наступного source-level fix review.
- GR/compute runlist ID = 0 — цей one-entry indexing risk не підтверджений
  для основного compute path.
- Raw TOP words без decoded rows, відсутній GR row або ранній probe failure —
  RUNLIST_ID_NOT_OBSERVED / NOT_MEASURED.

До встановлення runlist ID не запускати GPU submit, NVK compute, Rusticl
або будь-який workload. Не використовувати nva, BAR/MMIO, setpci чи /dev/mem.
Не виставляти Tested-by і не оголошувати GP107 bug без фізичного свідка.
