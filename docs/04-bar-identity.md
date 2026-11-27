# 04 — BAR0 identity: два джерела, один fail-closed результат

Мета зрізу G0/G1 — не «прочитати регістр будь-якою ціною», а показати,
які факти про GPU доступні **до** будь-якого драйверного рішення, і де
hosted-середовище ставить межу.

## Що зроблено

`pascal/02_bar_identity.pas` послідовно:

1. Отримує перший валідний GPU через `NV_ESC_CARD_INFO` (`/dev/nvidiactl`).
2. Незалежно читає PCI config space через sysfs за BDF, отриманим від кроку 1.
3. Звіряє `vendor:device` і BAR0 між двома джерелами; розбіжність = `exit 2`.
4. Відкриває `resource0` **тільки** `O_RDONLY` і викликає
   `FpMMap(nil, 4096, PROT_READ, MAP_SHARED, fd, 0)` **тільки після успішного open**.
5. Відмови розділені за названими станами:
   `OPEN_DENIED` означає, що `mmap` взагалі не виконувався;
   `MMAP_DENIED` означає, що `open` відбувся, а read-only мапінг відмовлено.
   Обидва стани друкують `BOOT0: UNPROVEN`, `G1-FAIL-CLOSED-OK` і завершуються
   успішно: це негативні свідки, а не збій інфраструктури. Причину відмови
   програма не стверджує — маркер `MMAP-DENIAL-CAUSE: UNPROVEN`.

У коді немає `PROT_WRITE`, `MAP_FIXED`, `O_RDWR`, `FpWrite` чи `pwrite`.
Гейт `scripts/test-pascal-probe.sh` перевіряє це **по коді**, попередньо
зрізаючи Pascal-коментарі (`{ }` та `//`), щоб заборона не спрацьовувала
на текст пояснень.

## Свідки за станом доказу

| Факт | Стан | Джерело |
|---|---|---|
| PCI config `10de:1c82`, BAR0 `0xee000000` | **runtime** | `FpPRead` sysfs `.../0000:01:00.0/config`, offset 0x00/0x02/0x10 (little-endian) |
| `NV_ESC_CARD_INFO` дає той самий `10de:1c82` і BAR0 `0xee000000+0x1000000`, `minor=0` | **runtime** | clean-room ioctl, той самий шлях, що й у `01_min_cuinit` |
| Два джерела збігаються | **runtime** | маркер `CROSS-CHECK-OK` у гейті |
| `OPEN_DENIED`: `resource0 open` як звичайний користувач → `EACCES` (13), `mmap` не викликався | **runtime-proven** | `ls -l`: `-rw------- root root`; гейт вимагає маркери `BAR0-STATE: OPEN_DENIED` і `BOOT0: UNPROVEN (open denied; MMIO not attempted)`; негативна перевірка забороняє будь-який звіт про mmap у цій гілці |
| `MMAP_DENIED`: `resource0 mmap(PROT_READ\|MAP_SHARED)` як root → `EINVAL` (22) | **runtime-proven** | окремий запуск `sudo ./02_bar_identity`; у базовому гейті не автоматизований |
| `EACCES` доводить ексклюзивне володіння BAR0 драйвером | **не доведено** | `EACCES` показує лише відмову open для цього uid; програма не робить і гейт не приймає такого твердження |
| Причина `EINVAL` — exclusive-володіння BAR0 драйвером `nvidia` | **не доведено / UNPROVEN** | можлива **інтерпретація** за `driver → /sys/bus/pci/drivers/nvidia` і Linux `pci_mmap_resource`, але з ядра це тут не перевірено; програма друкує `MMAP-DENIAL-CAUSE: UNPROVEN` |
| `NV_PMC_BOOT_0` для GP107 = `0x137000A1`, маска chipset `$FFF00000` → `$137` | **string-only / гіпотеза** | публічний коментар `/usr/include/libdrm/nouveau/nvif/cl0080.h`: «chipset from NV_PMC_BOOT_0»; значення **не прочитано** на цій машині |
| BOOT0 взагалі прочитаний на host | **не доведено й не стверджується** | див. два негативні свідки вище |

Реалізація читання BOOT0 у пробнику є, але гілка виконується тільки якщо mmap
успішний. На цій машині вона не виконується — тому жодне значення регістра
не потрапило в документацію.

## REA-свідки (статичний аналіз `libcuda.so.580.196.11`)

SHA-256 `20ad440390dad2c5fd06c14e518990512a8e7b31f8b6add7bb1581832fd4d331`,
Ghidra 12.2 через REA. Псевдокод у репозиторій не переноситься — лише
наявність/відсутність у інвентарі та адреси.

