# 55 — Windows reverse-scope: локальні артефакти GP107 (582.78)

## 0. Письмовий дозвіл власника

Власник прямо написав (UA, поточний сеанс, зафіксовано `2026-11-28T05:30:51Z`):

> «в тебе є перевага і особливість, ти на віндовсі, моє залізо тут не змінилося, тому реверси що є на віндовсі»

Це **written owner instruction** для статичного реверсу пропрієтарних бінарників, які реально встановлені на цій Windows-машині з GP107. Попередній англійський коментар у Issue #62 від `2026-11-28T03:59:46Z` власник відкликав як не свій; цей документ спирається **тільки** на наведене вище речення.

## 1. Точні артефакти (read-only інвентаризація)

Метод: `Get-PnpDevice` / `Get-PnpDeviceProperty` / `Get-FileHash -Algorithm SHA256`. Будь-який запуск драйвера, GPU, CUDA/Vulkan, ioctl — не виконувався.

| Властивість | Значення | Статус |
|---|---|---|
| GPU | `PCI\VEN_10DE&DEV_1C82&SUBSYS_33511462&REV_A1\4&2DB3ECDA&0&0008` | `INVENTORY_OBSERVED` |
| PnP Status | `OK` | `INVENTORY_OBSERVED` |
| Активний драйвер | `32.0.15.8278` (branch `582.78`), `oem7.inf` | `INVENTORY_OBSERVED` |
| DriverStore каталог | `nv_dispi.inf_amd64_58519edca6172ba9` | `INVENTORY_OBSERVED` |
| `nvcuda64.dll` | 34 562 280 байт, SHA-256 `af853a5b0f3ce3eedc297c66cf5e03307112aa31c714b82479a2ae841c92d407` | `INVENTORY_OBSERVED` |
| `nvlddmkm.sys` | 110 691 560 байт, SHA-256 `ae93846067fbb17327d0fc970ce23c533922e811199830d5ac469523c9ca78a3` | `INVENTORY_OBSERVED` |
| `nvwgf2umx.dll` | 93 249 280 байт, SHA-256 `54326941231f64fbafea9b04a975daf800b862fdb5fcd06fc5f468386549f742` | `INVENTORY_OBSERVED` |
| Другий набір у Store | `32.0.15.6094`, `nvcuda64.dll` SHA-256 `59b88c90da154d79576599a4170e0ec05e244f8477d82dbfa22b80bb0bf508ac` | `INVENTORY_OBSERVED`, не активний |

Hach активного `nvcuda64.dll` **збігається** з артефактом, описаним у `docs/53` і `docs/45`. Це `runtime-proven` pairing для самого файлу на диску (не для GPU-стану). Повний перелік із hach-ами — `evidence/windows-20261128/windows-driver-inventory.json`.

## 2. Межі дозволу на цей сеанс

Дозволено (статичний lane C, за письмовим дорученням власника вище):

- read-only інвентаризація файлів і hach-ів;
- targeted static disassembly/xrefs/dataflow через Rizin (REA), тільки на перелічених вище hach-ах;
- фіксаціяEvidence-ID, tool version, coverage limitations і власних висновків;
- публікація звітів у `docs/` із позначенням статусів.

Не дозволено без окремого погодження:

- запуск `nvcuda64.dll`, `cuInit`, NVML, CUDA/Vulkan/OpenGL, будь-який RM/UVM/D3DKMT ioctl, GPU submit;
- BPF/kprobe/ftrace/perf, driver unbind/switch, BAR/MMIO/BOOT0, firmware/VBIOS, reboot;
- копіювання vendor source або великих фрагментів vendor pseudocode/disassembly у документи;
- tag, GitHub Release, rc6, keyring, WSM/release manifest, upstream installer;
- аналіз неактивного набору `32.0.15.6094` — він тут лише для повноти інвентаризації.

## 3. Що важливо для координації

Issue #62 вимагав письмового scope/clearance саме для бінарного hach-, методів і сфери публікації. Цей документ їх фіксує: hach `af853a5b…`, методи — Rizin static read-only, сфера — `docs/` + evidence, без runtime і без release. `docs/53` і його evidence наразі **прибрані** з `master` (`a291d6e`, `b1c6a6e`) і збережені приватно в `draft/doc53-uncleared`; цей документ не відновлює їх автоматично.

## 4. Статуси тверджень

| Твердження | Статус |
|---|---|
| Файл `nvcuda64.dll` з hach `af853a5b…` фізично присутній на цій Windows-машині | `runtime-proven` (filesystem inventory) |
| Активний драйвер GP107 — `32.0.15.8278` | `runtime-proven` (PnP) |
| Hach збігається з тим, що аналізувався в `docs/53` | `runtime-proven` (SHA-256 level) |
| Будь-який новий висновок про UUID producer / `0x22e034` / BDF↔RM | поки `UNPROVEN`, див. окремі звіти |
