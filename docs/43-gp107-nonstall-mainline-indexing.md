# 42 — GP107: global non-stall event index versus per-runlist channel ID

Цей документ доповнює [docs/09](09-gp107-fifo-nonstall-source-audit.md)
та [issue #18](https://github.com/juv4uk/gp107-nvidia-re/issues/18).
Це **source-only** аудит точного Linux mainline snapshot. Він не доводить
runtime defect на GA-H170-Gaming 3 і не є підставою патчити ядро чи запускати
новий GPU workload.

## 0. Verdict

Для GP107 upstream dispatch обирає `gp100_fifo_new()`. У `gp100_fifo`
вказаний `.nonstall = &gf100_fifo_nonstall`, але немає
`.nonstall_ctor`. Загальний FIFO initializer тому створює non-stall event
з одним індексом (`index_nr = 1`).

Водночас generic Nouveau user-channel callback передає `runl->id` як
notifier ID. Якщо такий notifier буде створено для каналу з
`runl->id != 0`, source path показує дві умовні проблеми:

1. перехід notifier у `allowed` викликає `nvkm_event_get()`, який
   індексує `refs[index * types_nr + type]` без локальної перевірки меж;
   для однобазового event array ненульовий index виходить за межі;
2. FIFO non-stall IRQ шлях викликає `nvkm_event_ntfy(event, 0, ...)`,
   а notifier dispatch порівнює `ntfy->id == id`; notifier із ненульовим
   ID не збігається з глобальним IRQ index 0.

Це **умовна source inconsistency**, а не свідчення, що GR/compute channel
на H170 фактично має ненульовий runlist. Відомий сторонній GP107 witness
у [docs/13](13-nouveau-nvk-boot-witness-result.md) показав GR TOP runlist 0,
але user-channel → runlist кореляцію не довів.

## 1. Immutable source snapshot

Перевірено upstream `torvalds/linux` commit:

- commit: `f4585067150b85e33f60876149a6e742928da75e`
- дата commit: 2026-11-27 20:41:24 UTC
- branch tip, зафіксований перед читанням файлів: `master`
- кожен файл нижче отриманий за повним commit SHA, не з рухомого `master`.

| Файл | Перевірений факт |
|---|---|
| `nvkm/engine/device/base.c` | `nv137_chipset` (GP107) обирає `gp100_fifo_new()`; dispatch ID `0x137` |
| `nvkm/engine/fifo/gp100.c` | `gp100_fifo` задає `.nonstall`, але не `.nonstall_ctor` |
| `nvkm/engine/fifo/base.c` | відсутній ctor задає `ret = 1`, потім event init отримує `types_nr = 1`, `index_nr = 1` |
| `nvkm/engine/fifo/uchan.c` | `NVIF_CHAN_EVENT_V0_NON_STALL_INTR` реєструє `runl->id` |
| `nvkm/core/uevent.c` | передає цей ID у `nvkm_event_ntfy_add()` |
| `nvkm/core/event.c` | реєстрація notifier починається з `allowed = 0`; `get/put` індексують ref array; notify перевіряє index та ID |
| `nvkm/engine/fifo/gk104.c` | GP100/GK104 FIFO runlists створюються за ID із TOP table; IRQ non-stall notify використовує ID 0 |
| `nouveau_chan.c` | user-channel request формує runlist з `__ffs64(runm)` |
| `nouveau_fence.c` | user fence path створює `NON_STALL_INTR` event; окремо викликає allow при fence signaling |

Commit-pinned source links:

- [GP107 chipset dispatch](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/engine/device/base.c#L2211-L2242)
- [GP100 FIFO function table](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/engine/fifo/gp100.c#L113-L139)
- [FIFO oneinit / event index count](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/engine/fifo/base.c#L287-L303)
- [user-channel non-stall callback](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/engine/fifo/uchan.c#L42-L60)
- [uevent registration bridge](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/core/uevent.c#L124-L134)
- [notifier state and allow/block transitions](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/core/event.c#L60-L160)
- [event get/put reference indexing](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/core/event.c#L25-L57)
- [event notify index guard and ID match](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/core/event.c#L169-L189)
- [TOP table runlist decode](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/subdev/top/gk104.c#L45-L64)
- [runlist construction from TOP entries](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/engine/fifo/gk104.c#L770-L809)
- [global non-stall IRQ notify with ID 0](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/engine/fifo/gk104.c#L725-L734)
- [user-channel constructor chooses runlist from mask](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nouveau_chan.c#L254-L310)
- [NVKM user-channel resolves runlist ID](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nvkm/engine/fifo/uchan.c#L330-L375)
- [fence context creates non-stall event](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nouveau_fence.c#L168-L205)
- [fence signaling allows the event](https://github.com/torvalds/linux/blob/f4585067150b85e33f60876149a6e742928da75e/drivers/gpu/drm/nouveau/nouveau_fence.c#L517-L530)

## 2. End-to-end source path

### 2.1 GP107 selects the legacy/global FIFO non-stall event

`nv137_chipset` is named GP107. Its FIFO constructor is
`gp100_fifo_new()`; its TOP constructor is `gk104_top_new()`
(`device/base.c`, lines 2211–2242).

The GP100 FIFO table contains:

- `.nonstall = &gf100_fifo_nonstall`;
- `.runl_ctor = gk104_fifo_runl_ctor`;
- no `.nonstall_ctor` initializer.

In `nvkm_fifo_oneinit()`, when a non-stall event exists but the optional
per-runlist `nonstall_ctor` does not, `ret` is set to 1. That value is
passed as `index_nr` to `nvkm_event_init()` with `types_nr = 1`.
Thus this event has one valid index: 0.

### 2.2 Channel event registration carries the channel runlist ID

The generic user-channel constructor sets `args->runlist = __ffs64(runm)`.
`nvkm_uchan_new()` looks up that exact runlist and creates the channel group
against it. `nvkm_uchan_uevent()` then obtains `runl` from the channel's
group and, for `NVIF_CHAN_EVENT_V0_NON_STALL_INTR`, calls
`nvkm_uevent_add(..., runl->id, ...)`.

The ID is therefore not rewritten to zero on this path in the inspected
snapshot. The source establishes the passed value; it does not tell us which
mask `runm` a specific physical GP107 compute user-channel receives.

### 2.3 Object registration is not an enabled event subscription

On the host side, `nouveau_fence_context_new()` constructs the
`NVIF_CHAN_EVENT_V0_NON_STALL_INTR` event when the uevent path is enabled.
The NVKM bridge calls `nvkm_event_ntfy_add()`, which stores `ntfy->id`,
`bits`, `wait`, sets `allowed = 0`, and sets `running = false`.

At this point:

- the event/notifier object has been registered;
- it is not yet allowed;
- `nvkm_event_get()` has not yet been called because notifier state has not
  transitioned to running.

Fence signaling separately calls `nvif_event_allow()`. The NVKM allow path
changes `allowed` from 0 to 1, calls `nvkm_event_ntfy_state()`, and that
state transition calls `nvkm_event_get()`. Blocking later calls
`nvkm_event_put()`.

### 2.4 The two index-sensitive operations

The reference helpers use:

`event->refs[index * event->types_nr + type]`

in both `nvkm_event_get()` and `nvkm_event_put()`. Those helpers do not
perform a local `index < index_nr` test before indexing the array.

The delivery path is separate. `nvkm_event_ntfy()` first rejects
`id >= event->index_nr`, then dispatches only notifier objects for which
`ntfy->id == id`. In the inspected GK104 FIFO IRQ handler the global
non-stall interrupt is delivered as:

`nvkm_event_ntfy(&fifo->nonstall.event, 0, NVKM_FIFO_NONSTALL_EVENT)`

Consequently, on the conditional path where a notifier ID is nonzero:

- enabling it feeds that nonzero ID into the unchecked reference index;
- the global IRQ dispatch uses ID 0, so it does not match the stored nonzero
  notifier ID.

This describes the static control/data flow. It does not claim that the
conditional path occurs for an actual GP107 GR/compute channel on the owner's
board.

## 3. Evidence states must stay separate

Use these exact evidence labels in future witness reports:

| State | What is required | What it does not prove |
|---|---|---|
| `CHANNEL_NONSTALL_EVENT_ENTRY_OBSERVED` | callback receives the non-stall event type with a channel/runlist context | successful notifier registration |
| `NONSTALL_EVENT_OBJECT_REGISTERED` | `nvkm_uevent_add()` / notifier add returns successfully | `ALLOW`, refcount transition or interrupt delivery |
| `NONSTALL_EVENT_ALLOWED` | separate `NVIF_EVENT_V0_ALLOW` is observed | correct reference index or IRQ matching |
| `RUNLIST_REFCOUNT_UPDATED` | `nvkm_event_get/put()` transition and actual index are observed | hardware interrupt or fence progress |
| `NONSTALL_IRQ_MATCH_OBSERVED` | interrupt dispatch index and notifier ID are shown to match | completed fence |
| `FENCE_PROGRESS_OBSERVED` | a specific fence sequence advances/signals | general stability or all engines |

Do not compress these states into a generic “subscription works” verdict.

## 4. Hardware evidence boundary

The separate Kali/NVK GP107 witness in docs/13 recorded GR TOP runlist 0.
That is a decoded hardware TOP inventory result, not a trace of
`nouveau_channel_ctor()`, `runm`, a GR user-channel's `args->runlist`,
`NVIF_CHAN_EVENT_V0_NON_STALL_INTR`, `ALLOW`, refcount, or fence progress.
It does not identify the owner's GA-H170-Gaming 3.

Current owner-side labels remain:

- `TOP_GR_RUNLIST_0_OBSERVED`: external GP107 witness only;
- `USER_CHANNEL_RUNLIST_UNCORRELATED`;
- `CHANNEL_NONSTALL_EVENT_ENTRY_OBSERVED`: not demonstrated for H170;
- `NONSTALL_EVENT_OBJECT_REGISTERED`: not demonstrated for H170;
- `NONSTALL_EVENT_ALLOWED`: not demonstrated for H170;
- `RUNLIST_REFCOUNT_UPDATED`: not demonstrated for H170;
- `FENCE_PROGRESS_OBSERVED`: not demonstrated for H170;
- `H170_NATIVE_LINUX_ACCEPTANCE=NOT_RUN`.

## 5. Upstream patch and action

The proposed legacy FIFO fix from the September 2026 mailing-list series normalizes
the non-stall event index to zero when a per-runlist `nonstall_ctor` is absent.
The candidate is relevant to this source shape, but it must not be called merged
or present in the tested mainline snapshot. The exact current mainline source
above still uses `runl->id` in `nvkm_uchan_uevent()`.

**Do not cherry-pick or deploy the patch on H170 from this evidence alone.**
Before any kernel change, require:
1. exact running kernel package, source commit and downstream patchset pairing;
2. exact Nouveau module/build identity on the witness host;
3. channel/runlist correlation from an existing approved witness or a separately
   reviewed experiment plan;
4. owner approval for any hardware runtime test and an explicit rollback path.

Until then, the useful next work is source-level only: preserve the immutable
snapshot, compare new upstream commits to it, and obtain provenance for the
existing external witness. Do not run GPU enumeration/submit, RM/UVM ioctl,
BAR/MMIO, BPF/kprobe/ftrace, driver switch/unbind, firmware changes or reboot.

## Ukrainian one-liner

У Linux master GP107 використовує FIFO з одним глобальним non-stall event index,
але generic user-channel callback передає `runl->id`; це створює умовну
source-проблему для ненульового runlist, тоді як фактичний GR/compute
user-channel ID на H170 залишається недоведеним.