| Питання | REA Evidence | Що показано |
|---|---|---|
| Які device-ноди відомі бібліотеці? | `ev_3c907a7d2445bfe7b645072bc1e232175242a090ee44983e9ba5e43d5ce005d7` | 14 рядків `/dev/nvidia*`: `nvidiactl`, `nvidia%d`, `nvidia-uvm`, `nvidia-modeset`, `nvidia-caps`, … |
| Чи є в інвентарі рядків `BOOT_0`? | `ev_4668ff2598fe075d77989eeb7ec554c6b0ef35b1994183214b3a6cf6eb9d8bd0` | 0 збігів. Обмеження: це інвентар рядків Ghidra, а не довільні байти ELF |
| Чи є імена RM-команд `NV2080_CTRL_CMD`? | `ev_514422e5d7733e0417243209387c8ed82d57d912dbc2734ef42a70c4b64773ac` | 0 збігів у інвентарі рядків — тобто шлях до BOOT0 через іменовану RM-команду тут не знайдено |
| Чи є `PMC` / `BOOT_0` / `chipset` у рядках? | `ev_ec1aa014bf464a9d8d6a25fd044ed527e43ac1601cbc872e86d42c11add4eafe` | 0 збігів |
| Чи є `GET_ARCH` / `ARCH_INFO` / `MC_ARCH` у рядках? | `ev_6da5600bbf853c468595fb3c1dcc8cbdcfd67b6d46f97fea67858a5ed59c6d0f`, `ev_72a09f3cdedeaff12c74f8a7cf417adb952bda8358200aea82306d48b3a284c0`, `ev_c0dafaf806f860fb94cadbeae00eff6466687b2c92aac7831d842b8d4273d85b` | 0 збігів |
| Чи є процедури з іменем `nv2080`? | `ev_77772da4c98eabd6a457d9f0be88df38f693156c49e302348d8b71853ae121e1` | 0 збігів |
| Де лежить `cuDeviceGetAttribute`? | `ev_9086e25fc2cef32fc2ad6e6ecdb46e5e4e13f5f26dffbf465b8435b4c2b67ef0` | `0x428050`, не thunk |
| Чи доступна декомпіляція? | `ev_d21438e9640d1a1cabdc92cb47b41e5e14fce625ffb1d32d478ab31e0ed17343` | так, 920 UTF-16 code units; у репо не копіюється |

Висновок з REA обмежений і чесний: у **інвентарі рядків** libcuda немає
ані `BOOT_0`, ані імені RM-команди `NV2080_CTRL_CMD`. Це не доводить, що
бібліотека ніколи не читає BAR0 через числові константи, — але й не дає
підстави стверджувати, що такий контроль існує в цій збірці.

## Наслідок для capability в `wsm-os-lisp`

1. `PciConfig` може бути вузькою (vendor/device + BAR base з config space): обидва поля вже мають два незалежні свідки.
2. `Mmio` має бути **окремою** capability з явним read-only профілем; hosted-приклад показує, що наявність BAR0 у PCI config ще не дає права на мапінг.
3. Жодного рядка про NV_PMC у ADR доти, доки BOOT0 не буде прочитано на firmware/bare-metal seams або через доведений RM-контроль.
4. ABI v8→v9 у `wsm-target-contract` залишається передумовою, а не наслідком цього зрізу.

## Відтворення

```bash
make test                                  # три пробники, green, без sudo
make gate-root                             # опційний root-свідок; за потреби SUDO_FLAGS=-S
sudo ./pascal/02_bar_identity              # той самий root-свідок вручну
```

`gate-root` **не входить** до базового `test`: основний гейт лишається
детермінованим і виконується звичайним користувачем (`OPEN_DENIED` → fail-closed).
Root-свідок перевіряє іншу гілку: `open` OK → `MMAP_DENIED` (`EINVAL`) →
`BOOT0 UNPROVEN` → причина відмови `UNPROVEN`.

Очікуваний фінальний рядок гейту:

```text
PASCAL-PROBE-GATE-OK fpc=3.2.2 static=yes no-libc=yes gpu=10de:1c82 bar0=fail-closed rmarch=runtime-proven boot0=unproven
```

## Фаза 03 — RM arch info: runtime-proven окремий канал

**Statically proven (публічний ABI, не з libcuda):**

- `NV2080_CTRL_CMD_MC_GET_ARCH_INFO = 0x20801701` — публічний SDK-заголовок
  `src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080mc.h` у
  `NVIDIA/open-gpu-kernel-modules`; незалежно збігається з
  `gvisor/pkg/abi/nvgpu/ctrl.go:822` (Apache-2.0/BSD-3-Clause/MIT).
- `NV2080_CTRL_MC_GET_ARCH_INFO_PARAMS`: `NvU32 architecture`,
  `NvU32 implementation`, `NvU32 revision`, `NvU8 subRevision`; C-розмір 16
  через вирівнювання.
- Команди `0x205` / `0x214` / `0x215` і структури
  `GPU_GET_ID_INFO_V2_PARAMS` (32 B), `GPU_GET_PROBED_IDS_PARAMS` (384 B),
  `GPU_ATTACH_IDS_PARAMS` (132 B) — публічний
  `ctrl0000/ctrl0000gpu.h`. `NV0080_ALLOC_PARAMETERS` має 56 B; перші два
  поля — `deviceId` та `hClientShare`. Розміри збігаються з trace
  (`0x20`, `0x180`, `0x84`).
