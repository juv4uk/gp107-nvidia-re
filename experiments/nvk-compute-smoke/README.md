# Clean-room NVK vector-add smoke test

Це окремий harness для `PHYSICAL_COMPUTE_TEST`. Він **не** використовує PR #21,
пропрієтарний ICD, vendor headers чи vendor code.

## Що перевіряє

1. sysfs-ідентифікація BDF: `vendor=0x10de`, `device=0x1c82`, driver symlink = `nouveau`;
2. Vulkan-фільтр фізичного пристрою: `vendorID == 0x10de`, `deviceID == 0x1c82`;
3. жорсткий фільтр драйвера: `driverID == VK_DRIVER_ID_MESA_NVK` (24), інакше негайний fail;
4. 1024 × `uint32_t` A/B/C у `HOST_VISIBLE | HOST_COHERENT`;
5. детерміновані A/B і сентінель `0xDEADBEEF` у C перед dispatch;
6. `vkCmdBindPipeline` + `vkCmdBindDescriptorSets` + `vkCmdDispatch(16,1,1)`;
7. `vkQueueSubmit` з `VkFence`, `vkWaitForFences`, `vkGetFenceStatus`;
8. host readback C і порівняння FNV-1a з CPU-еталоном; будь-яка невідповідність = fail;
9. трасування `ioctl` і дельта kernel log.

## Збірка

Системних Vulkan headers і glslang у-machine немає, тому `vk_min.h` містить
власні мінімальні ABI-декларації, а `gen_spirv.py` самостійно емітує SPIR-V.

```sh
make
make nvk_compute_smoke_noop   # тільки негативний контроль
```

## Запуск

```sh
make run           # strace + kernel log -> artifacts/
make run-negative  # no-op shader -> artifacts-negative/, очікується rc=2
```

Змінні оточення: `SMOKE_BDF` (типово `0000:01:00.0`), `SMOKE_ICD` (типово
`/usr/share/vulkan/icd.d/nouveau_icd.json`), `SMOKE_OUT`.

Фінальний прийнятий запуск збережено в `artifacts-v4/`; негативний контроль —
у `artifacts-negative/`; перевірку залежностей і збіг ABI-offsets — у
`artifacts-static/`. Інтерпретація міток доведення — у
`docs/14-nvk-vector-add-compute-result.md`.

## Межі

- Жодного MMIO-read/write, `nva`, custom reset або `/dev/nvidia*`.
- Жодного `Tested-by`, release/tag чи пушу.
- Один board, один shader, один dispatch: це functional smoke, не benchmark і не
  доведення всіх PASCAL/SM_61 шляхів.
