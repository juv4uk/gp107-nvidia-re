# 14 — Результат clean-room NVK vector-add compute smoke (2026-11-27)

**Статус: `PHYSICAL_COMPUTE_TEST=PASS / NVK-VECTOR-ADD-RUNTIME-PROVEN`.**
Це functional evidence для реальної плати `10de:1c82` під відкритим стеком.
Це **не** `Tested-by`, не benchmark, не довідка про всі CUDA-шляхи й не
дозвіл запускати PR #21.

## 1. Provenance й clean-room межа

- Harness: `experiments/nvk-compute-smoke/`, власний C11-код, власний Python-генератор
  SPIR-V і мінімальні Vulkan-декларації в `vk_min.h`.
- OpenGL/Vulkan vendor headers, vendor source/blob, Ghidra-псевдокод і код NVIDIA
  **не використовувались**.
- Чисельні Vulkan-константи й opcode-номери звірено з публічними Khronos-headers:
  - `vulkan_core.h`, SHA-256 `a6948c33bbc0422092ad5d96fe9ea9d4109214fa00f26715b23ed1971f4e7216`;
  - `spirv.hpp11`, SHA-256 `7454207c6a2de60c008c3c739021ffe667b90317d030694387868ff92293e9ff`.
- Збірка: `cc -O2 -Wall -Wextra -std=c11 -I. -o nvk_compute_smoke nvk_compute_smoke.c -ldl`.
- ICD запуску: `/usr/share/vulkan/icd.d/nouveau_icd.json` через `VK_ICD_FILENAMES`.
- BDF: `0000:01:00.0`. Поточний boot — відкритий драйвер, знятий раніше у doc 13.
- Жодного MMIO-read/write, `nva`, custom reset, `/dev/nvidia*` або змін
  boot/driver/firmware у цій сесії.

## 2. Результат перевірки залежностей

Артефакт: `experiments/nvk-compute-smoke/artifacts-static/01-deps.txt`,
SHA-256 `67525688d9010fad370c50ae7e59703d9d82ffddea27173dab1b2f56f56f7c7e`.

```text
ABSENT  /usr/include/vulkan/vulkan.h
ABSENT  /usr/lib/x86_64-linux-gnu/pkgconfig/vulkan.pc
PRESENT /usr/lib/x86_64-linux-gnu/libvulkan.so.1
TOOL    cc / clang / fpc / vulkaninfo / strace / python3
MISSING glslangValidator / glslc / spirv-as / spirv-val
```

`statically proven`: через відсутність headers і SPIR-V-компілятора harness
вантажить `libvulkan.so.1` через `dlopen`, оголошує власні ABI-structs і емітує
SPIR-V самостійно. Це не `interpretation` і не прихований CPU-шлях.

Окремо звірено offset-и ключових структур з публічним Khronos-header:
`artifacts-static/02-abi-offsets.txt`, SHA-256
`4d4f8c34303c2c235f6889024d03e544ead5b7db17f5de535284d06eb6f2d37d`.
`VkComputePipelineCreateInfo=96`, `stage@24`, `layout@72`,
`VkPipelineShaderStageCreateInfo=48`, `VkShaderModuleCreateInfo=40`,
`VkPhysicalDeviceDriverProperties=536` — збігаються для `vk_min.h` і публічного
header. Мітка: `statically proven (ABI layout)`, **не** NVIDIA-ABI-факт.

## 3. Контракт harness

- `BDF-ASSERT`: sysfs `vendor=0x10de`, `device=0x1c82`, driver symlink `nouveau`.
- `DEVICE-FILTER`: Vulkan `vendorID==0x10de && deviceID==0x1c82`.
- `DRIVER-FILTER`: `driverID == VK_DRIVER_ID_MESA_NVK` (24). Будь-який інший
  драйвер (пропрієтарний, llvmpipe, softpipe) викликає `NVK-COMPUTE-FAIL` до
  створення пайплайну.
- A/B/C — по 4096 байт, `HOST_VISIBLE | HOST_COHERENT`, memType 1.
- A: `i*3+1`; B: `i*5+7`; C перед dispatch: `0xDEADBEEF`. Сентінель додано
  спеціально, щоб залишкова пам’ять від попереднього процесу не дала хибного PASS.
- Один compute pipeline з власним SPIR-V `c[i] = a[i] + b[i]`,
  `LocalSize(64,1,1)`, три storage-buffer descriptor-и.
