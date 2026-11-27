# 19 — REA: межа пропрієтарного ICD та RM-контролі пам'яті/submit

Продовження `docs/11` і `docs/15`, зроблене паралельно з циклом бенчмарків.
Мета — зняти частину невизначеності про те, **де** в пропрієтарному стеку
знаходиться Vulkan-межа й які control-імена існують для пам'яті/submit.
Код, псевдокод і vendor source не копіюються: REA читає shipped-артефакти як
дані. Жодного MMIO, RM-запиту, PR #21 executable чи фізичного експерименту в
цьому зрізі не робилось.

## Тарґети

| Артефакт | SHA-256 | REA-операції |
|---|---|---|
| `/usr/lib/x86_64-linux-gnu/libGLX_nvidia.so.580.196.11` | `fb5bcecf63a9cbb7bea6a419c497af5469e1221d3e9cce02acaf4b34af342e61` | Ghidra inventory/export/deps/analyze_function summary; без pseudocode |
| `/usr/lib/x86_64-linux-gnu/libnvidia-glcore.so.580.196.11` | `e8b68f57d14236351bfc3fb74afb1e713ae85733a471fc815a4f07dbb7f4abcc` | ELF exports/deps/GPU-code-object inventory |
| `/tmp/opencode/rea-nvidia/nvidia.ko` (розпакований DKMS) | `95c5fa5ab0546ee40842cda2ec20ea3ec1e196a5afee1580944ecae2ffc75bbe` | rizin `izz~MEMORY`, `izz~BAR1`, `izz~SUBMIT` |

Evidence-бандли в репозиторії:
`evidence/rea-20261127/evidence-nvidia-icd-dispatch.json` (46 записів),
`evidence/rea-20261127/evidence-nvidia-ko-memory-controls.json` (54 записи,
накопичувальний).

## Statically proven — межа ICD

| Факт | Evidence |
|---|---|
| Повний dynamic-export inventory ICD: **2674** symbols; Vulkan-експорти лише три: `vk_icdGetInstanceProcAddr @ 0x9f740`, `vk_icdGetPhysicalDeviceProcAddr @ 0x9f7a0`, `vk_icdNegotiateLoaderICDInterfaceVersion @ 0x9f800` | `ev_c8c6e1e564fd9cd1a72985c5354a36587e680087140ae695e1069ee00c248de6` (coverage complete) |
| Це **уточнення до `docs/11`**: там зафіксовано два ICD-експорти; третій (`vk_icdNegotiateLoaderICDInterfaceVersion`) тепер statically proven | той самий Evidence |
| `vk_icdGetInstanceProcAddr`: 30 assembly units, 5 basic blocks, 3 callees, 8 referenced names, **0 referenced strings**; pseudocode не читався | `ev_ed17d9e5f7e1634846f5ff5870e914afddd0c2ddec601af72ae1ee3f2aa967b6` |
| `DT_NEEDED` ICD (7): `libnvidia-glsi`, `libnvidia-tls`, `libnvidia-glcore`, `libX11`, `libXext`, `libc`, `libdl`; `libdrm` немає | `ev_f87131dec524dba4b296f933870c55bd86214951b0f4755cbbeeb053f109ea68` |
| `libnvidia-glcore.so` має 26 dynamic exports; серед них `vk_optimusGetInstanceProcAddr` і `vk_optimusGetDeviceProcAddr`, решта — `_nvNNNglcore` | `ev_a7e8e86807fd79cd58a299f87240127f6483c451fb2027a7eea048a4d9c15ce8` |
| Inventory embedded CUDA/HIP GPU code objects: **0 objects / 0 kernels** в ICD і в glcore (тільки в межах підтриманих секцій) | `ev_bb3be55da54de19c893133b0ef600d36e89d7c0b2b5859b1a3f2ad7ceb025c88`, `ev_c92aa89b4fc65732c27c69b229786f40b76b03726bf85959db75678ab83fe59c` |

## String-only — Vulkan-залежні імена в ICD

Повний string inventory за шаблоном `^vk[A-Z]` дав **17** рядків
(`ev_6356a59054b58397d2e8be0aa5cf47fc6064201805ac46077140f5146320ee31`,
coverage complete-within-view): `vkCreateInstance`, `vkDestroyInstance`,
`vkCreateDevice`, `vkDestroyDevice`, `vkGetDeviceQueue`,
`vkCreateSwapchainKHR`, `vkDestroySwapchainKHR`, `vkQueuePresentKHR`,
`vkQueuePresent2KHR`, `vkQueueSubmit`, `vkGetInstanceProcAddr`,
`vkGetDeviceProcAddr`, `vkAllocateMemory`, `vkBindBufferMemory`,
`vkBindImageMemory`, `vkAcquireNextImageKHR`, `vkAcquireNextImage2KHR`.

