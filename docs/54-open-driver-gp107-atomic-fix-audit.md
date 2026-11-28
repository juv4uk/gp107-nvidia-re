# 54 — Відкритий драйвер для GP107: аудит atomic-фіксу Nouveau

Це перший практичний крок до мети власника: **нормальні відкриті драйвери для
його GTX 1050 Ti / GP107 (`10de:1c82`)**. Тут не аналізуються пропрієтарні
бінарники, не виконуються RM/UVM ioctl, MMIO, firmware-зміни, reboot або
перемикання драйверів. Джерело — публічний upstream Linux і вже опублікований
[`docs/48`](48-gp107-open-stack-status-2026-11.md).

## 0. Що важливо

[`docs/48`](48-gp107-open-stack-status-2026-11.md) §3.2 фіксує регресію саме на
GP107: увімкнення atomic modesetting для NV50+ (`2652aca460dc`) призводило до
NULL pointer dereference під час ініціалізації дисплея; обхід —
`nouveau.atomic=0`. Статус на 2026-11-28: виправлення є в mainline, але чи є
воно у конкретному ядрі власника — **`UNKNOWN`**, бо `uname -r` ще не надано.

**Цей документ перевіряє публічний факт і дає інструмент перевірки локального
дерева ядра. Висновок про ядро власника не робиться.**

## 1. Перевірений upstream-факт

| Властивість | Значення | Статус |
|---|---|---|
| Коміт | `ed7fb901fce31588bd12ab95adc36ebcb51bc8ea` | `statically proven` |
| Автор / дата | Dave Airlie, `2026-11-11T06:00:05Z` | `statically proven` |
| Назва | `drm/nouveau/disp: Set drm_mode_config_funcs.atomic_(check\|commit) (attempt 2)` | `statically proven` |
| Файл | `drivers/gpu/drm/nouveau/nouveau_display.c` | `statically proven` |
| Зміни | +10 / −1 | `statically proven` |
| Джерело | `https://api.github.com/repos/torvalds/linux/commits/ed7fb901fce31588bd12ab95adc36ebcb51bc8ea` (отримано 2026-11-28) | `statically proven` |

Суть patchу публічного ядра (стисло, без копіювання великого фрагменту):

- додається окремий набір `drm_mode_config_funcs` —
  `nouveau_mode_config_funcs_atomic` — з
  `.atomic_check = drm_atomic_helper_check` і
  `.atomic_commit = drm_atomic_helper_commit`;
- у `nouveau_display_create()` вибір робиться через
  `drm_drv_uses_atomic_modeset(dev)`: для atomic-шляху береться новий набір,
  інакше лишається старий;
- це другу спробу: перша (`604826acb3f5`) була відкочена `6c65db809796` через
  поломку pre-atomic заліза (NV04) — тому новий набір не чіпає спільний шлях.

Коміт має `Cc: stable@vger.kernel.org`, отже може бути присутній і в
дистрибутивних стабільних гілках, не тільки в mainline. **Аналіз того, чи є
він у конкретному релізі, — окрема перевірка нижче.**

## 2. Чому це важливо для GP107, а не абстрактно

- GP107 належить до NV50+, тобто потрапляє під дію коміту `2652aca460dc`, який увімкнув
  atomic за замовчуванням.
- У звіті nouveau від 2026-11-02 саме GP107 (гібрид з Intel iGPU) падав у
  `drm_atomic_commit`; `nouveau.atomic=0` знімав проблему.
- Фікс `ed7fb901fce3` не змінює boot-шлях і не вимагає пропрієтарної
  прошивки — це чистий DRM-код ядра.
- Отже це **найближчий до застосунку відкритий fix**, який можна перевірити
  без жодного ризикованого hardware-експерименту.

## 3. Відтворювана перевірка

Додано `scripts/check-nouveau-atomic-fix.py`. Він читає вказане користувачем
дерево ядра, шукає два маркери в
`drivers/gpu/drm/nouveau/nouveau_display.c` і, якщо каталог є git-репозиторієм,
перевіряє `git merge-base --is-ancestor ed7fb901… HEAD`.

```bash
uname -r
python3 scripts/check-nouveau-atomic-fix.py --kernel-dir /path/to/linux
```

Без `--kernel-dir` скрипт друкує `NEED_INPUT` і не робить нічого іншого. Він
не звертається до мережі, до `/dev/*`, до GPU, до пропрієтарних файлів.

Можливі статуси:

| Статус | Що означає |
|---|---|
| `FIX_PRESENT` | фікс є предком HEAD **і** обидва маркери присутні |
| `FIX_ABSENT_OR_PARTIAL` | гілка не містить фіксу або маркери відсутні/часткові |
| `SOURCE_MARKERS_ONLY` | маркери є, але git-походження перевірити не вдалося |
| `NEED_INPUT` | треба вказати каталог ядра |

## 4. Межі й статуси

| Твердження | Статус |
|---|---|
| Коміт `ed7fb901…` існує в публічному `torvalds/linux` і містить описаний patch | `statically proven` |
| Регресія GP107 і обхід `nouveau.atomic=0` | задокументовано в `docs/48` §3.2 з датованими джерелами |
| Чи містить фікс ядро власника | `UNKNOWN` — потрібні `uname -r` або шлях до вихідних кодів ядра |
| Чи усуває фікс проблему саме на цій карті в рантаймі | `UNPROVEN` — рантайм не запускався |
| Відкриті драйвери працюють «нормально» на GP107 | `NOT_MEASURED` — див. Issue #28, матриця критеріїв |

## 5. Наступні кроки

1. Отримати від власника `uname -r` (або шлях до дерева/headers ядра).
2. Запустити `scripts/check-nouveau-atomic-fix.py`; записати результат у
   окремий evidence-файл із SHA-256 і версією інструментів.
3. Якщо фікс відсутній — підготувати **інструкцію**, не дію: оновлення ядра
   або тимчасовий `nouveau.atomic=0`. Будь-яка зміна boot-конфігурації — тільки
   за явним дозволом власника.
4. Після закриття KMS-питання перейти до вимірюваного NVK/Vulkan compute на
   GP107 через уже наявний fail-closed harness з Issue #28 / PR #43; не
   створювати новий harness і не запускати пропрієтарний драйвер одночасно.

## 6. Що явно не робилося

- Пропрієтарні бінарники NVIDIA не аналізувалися; попередня гілка `docs/53`
   для цієї мети не потрібна й лишається в локальній гілці
  `draft/doc53-uncleared` без публікації.
- RM/UVM ioctl, `cuInit`, CUDA/Vulkan init, GPU submit, BPF/kprobe, MMIO,
  BOOT0, firmware/VBIOS, driver switch, reboot — `NOT RUN`.
- Тег, Release, rc6, keyring, WSM-маніфест, upstream installer — не
  публікувалися.
- Усі твердження позначено `statically proven`, `UNKNOWN`, `UNPROVEN` або
  `NOT_MEASURED`; жодне не ґрунтується на іменах чи припущенні про ядро
  власника.
