# 08 — Підсумковий звіт спринту GP107/GTX 1050 Ti під R580

> **Межа звіту й доказу:** цей документ охоплює лише пропрієтарні NVIDIA R580 user-space RM-зонди. Він **не** є результатом тестування Nouveau/NVK/Rusticl. Фізичний open-driver runtime на GTX 1050 Ti (`10de:1c82`) у межах цього звіту не запускався: **`NOT_RUN / UNPROVEN`**. Для підвищення статусу потрібні окремі native-Linux логи саме з цієї фізичної карти.

Це завершальний звіт семи частин спринту `gp107-nvidia-re`. Репозиторій
залишається **неавторитетною research-базою**: він не є новою системною ABI,
не змінює SENS, CML, `wsm-os-lisp`, їхні ADR, target contract чи ABI-pin.
Усі висновки подано з явним станом доказу. База спринту — `2c2b746`,
кінечний стан research-зрізу — `c7e3218`, гілка `master` синхронізована з
`origin/master`. Цей звіт додано окремим комітом поверх `c7e3218`;
пізніші коміти в `master` поза цим спринтом до оцінок нижче не належать.

## 1. Що виправлено

| Проблема | До спринту | Після спринту | Коміт |
|---|---|---|---|
| Плутанина між відмовою відкрити `resource0` і спробою `mmap` | один стан `DENIED` міг читатися як твердження про BAR0 | окремі `OPEN_DENIED` / `MMAP_DENIED`; `EACCES` явно не доводить власника BAR0 | [`841fa3c`](https://github.com/juv4uk/gp107-nvidia-re/commit/841fa3c5226f80dec8d4330261b3859371e1c4b5) |
| Хардкод `/dev/nvidia0` | шлях GPU-вузла припускався з minor=0 | шлях обчислюється з `NV_ESC_CARD_INFO`; 0 або >1 збігів дає `RM-ARCH-FAIL` | [`ff74ac8`](https://github.com/juv4uk/gp107-nvidia-re/commit/ff74ac8ad4cf1fcbf2ab17955e10434a70c1ecac) |
| Неявне звільнення RM-обʼєктів через закриття fd | cleanup не був окремим доведеним кроком | явний `NV_ESC_RM_FREE` у зворотному порядку; інʼєкція часткової відмови перевіряє 1/2/3 free | [`7a2317f`](https://github.com/juv4uk/gp107-nvidia-re/commit/7a2317fc72af6bc6e1746533d8675b87b0c4bb96) |
| gate не розділяв суміжні види доказів | статичні ELF-перевірки й сумісність хоста були в одному потоці | окремі бінарні докази та `PASCAL-PROBE-UNSUPPORTED`/exit 3 для несумісного хоста | [`81b1e7b`](https://github.com/juv4uk/gp107-nvidia-re/commit/81b1e7b1f2e45a75c4c150dce196c0ded05de91a) |
| Розрізнені факти без єдиної карти станів | докази й межі були в кількох документах | консолідована матриця 26 фактів із commands і negative checks | [`6c4f373`](https://github.com/juv4uk/gp107-nvidia-re/commit/6c4f37312856b235b957509d1b72c6018ea084df) |
| Відсутній явний напрям далі | не було сформульованих критеріїв для command submission | план E1–E6 із критеріями green/negative та заборонами | [`c7e3218`](https://github.com/juv4uk/gp107-nvidia-re/commit/c7e3218e609bdd3ad73a316dbebbdc7934eed89d) |

## 2. Нові спроможності

1. **Динамічний вибір GPU-вузла** — `NV_ESC_CARD_INFO` → `minor_number` →
   `/dev/nvidia<N>`, звірений із sysfs `10de:1c82 @ 0000:01:00.0`.
   Стан: `runtime-proven`.
2. **Явний lifecycle RM-обʼєктів** — `NV01_ROOT_CLIENT` →
   `NV01_DEVICE_0` → `NV20_SUBDEVICE_0`, потім `RM_FREE` у зворотному
   порядку. Стан: `runtime-proven`, включно з інʼєкційними негативами.
3. **Fail-closed BAR0-negative** — звичайний користувач отримує
   `BAR0-STATE: OPEN_DENIED`, `mmap` не виконується, BOOT0 залишається
   `UNPROVEN`. Стан: `runtime-proven` для самої відмови; причина відмови —
   `UNPROVEN`.
4. **Незалежні бінарні докази** — STATIC ELF, без `PT_INTERP`, `.dynamic`,
   `PT_DYNAMIC`, `DT_NEEDED`; немає динамічної libc. Стан:
   `statically proven, ELF`.
5. **Захист від хибного green** — несумісна версія FPC і часткові RM-відмови
   дають явний fail-closed вихід, а не підміну успіху. Стан:
   `runtime-proven negative`.
6. **Карта межі знання** — [`05-gp107-capability-matrix.md`](05-gp107-capability-matrix.md)
   і [`07-next-research-direction.md`](07-next-research-direction.md).
   Стан: документований research-план; нові там дії — `UNPROVEN`.

## 3. Точні команди перевірки й фактичні результати

### 3.1 Основний гейт

```bash
cd /home/agents/GitHub/gp107-nvidia-re
bash -n scripts/test-pascal-probe.sh
bash scripts/test-pascal-probe.sh
```

Фактичний вихідний код: `0`. Ключові маркери останнього прогону:

```text
HOST-PROFILE-OK bdf=0000:01:00.0 driver=580.196.11 block=8000000 bar0=0x00000000ee000000
FPC-PIN-OK 3.2.2
BAR0-STATE: OPEN_DENIED
BOOT0: UNPROVEN (open denied; MMIO not attempted)
NV2080_CTRL_MC_GET_ARCH_INFO: arch=0x00000130 impl=0x00000007 rev=0x000000A1 subrev=0x02
BOOT0: UNPROVEN (RM arch info is a separate channel)
RM-CLEANUP-COMPLETE objects=3
BINARY-PROOF-OK elf-static=yes no-dynamic-deps=yes libc-dynamic=no
PASCAL-PROBE-GATE-OK fpc=3.2.2 static=yes no-libc=yes gpu=10de:1c82 bar0=fail-closed rmarch=runtime-proven boot0=unproven
```

Негативні маркери того самого прогону:

```text
RM-CLEANUP-COMPLETE objects=1
RM-CLEANUP-COMPLETE objects=2
RM-CLEANUP-COMPLETE objects=3
```

### 3.2 Негатив щодо версії toolchain

```bash
FPC_EXPECTED=9.9.9 bash scripts/test-pascal-probe.sh
```

Фактично: exit `3` і рядок
`PASCAL-PROBE-UNSUPPORTED reason=fpc-version=3.2.2 expected=9.9.9`.

### 3.3 Негативи часткової RM-відмови

```bash
for s in after_alloc_client after_alloc_device after_alloc_subdev; do
  WSM_RM_FAIL_STEP=$s ./pascal/03_rm_arch_info
done
```

Фактично: кожен запуск exit `2`, друкує `RM-ARCH-FAIL step=INJECT-...`
і рівно `RM-CLEANUP-COMPLETE objects=1|2|3` відповідно.

### 3.4 Опційний root-свідок

```bash
sudo -n bash scripts/test-root-witness.sh
```

У поточній сесії **не виконано**: `sudo -n` недоступний. У попередній
сесії root-свідок показав `open(resource0)` OK і
`mmap(PROT_READ|MAP_SHARED)` → `EINVAL`; сама причина `EINVAL` лишається
`UNPROVEN`. Базовий гейт цей свідок не вимагає.

## 4. Класифікація доказів

### `statically proven`

- `NV2080_CTRL_CMD_MC_GET_ARCH_INFO = 0x20801701`.
- Параметри arch-info: 3 × `NvU32` + `NvU8` з паддингом до 16 байт.
- `GPU_IMPLEMENTATION_GP107 = 0x07`, `ARCHITECTURE_GP100 = 0x130`,
  `Tnvos00 = 16`; структури перевірено compile-time `SizeOf`-assertами.
- Усі три Pascal-бінарники — STATIC ELF без динамічних залежностей. `libc` не є динамічною залежністю.

### `runtime-proven`

- `arch=0x130 impl=0x7 rev=0xa1 subrev=0x2` через власний FPC-зонд;
  раніше звірено з libcuda-shimом.
- Ідентичність `10DE:1C82 @ 0000:01:00.0 minor=0`, шлях `/dev/nvidia0`.
- `GPU_ATTACH_IDS : gpu=0x100 status=0`; явні `RM_FREE status=0` ×3.
- `OPEN_DENIED` для непривілейованого `resource0`; BOOT0 не читався.
- Поведінка негативів FPC-pin та RM-інʼєкції.

### `string-only`

- `0x137000A1` як рядок із libdrm `cl0080.h`. Це не прочитаний регістр.

### `interpretation`

- `0x130` → GP100-родина, `0x07` → GP107; це публічні імена констант.
- Збіг `rev=0xa1` із молодшим байтом `0x137000A1` **не** є BOOT0-доказом.
- `EINVAL` може бути повʼязаний із володінням BAR0 драйвером, але сам
  errno причини не доводить.

### `UNPROVEN`

- BOOT0 на цій hosted-машині з активним `nvidia.ko`; нормативне значення
  лишається `BOOT0 = UNPROVEN`.
- Причина `EACCES`/`EINVAL`; семантика `devpars.device_id = 0`.
- Чи звільняє fd всі RM-обʼєкти сам по собі — у зонді є явний `RM_FREE`.
- Channel/context, pushbuffer, command submission, GPU sync, doorbell,
  DMA/GVA, kernel launch, writable BAR0.
- Display/GOP/framebuffer, bare-metal/UEFI MMIO seam.
- Перенесення `PciConfig`/`Mmio`/`RmControl` у `wsm-os-lisp` або оновлення
  ABI-pin; потрібне окреме owner-рішення.

## 5. Межі, які збережено

- Не змінено `wsm-os-lisp/target-abi-pin.lisp` (v8) і CML/master (v9).
- Не оголошено Contract 12.0 conformance для нового ABI.
- Не додано SID8 у активну проєкцію й не створено нову Lisp-основу з FPC.
- Не поєднано hosted compute/RM/UVM із display/GOP/framebuffer або з
  bare-metal BOOT0.
- Не копійовано vendor source, Ghidra-псевдокод чи декомпільовані NVIDIA-файли;
  збережено лише власні потоки, таблиці, ABI-факти й власний C/Pascal.

## 6. Коміти спринту

1. [`841fa3c`](https://github.com/juv4uk/gp107-nvidia-re/commit/841fa3c5226f80dec8d4330261b3859371e1c4b5) — розділення `OPEN_DENIED`/`MMAP_DENIED`.
2. [`ff74ac8`](https://github.com/juv4uk/gp107-nvidia-re/commit/ff74ac8ad4cf1fcbf2ab17955e10434a70c1ecac) — GPU-шлях з `NV_ESC_CARD_INFO`.
3. [`7a2317f`](https://github.com/juv4uk/gp107-nvidia-re/commit/7a2317fc72af6bc6e1746533d8675b87b0c4bb96) — явний `RM_FREE` та cleanup при частковій відмові.
4. [`81b1e7b`](https://github.com/juv4uk/gp107-nvidia-re/commit/81b1e7b1f2e45a75c4c150dce196c0ded05de91a) — окремі ELF-докази й environment gate.
5. [`6c4f373`](https://github.com/juv4uk/gp107-nvidia-re/commit/6c4f37312856b235b957509d1b72c6018ea084df) — матриця можливостей за станами доказу.
6. [`c7e3218`](https://github.com/juv4uk/gp107-nvidia-re/commit/c7e3218e609bdd3ad73a316dbebbdc7934eed89d) — план research E1–E6.

Попередня база: [`2c2b746`](https://github.com/juv4uk/gp107-nvidia-re/commit/2c2b74607a7b52d64dc0d45bc6cef6ea678b9abf).