Це **string-only**, не доведений dispatch-шлях і не перелік усіх команд
Vulkan у всьому стеку. Зокрема, рядків `vkCreateComputePipelines`,
`vkCmdDispatch` чи `vkMapMemory` у цьому інвентарі немає; порожній результат
для одного артефакту не є absence-proof для системи.

## Statically proven — RM-контролі пам'яті/submit у `nvidia.ko`

| Факт | Evidence |
|---|---|
| У `.rodata`: `ALLOC_MEMORY`, `MAP_MEMORY`, `UNMAP_MEMORY`, `MAP_MEMORY_DMA`, `UNMAP_MEMORY_DMA`, `ALLOC_DYNAMIC_MEMORY`, `MAP_SEMA_MEMORY`, `UNMAP_SEMA_MEMORY`, `CTRL_FABRIC_MEMORY_DESCRIBE` | `ev_12b0c06ebcd28852e0b0d07211296d1d828a7513833ee9af00d97c585524dc2d` |
| У `.BTF`: `NV_MEMORY_TYPE_SYSTEM`, `NV_MEMORY_TYPE_REGISTERS`, `NV_MEMORY_TYPE_FRAMEBUFFER`, `NV_MEMORY_TYPE_DEVICE_MMIO`, `UVM_PMA_GPU_MEMORY_TYPE_{UNPROTECTED,PROTECTED}` | той самий Evidence |
| У `.rodata`/`.BTF`: `RM64KBBAR1Mappings`, `kbusCreateFbSegment_VBAR1`, `kbusDestroyFbSegment_VBAR1`, численні `BAR1`, `BAR1 PDE`, `BAR1 PTE` | `ev_0dbfa4dbc344a80c310d3a4ca97c66b7cde5063ba685ae9f77bf804672e5aac1` |
| `CTRL_GPFIFO_GET_WORK_SUBMIT_TOKEN` і `CTRL_GPFIFO_SET_WORK_SUBMIT_TOKEN_NOTIF_INDEX` підтверджені окремим запитом (узгоджується з `docs/15`) | `ev_a15859ed8af7bfc02147bd3c772c315dade70bd532a0f6274e04325474635aa1` |

rizin друкував `WARNING: bin_file_strings: search interval size ... exceeds
max region size (0xa00000), skipping it` — навіть попри спробу підняти ключ у
межах виклику. Тому перелічені вище рядки є **statically proven наявністю**,
але інвентар **частковий**; порожні результати нічого не доводять.

## Interpretation (не causal proof)

- `libGLX_nvidia.so` виглядає тонким loader/interop-шаром: стандартний
  ICD-контракт із трьома точками входу, X/DRI3-залежності без `libdrm`,
  відносно малий розмір. **Interpretation**: самий ICD-export surface не
  пояснює виміряний NVK/NVIDIA gap; шукати причину треба глибше — у шляху
  пам'яті, submit-фенсингу та RM-плануванні.
- Наявність окремих control-імен для `MAP_MEMORY_DMA`, `NV_MEMORY_TYPE_*` і
  BAR1 узгоджується з тим, що пропрієтарний стек явно розрізняє системну,
  framebuffer і device-MMIO пам'ять. **UNPROVEN**: формат структур, вибір
  типу для нашого workload, специфіка GP107/Pascal і будь-який вплив на
  продуктивність не доведені.
- `vk_optimus*` в glcore стосуються Optimus-шляху; для дискретної GP107 це
  лише статичний факт, не активний маршрут.

## Межі

- `BOOT0`, `NONSTALL_EVENT_SUBSCRIPTION_OBSERVED`,
  `CHANNEL_RUNLIST_CORRELATED` лишаються **UNPROVEN/PARTIAL** без змін.
- Не використано Ghidra-pseudocode; не скопійовано vendor source чи код
  NVIDIA; не робилось MMIO read/write, `nva`, custom reset, `Tested-by`.
- Не змінено pin-и, SENS, CML, `wsm-os-lisp`, ADR чи target contract.
- REA не змінює pin-и й не надає права на risky physical experiment.

## Ukrainian one-liner

REA уточнив ICD-контракт (третя точка входу) і показав статичні RM-контролі
пам'яті/BAR1/GPFIFO, але не перетворив їх на причинний доказ продуктивності:
причина gap лишається відкритим research-питанням.
