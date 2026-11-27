# 11 — REA-факти з пропрієтарних shipped-артефактів (58x.196.11)

Це **не** звіт про відкритий драйвер і не дозвіл на запуск. Мета — дістати з
вже встановлених пропрієтарних артефактів лише **ABI-факти**, яких бракує у
власних clean-room зондах, і чітко позначити межу. Код і псевдокод не копіюються:
REA читає артефакти як дані.

## Тарґети

| Артефакт | SHA-256 | Стан |
|---|---|---|
| `/tmp/opencode/nvidia.ko` (розпакований DKMS `nvidia.ko.xz`) | `95c5fa5ab0546ee40842cda2ec20ea3ec1e196a5afee1580944ecae2ffc75bbe` | shipped-artifact, ELF64 ET_REL, not stripped |
| `/usr/lib/x86_64-linux-gnu/libGLX_nvidia.so.580.196.11` | `fb5bcecf63a9cbb7bea6a419c497af5469e1221d3e9cce02acaf4b34af342e61` | shipped-artifact, ELF64 ET_DYN, Vulkan/GL ICD з `nvidia_icd.json` |

## Статично доведено (REA, без виконання коду)

1. **`nvidia.ko` 580.196.11, `srcversion=65626331C62C6702B5D95C0`.**
   У `.modinfo` оголошено лише два firmware-файли:
   `nvidia/580.196.11/gsp_tu10x.bin` і `nvidia/580.196.11/gsp_ga10x.bin`.
   Є параметри `NVreg_IgnoreMMIOCheck`, `NVreg_OpenRmEnableUnsupportedGpus`,
   `NVreg_EnableGpuFirmware`, `NVreg_ResmanDebugLevel`.
   Evidence: `ev_6a5b3f3d...` (`inspect_kernel_module`, coverage complete, 71 entries).
2. **Вузька інтерпретація GSP:** у manifest модуля **нема** GSP-прошивки для
   Pascal/GP107; GSP згадується тільки для TU10x/GA10x. Це `interpretation`
   зі спостережуваних рядків, а не доведена відсутність будь-якого GSP-шляху на
   GP107. Практичний висновок: GSP не є очевидно потрібним для нашого першого
   зрізу; це **не** знімає потреби в BOOT0/MMIO witness.
3. **Пропрієтарний ICD — стандартний Vulkan-loader ICD.** `inspect_native_exports`
   знайшов `vk_icdGetInstanceProcAddr @ 0x9f740` (size 87) і
   `vk_icdGetPhysicalDeviceProcAddr @ 0x9f7a0` (size 87), обидва `global/default`.
   Evidence: `ev_c8c6e1e5...`, вибірка `ev_7ba1a8ee...`.
4. **Залежності ICD:** `libnvidia-glsi.so.580.196.11`, `libnvidia-tls.so.580.196.11`,
   `libnvidia-glcore.so.580.196.11`, `libX11.so.6`, `libXext.so.6`, `libc.so.6`,
   `libdl.so.2`. **`libdrm` серед DT_NEEDED немає**; водночас у `.rodata` є
   `xcb_dri3_set_drm_device_in_use`. Тобто презентація йде через X/DRI3, а
   керування GPU — через власний RM-шлях, не через DRM ioctl.
   Evidence: `ev_f87131de...` / `ev_7435049c...` (coverage complete: 7 needed,
   5 versions, 118 imports).

## Лише текстовий рядок (не доказ ABI)

- У `libnvidia-glcore.so` знайдено `nvDevice: INVALID CHANNEL PRIORITY %d\n` і
  `CE CHANNEL INDEX %d, is %s\n` (rizin `izz~CHANNEL`). Це лише наявність тексту;
  не доводить ані формат структури, ані алгоритм вибору prio/runlist.

## UNPROVEN / межі охоплення

- Пошук `BOOT0`, `GPFIFO`, `RUNLIST`, `NV2080_CTRL`, `NV_ESC` у 138M `nvidia.ko`
  і 36M `libnvidia-glcore.so` **не дав результату через обмеження rizin**
  (`search interval size ... exceeds max region size 0xa00000`). Порожній вивід
  **не є** доказом відсутності — це часткове покриття. Ghidra-псевдокод не
  використовувався навмисно (clean-room межа). Пізніше coverage для `nvidia.ko`
  піднято в `docs/15-rea-static-markers-nonstall-runlist-event.md`; там же
  зафіксовано нові статичні маркери, які не змінюють runtime-статус.
- Значення `BOOT0`, адреси регістрів, формат GPFIFO, вибір RUNLIST_ID,
  механізм ALLOW/BLOCK — лишаються `UNPROVEN`.
- Жодного нового MMIO-читання, RM-запиту чи фізичного запуску не робилось.

## Що це змінює в головній меті

1. Для лісп-машини достатньо стандартного ICD-інтерфейсу з двох точок входу;
   його може надати **відкритий** NVK, а не `libGLX_nvidia.so`.
2. Пропрієтарний шлях не використовує `libdrm`; відкритий шлях має йти через
   Nouveau DRM/KMS + NVK. Це підтверджує вибрану hosted-стратегію.
3. Наступний реальний крок лишається не REA, а GPU-witness: перевести плату на
   `nouveau` і перевірити NVK на `10de:1c82`. REA тут лише зняв частину
   невизначеності щодо структури стека.

## Коротко українською

REA показав, як пропрієтарний стек влаштований зовні, але не дав жодного права
писати в апаратуру — відкритий драйвер і далі починається з перевіреного
identity-контракту.
