# Clean-room Vulkan compute benchmark (GP107, обидва ICD)

Один і той самий бінарник для відкритого і закритого драйвера. На відміну від
`nvk-compute-smoke`, він **не фільтрує** драйвер: перевіряє плату за sysfs і
через `VK_EXT_pci_bus_info` (`10de:1c82 @ 0000:01:00.0`), а потім **записує**,
який Vulkan-ICD відповів.

## Що міряє

- `c[i] = a[i] + b[i]` (`uint32_t`), власний SPIR-V від `../nvk-compute-smoke/gen_spirv.py`;
- три розміри: 4096, 1 Mi, 8 Mi елементів;
- час одного `vkQueueSubmit` + `vkWaitForFences` (fence signaled, без readback у циклі);
- `min / median / mean` у ns і медіанну пропускну здатність для 12 байт/елемент
  (2 читання + 1 запис);
- до і **після** таймінгу — обов’язкова перевірка GPU-результату з CPU-еталоном
  (poisoned C = `0xDEADBEEF`, checksum, `mismatch=0`);
- `run.sh` встановлює `VK_ICD_FILENAMES` до `vulkaninfo --summary`, щоб
  identity-лог належав тому самому ICD, що й вимір.

Межа: це **HOST_VISIBLE|HOST_COHERENT шлях**, тобто PCIe/CPU-мапований
шлях, а не пікова VRAM-пропускна здатність. У часову мітку входить і
планувальник CPU; `mean` часто більший за `median` — primary number = `median`.

## Збірка

```sh
make
```

## Запуск — відкритий boot (NVK)

```sh
BENCH_ICD=/usr/share/vulkan/icd.d/nouveau_icd.json bash run.sh
```

## Запуск — закритий boot (пропрієтарний ICD)

Після reboot у NVIDIA-дефолт:

```sh
BENCH_ICD=/usr/share/vulkan/icd.d/nvidia_icd.json bash run.sh
```

`run.sh` сам визначає `binding` із sysfs і кладе результат у
`artifacts-nouveau/` або `artifacts-nvidia/`. Для повторів:
`BENCH_OUT=$PWD/artifacts-nouveau-repN BENCH_ICD=... bash run.sh`.

Змінні: `BENCH_BDF` (типово `0000:01:00.0`), `BENCH_ICD`, `BENCH_OUT`,
`BENCH_ELEMENTS` (один розмір), `BENCH_ITERS`.

## Межі

- Жодного MMIO read/write, `nva`, custom reset, `/dev/nvidia*`, `Tested-by`.
- Жодного PR #21 executable, transfer коду, release/tag чи пушу зсередини Harness.
- Не міряє power, clocks, 3D/framebuffer і не змінює boot/driver/firmware.
- Результати мають бути порівняні лише при однаковому BDF, ICD, розмірі й числі ітерацій.
