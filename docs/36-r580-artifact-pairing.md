# 36 — R580: pairing shipped-артефакта, REA-тарґета й завантаженого модуля

Це не новий реверс-код і не physics-тест. Це **read-only host inventory**, який
закриває важливу прогалину provenance: усі REA P1-висновки в
[`docs/23–28`](25-rea-p1-uvm-caller-map.md), [`docs/34`](34-rea-p1-parent-object-and-test-context.md)
і [`docs/35`](35-rea-p1-btf-type-proof.md) зроблено з розпакованого shipped
`nvidia-uvm.ko`. Тут **`runtime-proven`** показано, що цей самий build-ідентитет
є встановленим і завантаженим у ядрі на цій машині.

Не скопійовано vendor source, blob чи Ghidra-pseudocode: використано лише
пакетну/DKMS-метадату, SHA-256, `modinfo`, `readelf -n` і sysfs `notes`.
Жодного MMIO, RM-ioctl, unbind, reboot, write, firmware чи PR #21.

## 0. Triage

| Позначка | Що | Рішення |
|---|---|---|
| `ALREADY_DONE` | Pairing shipped `.ko.xz` ↔ DKMS-output ↔ unpacked REA target ↔ loaded module build-id | цей звіт |
| `PARTIAL` | Старіші REA bundles фіксують SHA тарґета, але не мають окремого sysfs build-id witness | цей звіт додає witness; bundles лишаються історичними й не переписуються |
| `UPSTREAM_EXISTS` | Nouveau/NVKM/NVK як implementation authority | не реверсити; див. docs/35 |
| `UNIQUE_GAP` | Safe GP107 BAR0 offset, RM/fence lifecycle, фізичний NVK↔NVIDIA A/B | лишається `UNPROVEN` / `NOT RUN`, не тут |

Pin-и v8/v9, SENS, CML, `wsm-os-lisp`, ADR, target contract, ABI-pin v8 і
asm-first контракт [`docs/33`](33-asm-first-target-contract.md) не змінено.

## 1. Артефакти й інструменти

| Роль | Шлях | SHA-256 | Статус |
|---|---|---|---|
| Shipped/Installed UVM | `/lib/modules/7.2.15+kali-amd64/updates/dkms/nvidia-uvm.ko.xz` | `80132204f76981b2373baeb936866347e3c80e8527feb118bffe03f6adc10e8f` | `runtime-proven` |
| Shipped/Installed RM | `/lib/modules/7.2.15+kali-amd64/updates/dkms/nvidia.ko.xz` | `f19b0531bf269ebe715790b17173cc3110ebdccf9239f1d397ca034254953062` | `runtime-proven` |
| DKMS-built UVM | `/var/lib/dkms/nvidia/580.196.11/7.2.15+kali-amd64/x86_64/module/nvidia-uvm.ko.xz` | `80132204f76981b2373baeb936866347e3c80e8527feb118bffe03f6adc10e8f` | `runtime-proven`, `cmp rc=0` |
| DKMS-built RM | `/var/lib/dkms/nvidia/580.196.11/7.2.15+kali-amd64/x86_64/module/nvidia.ko.xz` | `f19b0531bf269ebe715790b17173cc3110ebdccf9239f1d397ca034254953062` | `runtime-proven`, `cmp rc=0` |
| Unpacked REA target (UVM) | `/tmp/opencode/rea-nvidia-uvm/nvidia-uvm.ko` | `81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` | `runtime-proven`; ціль docs/35 |
| Unpacked RM | `/tmp/opencode/rea-nvidia-uvm/nvidia.ko` | `95c5fa5ab0546ee40842cda2ec20ea3ec1e196a5afee1580944ecae2ffc75bbe` | `runtime-proven`; ціль docs/24 |
| Сирий witness | `evidence/driver-pairing-20261128/artifact-pairing.txt` | `b6db7f53d1fa91c3a44517ffe20d4313eb5a6b95cd2052f1f7190f368ee47dc5` | `runtime-proven`, 140 рядків |
| DKMS `make.log` | `/var/lib/dkms/nvidia/580.196.11/7.2.15+kali-amd64/x86_64/log/make.log` | `7c133c82f200fad07ad6a4fc50bfe81d21ec488436dbb860ab66460027ddad26` | `runtime-proven`, line pointers 5/47961/47964/47968/47972 |

Інструменти (версії зафіксовані в witness): `dpkg-query 1.23.11`, `dpkg 1.23.11`,
`dkms 3.2.2`, `GNU readelf (Binutils for Debian) 2.47.50.20261021`,
`xz 5.8.4`, `kmod 34.2`, `sha256sum`/`od` (GNU coreutils) 9.12.

У цьому звіті **немає REA-адрес, функцій, xrefs чи caller/callee**: це не
disassembly, а identity-ixer. Для адрес і Evidence ID див. docs/23–28, 34–35;
там само вказано `artifact_sha256_after`,tool/version і coverage limits.

## 2. Ланцюг pairing — `runtime-proven`

