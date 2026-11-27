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
   `FpMMap(nil, 4096, PROT_READ, MAP_SHARED, fd, 0)`.
5. При будь-якій відмові друкує `BOOT0: UNPROVEN`, `G1-FAIL-CLOSED-OK` і
   завершується успішно: це негативний свідок, а не збій інфраструктури.

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
| `resource0 open` як звичайний користувач → `EACCES` (13) | **runtime** | `ls -l`: `-rw------- root root`; гейт вимагає саме цей маркер |
| `resource0 mmap(PROT_READ\|MAP_SHARED)` як root → `EINVAL` (22) | **runtime** | окремий запуск `sudo ./02_bar_identity`; у гейті не автоматизований |
| Причина `EINVAL` — exclusive-володіння BAR0 драйвером `nvidia` | **інтерпретація** | `driver → /sys/bus/pci/drivers/nvidia`; Linux `pci_mmap_resource` відмовляє для exclusive-регіонів. Прямо з ядра це тут не перевірено |
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
bash scripts/test-pascal-probe.sh          # обидва пробники, green
sudo ./pascal/02_bar_identity              # root-свідок: EINVAL, BOOT0 unproven
```

Очікуваний фінальний рядок гейту:

```text
PASCAL-PROBE-GATE-OK fpc=3.2.2 static=yes no-libc=yes gpu=10de:1c82 bar0=fail-closed boot0=unproven
```

## Фаза 03 — RM arch info (не запущена)

Кандидат `NV2080_CTRL_CMD_MC_GET_ARCH_INFO` (клас `0x2080`) поки **не підтверджений**:

- literal-назви немає в `/usr/src/nvidia-580.196.11` (публічні headers R580); знайдено лише коментарі `NV2080_CTRL_MC_ARCH_INFO_ARCHITECTURE_*` у `common/inc/nv_uvm_types.h`;
- REA-інвентар рядків `libcuda.so.580.196.11` не містить `NV2080_CTRL_CMD` (`ev_514422e5d7733e0417243209387c8ed82d57d912dbc2734ef42a70c4b64773ac`).

Тому `03_rm_arch_info.pas` **не створюємо як «доведений шлях»**. Фаза 03 — окреме research-завдання: знайти cmd id і struct layout або чесно зафіксувати `UNPROVEN`. Навіть позитивний RM-результат дає arch/implementation і лишається окремим каналом — він не перетворює BOOT0 на прочитаний регістр.

## Інструментарій, на якому це перевірено

FPC 3.2.2 (`3.2.2+dfsg-51`), Ghidra 12.2 + OpenJDK 25, REA MCP,
`kali-tools-reverse-engineering` (rizin, jadx, ltrace, yara), strace 7.3,
CUDA 12.6.3 / nvcc 12.6.85, драйвер `580.196.11-1`, `gh` 2.106.0,
Python 3.14.10, Node 24. `cargo` відсутній — потрібен лише для CML,
не для цього зрізу.
