# 46 — GP107: звірка заліза та стан інструментобуду

Звіт зроблено 2026-11-28 на вимогу власника: «звір нарешті залізо, і опублікуй звіт».
Уся робота з обладнанням була **read-only**. Не виконувалися RM-ioctl, MMIO-записи,
GPU compute, boot/reboot, зміни firmware, APPLY-дії та PR #21. Паролі й приватні
ключі не зберігалися.

Позначки: `runtime-proven` — спостереження живої системи; `statically proven` —
доведено з shipped-артефакта; `UNPROVEN` — немає доказу; `coverage limitation` —
інструмент не зміг побачити ділянку, це не доведення відсутності.

## 1. Залізо (read-only)

Джерела: `Get-CimInstance Win32_VideoController`, `nvidia-smi --query-gpu=...`
(Windows), `nvidia-smi -L` (WSL Ubuntu-24.04). Час звірки — 2026-11-28.

| Параметр | Спостереження | Статус |
|---|---|---|
| GPU | `NVIDIA GeForce GTX 1050 Ti` | `runtime-proven` |
| PCI-адреса | `00000000:01:00.0` (nvidia-smi), `PCI\VEN_10DE&DEV_1C82&SUBSYS_33511462&REV_A1\4&2DB3ECDA&0&0008` (CIM) | `runtime-proven` |
| Vendor / device | `10de:1c82` (GP107) | `runtime-proven`, збігається з pinned ABI |
| Драйвер Windows | `32.0.15.8278`, дата драйвера `25.06.2026`; `nvidia-smi` показує гілку `582.78` | `runtime-proven` |
| UUID, який показує драйвер | `GPU-9fe583f9-037d-e98f-aaa1-a37a9781012d` — однаковий у Windows `nvidia-smi` і WSL `nvidia-smi` | `runtime-proven` для факту повідомлення; **`UNPROVEN**, що це той самий байт-масив, який `cuDeviceGetUuid` читає з `device+0xc06` |
| Відеопам'ять | `4096 MiB` total, `754 MiB` used, `3251 MiB` free (CIM `AdapterRAM` = `4293918720` ≈ 4095 MiB — наближене значення з CIM) | `runtime-proven` |
| Температура | `29 °C` у момент звірки | `runtime-proven`, миттєве значення |
| Поточний режим | `1920x1080` | `runtime-proven` |
| `power.draw` | `[N/A]` для цього SKU | `coverage limitation` |

WSL не показує `/sys/bus/pci/devices/0000:01:00.0/*` (немає PCI-passthrough в цій
WSL2-сесії), хоча `nvidia-smi` у WSL працює через WSL GPU-міст. Це
`coverage limitation`, не доказ відсутності пристрою.

## 2. Що це дає для RE

- Польова відповідність `10de:1c82` для GP107 підтверджена на живій машині й
  збігається зі статичними контрактами репозиторію — `runtime-proven`.
- Новий факт: драйвер exposing UUID через `nvidia-smi` як `GPU-…`. Зв'язок цього
  рядка з 16 байтами `device+0xc06` / `UVM_REGISTER_GPU` лишається `UNPROVEN`:
  потрібне окреме статичне трасування або узгоджений read-only witness.
- `BDF ↔ RM gpu_id` — **`UNPROVEN`**. Ні nvidia-smi, ні CIM не дають RM gpu_id.
- Не робився жоден ioctl-виклик, тому ioctl- BIOS/UEFI/BAR/BDF поведінка не
  перевірялася динамічно.

## 3. Інструментобуд, зроблений доступним

| Інструмент | Версія | Де | Статус |
|---|---|---|---|
| Rizin | `0.9.1`, commit `c3a90e9226d977f58f4e9c75f78fa6b07afe13c7` | `C:\Tools\rizin\...\bin\rizin.exe`; копія `C:\Users\juv4u\.bun\bin\rizin.exe` | доступний з будь-якої сесії |
| REA через MCP | `rea-agents`, Ghidra-провайдер `12.2` | конфіг `C:\Users\juv4u\.config\opencode\opencode.json` | `opencode mcp list` → `✓ rea connected`; `binary_session` → ghidra `available` |
| Ghidra | `12.2_PUBLIC` | `C:\Tools\ghidra\ghidra_12.2_PUBLIC` | `GHIDRA_INSTALL_DIR` передається тепер у самому MCP-конфізі |
| JDK | `25.0.5.102-hotspot` | `C:\Program Files\Microsoft\jdk-25.0.5.102-hotspot` | `java`/`javac` доступні |
| Git / gh | `2.56.1.windows.1` / `2.106.0` | shim-и в `C:\Users\juv4u\.bun\bin` | доступні навіть у старих процесах із застарілим PATH |
| FPC | `3.2.2` (WSL Ubuntu 24.04) | встановлено через `apt` | збігається з піном репозиторію |
| GCC | `13.3.0` (WSL) | встановлено через `apt` | доступний |
| bash / make | `5.2.21` / `4.4.1` (WSL) | вже були | доступні |

Ghidra-сесія перевірена на невеликому PE: `C:\Windows\System32\nvcuda.dll`,
SHA-256 `60a0f34f4e28bd305a1fe009635ccd62e7f4b6ed1500692adaf4a0eeb2cd0a91`,
`binary_overview` → 2439 процедур, 9 сегментів (Evidence
`ev_6c0c5baec7be3893e281ca4e90a1b1cd776c2877148e1e2e6ab897057f7b4f14`).
Для 34 МБ `nvcuda64.dll` стартового таймауту 330 с не вистачило; таймаут піднято
до 600 с у runtime і до 900000 мс у конфізі MCP на майбутні запуски. Це
`coverage limitation`, а не помилка артефакта.

Поточна рекомендація агентам: **Rizin** — для адрес, opcode, xref, SHA-pinned
перевірок; **REA Ghidra** — для типів і cross-check тупих ділянок. Ghidra-псевдокод
не копіювати в документи — фіксувати лише адреси й статуси.

## 4. Статичні гейти

Гейти прогнано в LF-копії репозиторію в temp ( робоче дерево власника не змінено):
WSL Ubuntu 24.04, FPC 3.2.2, GCC 13.3.0.

- `make test-valid-cards-static` — OK.
- `bash scripts/test-evidence-manifest.sh` — `MANIFEST-SUMMARY verified=142 known_bad=1 negative_controls=1`.
- `bash scripts/test-gp107-matrix-collector.sh` — `MATRIX-COLLECTOR-OK gpu-runtime=NOT_RUN manifest=verified`.
- `bash scripts/check-no-driver-overreach.sh` — `DRIVER-FIREWALL-OK`, заборонені операції відсутні.

Примітка: у Windows-клоні скрипти мають CRLF, тому bash у WSL падає на
`set -o pipefail`. Це не дефект репозиторію, а наслідок `core.autocrlf`; для
локальних перевірок використовуйте LF-копію або `git -c core.autocrlf=input clone`.

## 5. Склоновані авторські репозиторії

Усі — з `https://github.com/juv4uk/`, стан `main`, поверхневий клон (`--depth 1`), крім
перших двох (повні):

- `C:\Users\juv4u\GitHub\gp107-nvidia-re` — цей репозиторій.
- `C:\Users\juv4u\GitHub\wsm-desktop` — Guix System desktop, канал-скелет, реліз-запит rc6.
- `C:\Users\juv4u\GitHub\sens`
- `C:\Users\juv4u\GitHub\cml`
- `C:\Users\juv4u\GitHub\wsm-os-lisp`
- `C:\Users\juv4u\GitHub\wsm-target-contract`
- `C:\Users\juv4u\GitHub\wsm-lazarus`
- `C:\Users\juv4u\GitHub\wsm-cuda`
- `C:\Users\juv4u\GitHub\wsm-os`
- `C:\Users\juv4u\GitHub\wsm`

## 6. Координація з web-агентами

Три read-only розвідки (gp107-беклог, `wsm-desktop`/Guix, офіційна Guix-доктрина)
дали три узгоджені рекомендації:

1. **Канал.** У `wsm-desktop` вже є `.guix-channel`, простір `wsm/` і
   `channels.lock.scm`. Бракують `.guix-authorizations`, ключовий `keyring`-branch
   і підписану інтродукцію; `wsm-tools` має нерозв'язану ліцензію (#367).
   Готувати локально, без публікації introductions/ключів без окремого рішення.
2. **Інсталятор.** Не патчити upstream `guix-install.sh`: це root-бутстреп на
   чужій системі, який `guix pull` не оновлює. Зміни робити у WSM-скриптах/
   маніфестах, зберігаючи `APPLY`-disabled і diagnostic-only режим.
3. **Реліз.** `RELEASE-REQUEST.txt` просить `0.1.0-rc6-minimal-live`, але прямо
   вимагає окремого рішення власника про публікацію. Матеріали підготовлені,
   тег/release не створювалися.

Цей звіт опубліковано звичайним push-ом у публічний `master`. **Тег, GitHub Release
і announce не створювалися** — для них потрібна окрема явна вказівка.

## 7. Відкриті питання

1. Чи збігається `GPU-9fe…` з UUID у `device+0xc06`?
2. Який Windows IOCTL реєструє GPU і куди копіюється 16-байтний UUID?
3. Хто виробляє вихідні 16 байт для writer-ів `0x1804096ef` / `0x18036d645`?
4. Як `BDF / D3DKMT` перетворюється на RM `gpu_id`?
5. Який саме канал вважати канонічним: поточний `wsm-desktop` чи окремий репо?
6. Чи давати дозвіл на rc6 tag/release і на публікацію keyring/authorizations?
