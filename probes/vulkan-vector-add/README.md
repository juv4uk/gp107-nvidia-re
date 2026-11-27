# Мінімальний Vulkan compute harness для GP107 (`10de:1c82`)

Це **clean-room reproducible test proposal**, не hardware witness.
Він перевіряє тільки compute шлях: `vkCmdDispatch` → fence → host readback →
CPU checksum. У ньому немає display/KMS/framebuffer, покриття UVM, BOOT0 або
власного драйвера.

## Що перевіряється

1. sysfs BDF має `vendor=10de`, `device=1c82`;
2. Vulkan physical device має той самий BDF через `VK_EXT_pci_bus_info`,
   vendor/device і compute-чергу;
3. shader виконує `c[i] = a[i] + b[i]` для `uint` буфера;
4. після `vkWaitForFences` CPU звіряє кожен елемент із `3*(i+1)`.

Вихідні маркери: `BDF-SYSFS-OK`, `VULKAN-PHYSICAL-OK`, `VECTOR-ADD-CHECK-OK`,
`HARNESS-DONE rc=0`. Будь-яка невідповідність дає fail-closed вихід.

## Збірка (без GPU)

Потрібні Vulkan headers і loader; glslang потрібен тільки для `.spv`.

```bash
cd /home/agents/GitHub/gp107-nvidia-re/probes/vulkan-vector-add
bash build.sh
```

У цій сесії заголовки взято з Khronos Vulkan-Headers у `/tmp` (не в репо):

```bash
VULKAN_INCLUDEDIR=/tmp/opencode/vk-headers bash build.sh
```

Генерація SPIR-V на цільовій машині:

```bash
glslangValidator -V --target-env vulkan1.2 vector_add.comp -o vector_add.spv
```

## Запуск — тільки на фізичній `10de:1c82` після test boot

```bash
./vector_add --bdf 0000:01:00.0 --spirv vector_add.spv --elements 4096
```

Для NVK-шляху (після boot з Nouveau, не з `nvidia.ko`):

```bash
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nouveau_icd.json \
  ./vector_add --bdf 0000:01:00.0 --spirv vector_add.spv --elements 4096
```

Для proprietary ICD той самий harness є контрольним RM/Vulkan шляхом, але
його результат **не** є NVK witness. `vkcube` і будь-який графічний Vulkan
тест не підходять як compute доказ.

## Поточний стан

- `runtime-proven` на цій hosted-машині: `vulkaninfo --summary` бачить
  `10de:1c82` із `DRIVER_ID_NVIDIA_PROPRIETARY` / `580.196.11`; NVK як ICD для
  плати не активний.
- `NOT_RUN`: `vkCmdDispatch`, fence/readback і checksum на цій платі.
- `NOT_RUN`: NVK compute; потрібен окремий boot із Nouveau й rollback.
- Не змінюємо SENS, CML, `wsm-os-lisp`, ABI-pin, firmware чи системний driver.