- Локальний `/usr/src/nvidia-580.196.11/nvidia-uvm/ctrl2080mc.h` дає
  `ARCHITECTURE_GP100 = 0x130`; публічний `src/common/inc/swref/published/nv_arch.h`
  дає `GPU_IMPLEMENTATION_GP107 = 0x07`. Це ABI-таблиці, **не виміряні значення**.
- REA-негатив лишається чинним: в інвентарі рядків libcuda немає
  `NV2080_CTRL_CMD` (`ev_514422e5d7733e0417243209387c8ed82d57d912dbc2734ef42a70c4b64773ac`).
  Шлях у цій збірці йде через числові константи, а не через імена, —
  **`interpretation`**, не доведена поведінка.

**Runtime-proven (власний LD_PRELOAD-зонд на `cuInit(0)`, `/tmp`, до репо не входить):**

Власний shim на `ioctl` показав точний порядок, якого не видно в `strace`
(`strace` бачить лише номер, напрям і розмір, не вміст буфера):

```text
open /dev/nvidia0 → NV_ESC_SYS_PARAMS → alloc 0x41
→ GPU_GET_PROBED_IDS(0x214, gpu=0x100)
→ GPU_ATTACH_IDS(0x215, paramsSize=0x84, status=0)
→ alloc NV01_DEVICE_0(0x80): deviceId=0, hClientShare=client, status=0
→ alloc NV20_SUBDEVICE_0(0x2080), status=0
→ MC_GET_ARCH_INFO(0x20801701, paramsSize=0x10, status=0)
   params: arch=0x130 impl=0x07 rev=0xa1 subrev=0x02
```

Тому попередня відмова була не «демонстрацією недоступності RM», а наслідком
пропущених кроків: у першому зонді не було відкритого `/dev/nvidia0` і
`GPU_ATTACH_IDS`, а `deviceId` було помилково взято як PCI-ідентифікатор
`0x1c82`. Після виправлення `status=0` на всіх кроках. Чому саме ядро
відмовляло в першому варіанті (`0x1f` / `0x1b`), ми не довели — це
**`interpretation`** за `gvisor/.../status.go`, а не твердження про ядро.

**Runtime-proven (канонічний FPC-зонд у репо):**

`pascal/03_rm_arch_info.pas` відтворює цей ланцюжок власним кодом, без
libcuda, з compile-time `SizeOf`-перевірками в `nv_rm.pas`:

```text
GPU_ATTACH_IDS            : gpu=0x100 status=0 deviceInstance=0 subDeviceInstance=0
NV2080_CTRL_MC_GET_ARCH_INFO: arch=0x00000130 impl=0x00000007 rev=0x000000A1 subrev=0x02
BOOT0: UNPROVEN (RM arch info is a separate channel)
RM-ARCH-OK
```

ELF статичний, без `DT_NEEDED`; `make test` зелений для всіх трьох пробників.

**Вибір GPU-вузла — runtime-proven, без хардкоду:** `pascal/03_rm_arch_info.pas`
викликає спільний `nv_device.SelectTargetCard()`, який через `NV_ESC_CARD_INFO`
шукає унікальну картку `10de:1c82`, повертає `minor_number` і будує шлях
`/dev/nvidia<N>` через `GpuDevicePath()`. Якщо збігів 0 або більше 1 — це
явний `RM-ARCH-FAIL`, а не вибір першої картки. На цій конфігурації:

```text
NV_ESC_CARD_INFO target   : 10DE:1C82 @ 0000:01:00.0 minor=0
GPU device node           : /dev/nvidia0
```

`devpars.device_id` лишається `0`: це **не** PCI device id `0x1c82`, і семантика
нуля окремо не підтверджена. Гейт забороняє literals `/dev/nvidia0` у коді
RM-зонда (коментарі зрізаються перед перевіркою).

**Межі висновку:**

- `arch=0x130` зіставлено з `ARCHITECTURE_GP100`, `impl=0x07` — з
  `GPU_IMPLEMENTATION_GP107`. Зіставлення **`interpretation`** (у відкритому
  R580-заголовку імені `NV2080_CTRL_MC_ARCH_INFO_IMPLEMENTATION_GP107` немає,
  хоча числові значення збігаються). Самі чотири числа — **runtime-proven**.
- `BOOT0` не читався: жодного `mmap resource0`, жодного `NV_PMC_BOOT_0`.
  `0x137000A1` лишається **`string-only`**; збіг `rev=0xa1` із суфіксом
  рядка — **`interpretation`**, не доказ регістра.
- RM- arch/implementation є окремим каналом: він не надає права на MMIO
  і не змінює discriminated union capability у `wsm-os-lisp`.

## Інструментарій, на якому це перевірено

FPC 3.2.2 (`3.2.2+dfsg-51`), Ghidra 12.2 + OpenJDK 25, REA MCP,
`kali-tools-reverse-engineering` (rizin, jadx, ltrace, yara), strace 7.3,
CUDA 12.6.3 / nvcc 12.6.85, драйвер `580.196.11-1`, `gh` 2.106.0,
Python 3.14.10, Node 24. `cargo` відсутній — потрібен лише для CML,
не для цього зрізу.
