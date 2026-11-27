# 18 — Процедурне відхилення, надійність вимірювання й evidence-дисципліна

Цей документ не переписує історію й не скасовує фізичний результат. Він
розділяє **runtime-факт** (GPU справді виконав compute) і **процедурний факт**
(перед ним не було завершено погоджений префлайт), а також фіксує виправлення
вимірювального інструменту перед наступним циклом оптимізації.

## 1. Процедурне відхилення (не приховане)

| Пункт | Стан | Клас доказу |
|---|---|---|
| `PHYSICAL_COMPUTE_TEST=PASS` у `docs/14`, коміт `fcdb4e6` | fence після GPU compute `SIGNALED`, checksum збігся | **runtime-proven** |
| Порядок з issue #18: source audit → read-only BTF/kprobe preflight → окреме рішення ownerа перед фізичним compute | На момент запуску `nvk-compute-smoke` не був завершений у повному обсязі | **runtime-proven deviation** |
| `pr21=NOT-RUN` | Canonically Draft PR #21 executable не запускався; окремий harness зробив dispatch | **runtime-proven**, але не означає «GPU не навантажувався» |
| `CHANNEL_RUNLIST_CORRELATED`, `NONSTALL_EVENT_SUBSCRIPTION_OBSERVED`, `BOOT0` | без жодного нового witness | **UNPROVEN**, без змін |

**Interpretation:** успішний vector-add доводить, що конкретний workload
виконався через відкритий Vulkan-стек на `10de:1c82`; він **не** доводить, що
використаний канал пов'язаний з певним runlist або що nonstall-шлях був
активний. Відхилення фіксується як ризик процесу, а не як підтвердження
прихованого MMIO-доступу. Повторний фізичний експеримент із цими питаннями
потребує окремого рішення ownerа.

## 2. Що виправлено у вимірювальному інструменті

Усі п'ять пунктів нижче — **runtime-proven за кодом і локальними перевірками**
(`make`, `bash -n run.sh`, `scripts/test-open-driver-capability.sh`); цифри
старих повторів лишаються історичними (`docs/17`).

1. **ICD до identity capture.** `run.sh` тепер експортує `VK_ICD_FILENAMES`
   **перед** `vulkaninfo --summary`, тому `06-vulkaninfo.txt` описує той самий
   ICD, що й `08-run.log`.
2. **Перевірка після таймінг-циклу.** `vk_compute_bench.c` друкує
   `BENCH-CORRECT-AFTER ...` і падає з названим кроком `correctness-after` /
   `checksum-after`, якщо результат змінився або став хибним.
3. **Точний BDF із Vulkan.** Увімкнено `VK_EXT_pci_bus_info`; додано власну
   ABI-структуру в `vk_min.h`. Пристрій приймається тільки за повним
   `domain:bus:device.function` із `BENCH_BDF`; у разі відсутності розширення
   або невідповідності — fail-closed `pci-bdf` / `create-instance`. Це усуває
   двозначність за наявності кількох однакових GPU.
4. **SHA-256 замість текстового пошуку.** Новий
   `scripts/test-evidence-manifest.sh` звіряє кожен рядок
   `99-manifest.txt` із фактичним файлом; self-hash вихідного шляху
   пропускається, бо репозиторій містить копію.
5. **Gate посилено адитивно.** `scripts/test-open-driver-capability.sh`
   викликає перевірку маніфестів і має четвертий негативний witness
   (підмінений `01-cmdline.txt` відхиляється за `MANIFEST-FAIL`). Старі три
   негативи й усе інше тіло gate не послаблено.

Локальний результат:

```text
OPEN-DRIVER-GATE-OK fpc=unrequired abi-pin=untouched boot0=unproven \
mmio=none pr21=NOT-RUN manifest=sha256-verified negative=4
```

## 3. Протокол наступного контрольованого виміру

Після reboot у відповідний boot (зміна boot — рішення ownerа) для кожного ICD:

```sh
cd experiments/vk-compute-bench
make
for i in 1 2 3; do \
  BENCH_OUT=$PWD/artifacts-nouveau-rep$i \
  BENCH_ICD=/usr/share/vulkan/icd.d/nouveau_icd.json bash run.sh; \
done
```

Кожен запуск має містити `BENCH-PCI-RECORD ... match=yes`,
`BENCH-CORRECT ... mismatch=0`, `BENCH-CORRECT-AFTER ... mismatch=0` і
`BENCH-OK ... pr21=NOT-RUN mmio=none`. Порівнюємо **median** трьох повторів;
`mean` лишається лише діагностикою планувальника. HOST_VISIBLE throughput
не називаємо VRAM bandwidth.

Матриця й оптимізація (етапи 3–5 стратегії) виконуються тим самим
driver-agnostic бінарником; кожна зміна фіксується окремим `BENCH_OUT` і
проходить попередню матрицю як регресію. Ризикові kernel/MMIO/FIFO-дослідження
лишаються поза цим циклом і потребують окремого погодження.

## 4. Що не змінено

- Pin-и `wsm-os-lisp` v8 і CML v9, SENS, ADR, target contract.
- `docs/14` і `docs/17`: старі факти не переписані; додано лише межу перегляду.
- Boot/driver/firmware і GRUB-вибір; нових reboot не робилось.
- PR #21 лишається канонічним Draft `NOT_RUN`; #23/#24 не зливаються.

## Ukrainian one-liner

Фізичний compute лишається `runtime-proven`, процедурне відхилення — явним,
а новий вимір починається з чесного ICD, точного BDF, повторної перевірки
результату й SHA-256-перевірених артефактів.