- `vkCmdBindPipeline`, `vkCmdBindDescriptorSets`, `vkCmdDispatch(16,1,1)`,
  `vkQueueSubmit(..., fence)`, `vkWaitForFences`, `vkGetFenceStatus`.
- Readback C, FNV-1a по 4096 байт, порівняння з CPU-еталоном; розсинхрон = fail.

## 4. Прийнятий run

Артефакт: `experiments/nvk-compute-smoke/artifacts-v4/03-run.log`, SHA-256
`e06bdf4335d7084ed373f65343678f578f4d140bf83875d10bda0522b0c6320d`.
Час зняття: `2026-11-27T05:25:09Z`, `HARNESS_RC=0`.

```text
BDF-ASSERT-OK bdf=0000:01:00.0 vendor=0x10de device=0x1c82 driver=nouveau
DEVICE-FILTER-OK vendor=0x10de device=0x1c82 name=NVIDIA GeForce GTX 1050 Ti (NVK GP107)
DRIVER-FILTER-OK id=24 name=NVK info=Mesa 26.1.6-1
BUFFERS-OK elements=1024 bytes=4096 memType=1 c-init=0xdeadbeef
DISPATCH-RECORDED groups=16x1x1 local=64
FENCE-OK status=SIGNALED
CHECKSUM got=0xa52ce165 expected=0xa52ce165 match=yes mismatches=0
NVK-COMPUTE-SMOKE-OK bdf=0000:01:00.0 vendor=0x10de device=0x1c82 driver=NVK(24) elements=1024 dispatch=16x1x1 fence=SIGNALED checksum=0xa52ce165 match=yes pr21=NOT-RUN mmio=none
HARNESS_RC=0
```

Незалежний передрахунок FNV-1a на Python: `A=0xc3bb14f5`, `B=0xba046629`,
`C=0xa52ce165`. Мітка: `runtime-proven` + `statically proven (independent arithmetic)`.
Ключове: `runtime-proven`, бо `0xa52ce165` отримано з host readback після
реального GPU-dispatchу, а не лише обчислено на CPU.

## 5. ioctl-свідок dispatch/submit

Повний trace: `artifacts-v4/02-ioctl.txt`. Фрагмент саме біля submit —
`artifacts-v4/08-dispatch-ioctl.txt`, SHA-256
`b1bc22a5567ca8f3f6937f3090b5ac645284bee1d745784681d0450fcbe177ae`:

```text
103:3676  ioctl(5, DRM_IOCTL_NOUVEAU_EXEC, 0x55d47227e918) = 0
104:3676  ioctl(5, DRM_IOCTL_NOUVEAU_EXEC, 0x55d472277668) = 0
105:3676  ioctl(5, DRM_IOCTL_NOUVEAU_EXEC, 0x55d47227e918) = 0
106:3676  ioctl(5, DRM_IOCTL_SYNCOBJ_WAIT, 0x7ffc335854d0) = 0
107:3676  ioctl(5, DRM_IOCTL_SYNCOBJ_WAIT, 0x7ffc335855d0) = 0
```

У повному trace також видно `DRM_IOCTL_NOUVEAU_CHANNEL_ALLOC`,
`DRM_IOCTL_NOUVEAU_VM_BIND`, `DRM_IOCTL_NOUVEAU_GEM_NEW`,
`DRM_IOCTL_SYNCOBJ_CREATE` і `DRM_IOCTL_SYNCOBJ_WAIT` на fd 5. Рядки з розмитим
списком аліасів `GET_PARAM` **не** іменуємо конкретно; рядок
`DRM_IOCTL_AUTH_MAGIC ... = -1 EACCES` на іншому fd під час енумерації не є
compute-помилкою, бо submit і checksum пройшли. Мітка: `runtime-proven`.

Дельта kernel log за час запуску порожня: `artifacts-v4/06-kernel-delta.txt`
має SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
Отже нових TOP/FIFO-рядків під час цього compute-запуску **немає**; попередні
TOP/FIFO-факти лишаються фактами boot-зняття з doc 13. Мітка:
`runtime-proven negative (no new kernel messages)`, не absence-доказ для драйвера.

## 6. Негативний контроль

`make run-negative` використовує той самий C-harness і BDF, але валідний no-op
SPIR-V, який не записує C. Очікуваний результат: fence signaled, але checksum
падає з `c-init=0xdeadbeef`.

