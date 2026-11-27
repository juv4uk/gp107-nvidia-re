# 22 — Окремий вимір: DEVICE_LOCAL transfer/compute/readback фази

Продовження етапу 3 без reboot (за рішенням ownerа залишились на NVIDIA).
Це **новий harness**, а не переписані результати `docs/17`, `docs/20`, `docs/21`:
`vk_transfer_bench` кладе дані в DEVICE_LOCAL через HOST_VISIBLE staging,
виконує той самий власний vector-add SPIR-V і окремо тайміть чотири фази
з окремими fence-ами.

## Статус і межі

- **Runtime-proven:** 12/12 точок (`4096`, 1 Mi, 8 Mi, 32 Mi × 3 повтори)
  `rc=0`, `driver_id=4`, `NVIDIA`, `host_type=8`, `device_type=7`,
  `device_local_only=1`, `mismatch=0`, `TRANSFER-OK ... pr21=NOT-RUN mmio=none`,
  `MANIFEST-OK files=11` для всіх 12, порожні kernel-delta.
- **Runtime-proven:** ще 3 повтори канонічного HOST_VISIBLE бінарника на
  32 Mi (`artifacts-hostvisible-32m-rep{1,2,3}/`), `BENCH-CORRECT-AFTER
  mismatch=0`, `BENCH-OK ... pr21=NOT-RUN mmio=none`, MANIFEST-OK.
- **Interpretation:** нижчі співвідношення — похідні медіан, не новий вимір.
- **UNPROVEN:** NVK на цьому harness, реальний вибір пам'яті пропрієтарним
  стеком, годинники/енергія, пікова VRAM-пропускна здатність.

## Метод

Кожна фаза — власний `vkQueueSubmit` + `vkWaitForFences`:

1. `h2d_a`: staging A → DEVICE_LOCAL A (`vkCmdCopyBuffer`);
2. `h2d_b`: staging B → DEVICE_LOCAL B;
3. `compute`: bind pipeline/descriptor + `vkCmdDispatch` на DEVICE_LOCAL A/B/C;
4. `d2h_c`: DEVICE_LOCAL C → staging C.

Thermal/warmup: 2 прогрівочні цикли, далі 20 ітерацій; primary number —
медіана трьох повторів. Мітки `effective_gb_s` рахують **умовний traffic**:
4 байти/елемент для копій і 12 байтів/елемент для compute (2 читання + 1 запис).
Це не пропускна здатність шини VRAM і не PCIe-теоретичний максимум.

## Результати (медіани 3 повторів, ns)

| Елементів | h2d A | h2d B | compute (DEVICE_LOCAL) | d2h C | сума фаза | compute GB/s |
|---:|---:|---:|---:|---:|---:|---:|
| 4096 | 19402 | 18770 | 17417 | 17997 | 73586 | 2.82 |
| 1 Mi | 584930 | 563269 | 228516 | 543699 | 1924413 | 55.06 |
| 8 Mi | 3760183 | 4027769 | 1122181 | 3951592 | 13135725 | 89.70 |
| 32 Mi | 15848416 | 16125162 | 4451008 | 15869757 | 52390811 | 90.46 |

Копії в обидва боки: ~7.17–8.92 GB/s умовного traffic (найстабільніше на
8/32 Mi). DEVICE_LOCAL compute виходить на ~90 GB/s умовного traffic для
великих задач.

## Порівняння з HOST_VISIBLE на 32 Mi

| Шлях | Медіана (ns) | Умовний GB/s |
|---|---:|---:|
| Канонічний HOST_VISIBLE dispatch (3 повтори) | **42577965** | 9.46 |
| DEVICE_LOCAL compute **без** копій | **4451008** | 90.46 |
| Повний ланцюг staging→GPU→compute→staging | **52390811** | — |

**Interpretation:**

1. Для **даних, які вже лежать у VRAM**, compute на DEVICE_LOCAL у ~9.6 рази
   швидший за HOST_VISIBLE dispatch (за умовним traffic). Це найсильніший
   сигнал усієї матриці й напрямок для оптимізації.
2. Для **одноразового streaming** повний ланцюг повільніший за HOST_VISIBLE
   (52.39 ms проти 42.58 ms на 32 Mi), бо дві копії з'їдають виграш. Тому
   не можна оголошувати «DEVICE_LOCAL завжди швидший».
3. Отже попереднє відставання NVK вимірювало переважно **шлях даних**, а не
   саме ядро vector-add. Але причинність gap лишається **UNPROVEN**: потрібен
   той самий вимір під NVK після окремого рішення про reboot.
4. Пропрієтарний ICD міг би вибирати DEVICE_LOCAL для подібних workload-ів;
   це гіпотеза, не доведений факт. REA з `docs/19` дає лише статичні імена
   `NV_MEMORY_TYPE_FRAMEBUFFER` / `MAP_MEMORY_DMA`, не вибір типу в рантаймі.

## Відтворення

```sh
cd experiments/vk-compute-bench
make vk_transfer_bench
BENCH_ICD=/usr/share/vulkan/icd.d/nvidia_icd.json bash run_transfer_grid.sh
```

Артефакти: `artifacts-transfer-{4096,1048576,8388608,33554432}-rep{1,2,3}/`,
`transfer-summary.tsv`, `artifacts-hostvisible-32m-rep{1,2,3}/`.

## Ukrainian one-liner

DEVICE_LOCAL compute тримає ~90 GB/s умовного traffic, але копії роблять
одноразовий ланцюг повільнішим за HOST_VISIBLE; оптимізація має розрізняти
streaming і дані, що вже лежать у VRAM.
