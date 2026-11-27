# 20 — Базова лінія надійного harness: пропрієтарний ICD (NVIDIA 580.196.11)

Перший вимір після виправлень `docs/18`. Усі нижченаведені цифри —
**runtime-proven з комітованих артефактів**, а не історичні значення з `docs/17`.
Порівняння з NVK поки **не робиться**: потрібен reboot у відкритий boot
(окреме рішення ownerа).

## Стан

| Поле | Значення |
|---|---|
| Boot | NVIDIA default, `/proc/cmdline` без `wsm_open_driver=1` |
| BDF | `0000:01:00.0`, `10de:1c82` (sysfs + `BENCH-PCI-RECORD match=yes`) |
| ICD | `/usr/share/vulkan/icd.d/nvidia_icd.json` |
| Driver | `driverID=4`, `NVIDIA`, `580.196.11`, `api=0x00404138` |
| Пам'ять | `memType=8`, `HOST_VISIBLE|HOST_COHERENT`, heap=1 |
| Режим | `pr21=NOT-RUN`, `mmio=none`, binding=tільки запис |
| Повтори | 3 успішні, окремі `artifacts-nvidia-fixed-rep1..3/` |
| Manifest | `MANIFEST-OK files=11` для кожного повтору |

## Не зарахована спроба (чесно фіксується)

Перші три запуски з тієї ж серії впали на `BENCH-FAIL step=create-instance
vkResult=-7`: `VK_EXT_pci_bus_info` було помилково увімкнено як
**instance**-extension, тоді як це **device**-extension. Артефакти збережено в
`artifacts-nvidia-failed-ext-rep1..3/` як `runtime-proven` негативний witness.
Після перенесення розширення у `VkDeviceCreateInfo` усі три повтори завершились
`BENCH-OK`; жоден з невдалих запусків не включений у медіани нижче.

## Результати (median трьох повторів)

| Елементів | median першого/другого/третього (ns) | median of medians (ns) | effective GB/s |
|---|---|---|---|
| 4096 | 19621 / 40960 / 20310 | **20310** | **2.4201** |
| 1 Mi | 1361954 / 1259375 / 1267551 | **1267551** | **9.9269** |
| 8 Mi | 10616000 / 10162238 / 11072284 | **10616000** | **9.4822** |

Кожен успішний запуск мав `BENCH-CORRECT ... mismatch=0` **і**
`BENCH-CORRECT-AFTER ... mismatch=0`, checksum не змінився після циклу.
`mean` у 1 Mi/8 Mi перевищує median через CPU-планувальник; primary number —
median. Розкид для 4096 істотний (19621…40960 ns), тому маленький випадок
потребує більшої вибірки перед будь-яким висновком.

## Що це не означає

- Це не VRAM-пропускна здатність: вимірюється `HOST_VISIBLE|HOST_COHERENT`
  шлях + `vkQueueSubmit`/fence wait.
- Це не acceptance-порівняння з NVK: старі цифри `docs/17` знято старим
  harness і лишаються історичними (`docs/18`).
- Причина будь-якого майбутнього gap лишається **UNPROVEN**; REA з `docs/19`
  дає лише статичні control-імена.

## Наступний крок

Після owner-рішення про reboot у `wsm_open_driver=1` — ті самі три повтори з
`BENCH_ICD=/usr/share/vulkan/icd.d/nouveau_icd.json` у
`artifacts-nouveau-fixed-rep1..3/`, потім порівняння median одного harness.
Паралельно на поточному boot можна будувати матрицю (workgroup, пам'ять,
latency) без зміни драйвера чи ядра.

## Ukrainian one-liner

Оновлений harness дав чесну пропрієтарну базову лінію: 2.42 / 9.93 / 9.48 GB/s
ефективної HOST_VISIBLE-пропускної здатності, з зафіксованим негативним
witness і без порівняння з NVK до rebootу.