Артефакт: `artifacts-negative/01-noop.log`, SHA-256
`c6f3c7ebdbe2e3e1bcb9d0cbf87ae1af037db6f2024b71f5961e52c6b34ff114`.

```text
FENCE-OK status=SIGNALED
CHECKSUM got=0xc49c4dc5 expected=0xa52ce165 match=no mismatches=1
NVK-COMPUTE-FAIL step=checksum detail=GPU result differs from CPU reference
NOOP_RC=2
NEGATIVE-CONTROL-OK rc=2 step=checksum
```

Мітка: `runtime-proven negative`. Це відсікає хибний PASS через неініціалізовану
або залишкову пам’ять. Проміжні невдалі ітерації з пошкодженим SPIR-V
(`VK_ERROR_UNKNOWN`, `-13`) та no-op без сентінеля не є прийнятими evidence
і в репо не збережені.

## 7. Леджер доказів

| ID | Артефакт | SHA-256 (перші 12) | Мітка |
|---|---|---|---|
| `E1:DEPS` | `artifacts-static/01-deps.txt` | `67525688d901` | `runtime-proven` |
| `E2:ABI-OFFSETS` | `artifacts-static/02-abi-offsets.txt` | `4d4f8c34303c` | `statically proven` |
| `E3:RUN` | `artifacts-v4/03-run.log` | `e06bdf4335d7` | `runtime-proven` |
| `E4:IOCTL` | `artifacts-v4/08-dispatch-ioctl.txt` | `b1bc22a5567c` | `runtime-proven` |
| `E5:DMESG-DELTA` | `artifacts-v4/06-kernel-delta.txt` | `e3b0c44298fc` | `runtime-proven negative` |
| `E6:NEGATIVE` | `artifacts-negative/01-noop.log` | `c6f3c7ebdbe2` | `runtime-proven negative` |
| `E7:MANIFEST` | `artifacts-v4/99-manifest.txt` | див. файл | `provenance` |

## 8. Кваліфікація маркерів

| Маркер | Стан | Підстава |
|---|---|---|
| `PHYSICAL_COMPUTE_TEST` | `PASS` / `runtime-proven` | реальний `10de:1c82`, NVK, dispatch + fence + readback + checksum |
| `NVK_DRIVER_ID_ON_GP107` | `runtime-proven` | `driverID=24`, `driverName=NVK`, `Mesa 26.1.6-1` |
| `NO_CPU_FALLBACK_ACCEPTANCE` | `runtime-proven negative` | жорсткий `driverID` filter; пропрієтарний ICD/llvmpipe не брали участі |
| `GPU_RESULT_EQUALS_CPU_REFERENCE` | `runtime-proven` | FNV-1a `0xa52ce165`, 0 mismatches, негативний контроль падає |
| `VK_ABI_LAYOUT` | `statically proven` | збіг offset-ів із публічним Khronos header |
| `RUNLIST_ID_NONZERO_OBSERVED` | `runtime-proven` (doc 13) | boot trace, не compute |
| `CHANNEL_RUNLIST_CORRELATED` | `PARTIAL / UNPROVEN` | явного зв’язку конкретного каналу з runlist немає |
| `NONSTALL_EVENT_SUBSCRIPTION_OBSERVED` | `UNPROVEN` | у логах немає `event`/`ntfy` |
| `BOOT0` | `UNPROVEN` | свідомо не читався |
| `0x137000A1` | `string-only` | kernel-log string з doc 13, не BOOT0 |
| `PR21_EXECUTABLE` | `NOT_RUN` | не запускався |
| `Tested-by / release / tag / push` | `NOT_CLAIMED / NOT_DONE` | без owner-дії |

## 9. Межа головної мети

`runtime-proven`: на лісп-машині GPU `10de:1c82` виконує реальне Vulkan
compute-навантаження через відкритий стек `nouveau + NVK`, без пропрієтарного
стеку NVIDIA. Це закриває попередній `PHYSICAL_COMPUTE_TEST=NOT_RUN` з doc 13
для **цього clean-room harness**.

`UNPROVEN`: продуктивність/стабільність під тривалим навантаженням, інші шейдери
і shader stages, мульти-GPU fixture, firmware-рівень, BOOT0, nonstall event
subscription і будь-яка еквівалентність до CUDA-поведінки пропрієтарного стеку.

Не змінювались: ABI-pins, SENS/CML/wsm-os-lisp, ADR, target contract,
`/etc/modprobe.d`, firmware і конфігурація PR #21.
