# 17 — Clean-room Vulkan compute бенчмарк: відкритий boot vs закритий boot

Мета — порівняти **одним і тим самим бінарником** GP107 (`10de:1c82`) під
NVK/Nouveau і під пропрієтарним NVIDIA ICD, не запускаючи PR #21 executable,
не читаючи MMIO і не змінюючи boot/driver/firmware.

## Статус

| Boot | Стан | Driver record |
|---|---|---|
| Відкритий (`wsm_open_driver=1`, Nouveau) | **runtime-proven**, 3 повтори | `driverID=24 (DRIVER_ID_MESA_NVK)`, `driverName=NVK`, `Mesa 26.1.6-1` |
| Закритий (NVIDIA default) | **NOT_RUN** — очікує owner-reboot | буде записано окремо в `artifacts-nvidia/` |

Не робиться жодного висновку про продуктивність закритого драйвера, доки
його запуск не відбувся.

## Метод

Harness: `experiments/vk-compute-bench/`.

1. Перевірка плати через sysfs: `0000:01:00.0`, `vendor=0x10de`, `device=0x1c82`;
   sysfs `driver` лише **записується** (`binding=nouveau` / `nvidia`), не
   фільтрується.
2. Власні Vulkan ABI-декларації в `vk_min.h`; власний SPIR-V для
   `c[i] = a[i] + b[i]` від `gen_spirv.py`. Жодного vendor header/коду.
3. Пам’ять `HOST_VISIBLE | HOST_COHERENT`, `memType=1`; отруєння C значенням
   `0xDEADBEEF`; CPU-еталон і checksum перед таймінгом.
4. Кожна ітерація: `vkResetFences` → `vkQueueSubmit` → `vkWaitForFences` →
   `vkGetFenceStatus`. У вимірюваному циклі **нема** readback.
5. Фіксується `min`, `median`, `mean` тривалості; primary number — `median`.
   Пропускна здатність рахується як `12 × elements / median_ns` (2 read + 1 write).
6. Три розміри: `4096`, `1 Mi`, `8 Mi` елементів; warmup 20/10/5; ітерацій 200/50/20.
7. Три незалежні повтори з явно зафіксованим ICD.

Команда для відкритого boot:

```sh
cd experiments/vk-compute-bench
make
for i in 1 2 3; do \
  BENCH_OUT=$PWD/artifacts-nouveau-rep$i \
  BENCH_ICD=/usr/share/vulkan/icd.d/nouveau_icd.json bash run.sh; \
done
```

Команда для закритого boot (після reboot у NVIDIA default):

```sh
cd experiments/vk-compute-bench
make
for i in 1 2 3; do \
  BENCH_OUT=$PWD/artifacts-nvidia-rep$i \
  BENCH_ICD=/usr/share/vulkan/icd.d/nvidia_icd.json bash run.sh; \
done
```

`run.sh` зберігає cmdline, `lspci`, `lsmod`, binding, ICD, `vulkaninfo --summary`,
kernel-log delta, `08-run.log` і `99-manifest.txt` із SHA-256 усіх файлів.

## Результат — відкритий драйвер (`runtime-proven`)

Усі три повтори: `BENCH_RC=0`, `mismatch=0`, `BENCH-OK ... pr21=NOT-RUN mmio=none`,
driver `NVK(24)`.

| Розмір | Трафік на ітерацію | median ns (3 повтори) | median GB/s | min ns |
|---|---|---|---|---|
| 4096 elem | 49 152 B | 31 051 / 36 577 / 36 167 | 1.359 – 1.583 | 29 974 – 31 565 |
| 1 Mi elem | 12 582 912 B | 1 360 625 / 1 363 174 / 1 465 332 | 8.587 – 9.248 | 1 226 909 – 1 271 996 |
| 8 Mi elem | 100 663 296 B | 14 832 023 / 15 111 598 / 14 083 088 | 6.661 – 7.148 | 11 233 323 – 12 641 482 |

### interpretation

- Найстабільніший результат — 1 Mi елементів: ~8.6–9.2 GB/s на
  HOST_VISIBLE-шляху; розкид ~7.7 %.
- 8 Mi елементів дає нижчу пропускну здатність (~6.7–7.1 GB/s), імовірно через
  тиск на пам’ять і approximation з меншою кількістю ітерацій (20).
- Малий dispatch (`4096`) має високу латентність ~31–37 µs і сильний шум:
  `mean` у двох повторах у 5–9 разів більший за `median` через CPU-планувальник.
- Порівнювати з закритим драйвером треба **median**, а не `mean`.

### Що НЕ доведено

- **UNPROVEN** — перевага будь-якого драйвера; закритий boot ще не запускався.
- **UNPROVEN** — VRAM-only bandwidth, 3D/framebuffer, power/clock, довготривала
  стабільність; у бенчмарку немає контролю частот і немає transfer-only шляху.
- **string-only** — `0x137000A1` лишається рядком kernel log; бенчмарк його не читає.
- `PHYSICAL_COMPUTE_TEST=PASS` з doc 14 і цей бенчмарк — різні запуски; новий
  functional smoke тут не перезапускався.

## Межі

- Жодного MMIO read/write, `nva`, custom reset, `/dev/nvidia*`, `Tested-by`.
- Жодного PR #21 executable — `pr21=NOT-RUN` у всіх записах.
- Не змінено pin-и, SENS/CML/wsm-os-lisp, GRUB чи active driver.
- Після owner-reboot результат потрібно записати в цей же документ окремою
  секцією, не підмінюючи open-driver цифри.