| Крок | Спостереження | Статус |
|---|---|---|
| 1 | `dpkg-query -W`: `nvidia-driver 580.196.11-1`, `nvidia-kernel-dkms 580.196.11-1`, source `nvidia-graphics-drivers`; `dpkg -V nvidia-kernel-dkms` → `rc=0`, 0 B stdout/stderr | `runtime-proven` |
| 2 | `dkms status nvidia` → `nvidia/580.196.11, 7.2.15+kali-amd64, x86_64: installed` | `runtime-proven` |
| 3 | `make.log` рядок 5: `make -j4 KERNEL_UNAME=7.2.15+kali-amd64 … modules`; рядки 47968/47972: `LD [M] nvidia-uvm.ko` / `LD [M] nvidia.ko`; проміжні 47961/47964 — `MODPOST`/`nvidia-uvm.mod.o` | `runtime-proven`, line-only witness |
| 4 | SHA встановлених `.ko.xz` = SHA DKMS-виходів; `cmp -s` → `nvidia rc=0`, `nvidia-uvm rc=0` | `runtime-proven` |
| 5 | Розпакування дає точні SHA цілей REA: `81b21527…` (UVM) і `95c5fa5a…` (RM) | `runtime-proven` |
| 6 | `modinfo`: `version=580.196.11`, `vermagic=7.2.15+kali-amd64 SMP preempt mod_unload`; `srcversion` = `65626331C62C6702B5D95C0` / `FCB6D1F791D311E34BEF9A5` | `runtime-proven` |
| 7 | `readelf -n` розпакованих файлів: Build ID `c0007bbb496887617532fcb7fc7ef8521c6a853f` (RM) і `3ca683724fec50f550c2a7666394569e814f5691` (UVM); Linux notes містять `7.2.15+kali-amd64` | `runtime-proven` |
| 8 | sysfs `/sys/module/{nvidia,nvidia_uvm}/version` = `580.196.11`; `srcversion` збігається з `modinfo` (`MATCH rc=0`); `notes/.note.gnu.build-id` збігається з `readelf -n` (`MATCH rc=0`) для обох модулів | `runtime-proven` |

`dpkg-query -S` не знаходить шляхів DKMS-виходів — це очікувано: вони
генеруються під час збірки, а не належать dpkg-запису. Це **`runtime-proven`**
факт про packaging, не ознака підміни.

### Висновок про ідентичність

**`runtime-proven`**: розпакований REA-тарґет
`81b21527017a096f8276e7b93d04e82a414d03ac3b6a0831f9acba3a4ac488b6` — це
розпакована форма встановленого `nvidia-uvm.ko.xz` `80132204…`, байтово
рівного DKMS-виходу, з тим самим `version`, `vermagic`, `srcversion` і GNU
Build ID, які ядро експортує для завантаженого `nvidia_uvm`. Отже BTF із
docs/35 належить саме тому build-у, що працює на цій машині.

**`runtime-proven`** те саме для `nvidia.ko` / завантаженого `nvidia`: це
стосується REA-вікон RM dispatch у docs/24.

**`UNPROVEN`**: побайтова рівність *resident* memory після завантаження —
ядро застосовує relocations; цей стан не читався (`/proc/kcore`, module memory
не використовувалися) і не потрібен для build-ідентичності.

## 3. Межі, відкриті питання, найменший крок

| Відкрите питання | Статус | Найменший крок |
|---|---|---|
| Прямі caller-и `add_gpu @ 0x0801c120` і повний прототип | `UNPROVEN`; `axt` порожньо → coverage limitation, не absence-proof | targeted Rizin-вікна в межах відомих symbol-range, шукати прямий `call 0x0801c120`; без broad `/r`, `/c`, `izz~` |
| Safe GP107 BAR0 register offset | `UNPROVEN`; API лишається `read-safe-offset-unproven`, code 21 | вивести зі shipped-артефактів + окрема owner-авторизація до будь-якого фізичного read |
| Причина NVK↔NVIDIA compute gap | `UNPROVEN` | фізичний A/B на реальній `10de:1c82` з `VK_DRIVER_ID_MESA_NVK`, BDF-assert, fence, readback, CPU checksum |
| `BOOT0`, `0x137000A1` | `string-only` / `UNPROVEN` | не змінювати без окремого доведення |
| RM class/runlist/notifier/fence | `UNPROVEN` | вузькі REA-вікна; без RM-ioctl на реальному GPU |

`NOT RUN`: фізичний MMIO, RM-запити, GPU compute, unbind/boot/reboot, PR #21,
release/tag/publish, installer. HOST_VISIBLE throughput і надалі не називається
VRAM bandwidth; жоден висновок про продуктивність одним запуском не робиться.

## 4. Що змінено

- додано `evidence/driver-pairing-20261128/artifact-pairing.txt` (сирий witness);
- додано цей звіт;
- [`docs/35`](35-rea-p1-btf-type-proof.md) і `README.md` отримали посилання на pairing;
- вихідний код, asm, Pascal, gate-и, target contract і ABI-pin — без змін.

Повторно запущено `bash scripts/test-capability-driver.sh`; результат зафіксовано
у commit-повідомленні. Коміт і пуш виконано; `/home/agents/open-driver-identity`
синхронізовано fast-forward.
