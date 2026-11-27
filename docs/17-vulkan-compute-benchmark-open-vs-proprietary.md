# 17 — Clean-room Vulkan compute бенчмарк: відкритий boot vs закритий boot

Мета — порівняти **одним і тим самим бінарником** GP107 (`10de:1c82`) під
NVK/Nouveau і під пропрієтарним NVIDIA ICD, не запускаючи PR #21 executable,
не читаючи MMIO і не змінюючи boot/driver/firmware.

## Статус

| Boot | Стан | Driver record |
|---|---|---|
| Відкритий (`wsm_open_driver=1`, Nouveau) | **runtime-proven**, 3 повтори | `driverID=24 (DRIVER_ID_MESA_NVK)`, `driverName=NVK`, `Mesa 26.1.6-1` |
| Закритий (NVIDIA default) | **runtime-proven**, 3 повтори | `driverID=4 (VK_DRIVER_ID_NVIDIA_PROPRIETARY)`, `driverName=NVIDIA`, `580.196.11` |

Обидва boot-и завершені одним і тим самим бінарником і протоколом. Порівняння
нижче — **interpretation** на основі `runtime-proven` вимірів, а не новий
вимір і не доведення причинності.

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
| 4096 elem | 49 152 B | 31 051 / 36 577 / 36 167 | 1.344 – 1.583 | 29 974 – 31 565 |
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

### Що НЕ доведено (open boot)

- **UNPROVEN** — причинність будь-якої переваги; порівняння описане нижче.
- **UNPROVEN** — VRAM-only bandwidth, 3D/framebuffer, power/clock, довготривала
  стабільність; у бенчмарку немає контролю частот і немає transfer-only шляху.
- **string-only** — `0x137000A1` лишається рядком kernel log; бенчмарк його не читає.
- `PHYSICAL_COMPUTE_TEST=PASS` з doc 14 і цей бенчмарк — різні запуски; новий
  functional smoke тут не перезапускався.

## Результат — закритий драйвер (`runtime-proven`)

Після owner-reboot: `/proc/cmdline` без `wsm_open_driver=1`, `lspci` показує
`Kernel driver in use: nvidia`, sysfs `binding=nvidia`, явний ICD
`/usr/share/vulkan/icd.d/nvidia_icd.json`. Усі три повтори:
`BENCH_RC=0`, `mismatch=0`,
`BENCH-OK ... driver_id=4 driver_name=NVIDIA binding=nvidia pr21=NOT-RUN mmio=none`,
`api=0x00404138`. Kernel-log delta порожній у всіх трьох повторах.

| Розмір | Трафік на ітерацію | median ns (3 повтори) | median GB/s | min ns |
|---|---|---|---|---|
| 4096 elem | 49 152 B | 27 392 / 29 731 / 19 084 | 1.653 – 2.576 | 18 692 – 26 482 |
| 1 Mi elem | 12 582 912 B | 1 252 954 / 1 272 210 / 1 169 729 | 9.891 – 10.757 | 1 106 678 – 1 108 098 |
| 8 Mi elem | 100 663 296 B | 9 360 557 / 8 959 942 / 8 850 876 | 10.754 – 11.373 | 8 611 911 – 8 694 654 |

### interpretation

- 1 Mi дає 9.89–10.76 GB/s, 8 Mi — 10.75–11.37 GB/s; на відміну від NVK,
  закритий драйвер не показав падіння пропускної здатності на великому dispatch.
  Причину цього бенчмарк не встановлює.
- Малий dispatch знову шумний: 19–30 µs median; у rep1 `mean` 1 Mi помітно
  більший за `median` через CPU-планувальник.
- Порівнювати з відкритим boot треба **median**, а не `mean`.

## Порівняння обох boot-ів (`interpretation`)

Похідна таблиця: спершу береться median трьох повторів усередині кожного boot,
потім — відношення NVK / NVIDIA. Це не новий вимір і не статистичний тест.

| Розмір | median-of-3 NVK ns | median-of-3 NVIDIA ns | NVK / NVIDIA | Діапазон відношень за повторами |
|---|---|---|---|---|
| 4096 elem | 36 167 | 27 392 | 1.32× | 1.13 – 1.90× |
| 1 Mi elem | 1 363 174 | 1 252 954 | 1.09× | 1.07 – 1.25× |
| 8 Mi elem | 14 832 023 | 8 959 942 | 1.66× | 1.59 – 1.69× |

- Найменша різниця — 1 Mi (NVK ≈ 9 % повільніше); найбільша — 8 Mi
  (NVK ≈ 66 % повільніше). Малий dispatch має найширший шум.
- **interpretation**, не `runtime-proven` causation: boot-и відбувалися послідовно
  з owner-reboot між ними; немає чергування A/B, контролю частот/температури,
  ізоляції CPU і повторів у межах однієї сесії.
- **UNPROVEN** — продуктивність у VRAM-only шляху, 3D/framebuffer, енергоспоживання,
  стабільність під навантаженням і будь-яка перевага, спричинена саме кодом драйвера.
- **string-only** — `0x137000A1` лишається рядком kernel log; жоден бенчмарк
  його не читав.

### Provenance

SHA-256 `08-run.log`:

- NVK: `f9b594716cd68537b40c2be17146372a934ec85dacfe91c4f576e67679620551`,
  `69a159805536a6c2c6a44a6f113aa8d13e9c013be88d6f83f91892c7b6920939`,
  `46aa3d69b1c6f66d8fe051e010a55bd756349b097f636b8e87d19cf9c1ec576f`.
- NVIDIA: `b6a8ee43de88d42af57726847fdcdd1852b042afd52d0cd33df474ffe1960790`,
  `999daf9da5023ea296bc8a9eb47bb02e8632a9c0e6f497aeef052bb97e661c56`,
  `52d91198a4f496d2f6cd8fc6816ce3335eccf0c0fec5a4c05212f6cd2451b675`.

## Межі

- Жодного MMIO read/write, `nva`, custom reset, `/dev/nvidia*`, `Tested-by`.
- Жодного PR #21 executable — `pr21=NOT-RUN` у всіх записах.
- Не змінено pin-и, SENS/CML/wsm-os-lisp, GRUB чи active driver.
- Обидва набори артефактів (`artifacts-nouveau-rep1..3`, `artifacts-nvidia-rep1..3`)
  записані окремо; NVK-цифри не підмінено.
