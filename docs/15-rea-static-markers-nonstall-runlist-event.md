# 15 — REA: статичні маркери non-stall / runlist / event у пропрієтарному `nvidia.ko`

Це продовження `docs/11`, зроблене після `PHYSICAL_COMPUTE_TEST=PASS`. Мета —
зняти coverage-обмеження попереднього рядкового пошуку й перевірити, чи дає
пропрієтарний shipped-артефакт нові **статичні** факти для трьох відкритих
питань. Не робилось ані MMIO, ані RM-запитів, ані фізичного запуску, ані
псевдокоду/vendor source.

## Тарґет і відтворення

| Поле | Значення |
|---|---|
| Шипований артефакт | `/lib/modules/7.2.15+kali-amd64/updates/dkms/nvidia.ko.xz` |
| Розпакований для REA | `/tmp/opencode/rea-nvidia/nvidia.ko` |
| SHA-256 | `95c5fa5ab0546ee40842cda2ec20ea3ec1e196a5afee1580944ecae2ffc75bbe` |
| Формат | ELF64 ET_REL, x86-64, not stripped |
| REA-провайдер | `rizin` через `tools.rea.execute_rizin_command` |
| Ключ coverage | `search.str.max_region_size` піднято з `0xa00000` до `0x10000000` у межах одного виклику |

Попередній `izz~...` зазнавав помилки `Failed to generate interval list` через
`max region size 0xa00000`. Після підняття ключа рядковий інвентар відпрацював.
Ghidra двічі не вклався у startup (330 s, потім 600 s) на 138 MB модуль через
важкий автоаналіз; цей шлях не використовувався для фактів нижче. Порожній
результат рядкового/символьного інвентарю **не є** доказом відсутності.

Збережені Evidence-бандли:
- `evidence/rea-20261127/evidence-rizin-batch.json` — `sha256 7085fbed9eb37eed2f860bb9316b54b2ae4e70e19d1757b52c2c4d8fd7d0cd7f`;
- `evidence/rea-20261127/evidence-rizin-static-markers.json` — `sha256 86ea732def62cdbbb9307cf621b8053e09161a0083e23d7ee92c2e89d000eac8`;
- `evidence/rea-20261127/evidence-boot0-and-key-strings.json` — `sha256 83ea4b64d809f4f496c7f830150a78a2623b69ebb38519f449c192bebe6c446f`;
- `evidence/rea-20261127/evidence-notification-boot0-raw.json` — `sha256 c799a98f10207ad83c4cd1b44aa2066303ae140f89956e25bce3e4e1ec70ee09`.

## Статично доведено — наявність рядків і символів у готовому артефакті

| Факт | Свідоцтво | Evidence ID |
|---|---|---|
| `RMProcessNonStallIntrInLocklessIsr` двічі в `.rodata` | rizin `izz~nonstall` | `ev_73b123ff8190530cfb4cf9a3d832c8da9aa3268cbca46524bf2ac3106b87d5fa`, підтвердження `ev_017b94bbd6916afc51c2f4eca085e4de0317c7b705ae37df8d1a5bde341d0d7c` |
| `kchannelBindToRunlist_IMPL`, `runlist`, `RMDebugOverridePerRunlistChannelRam`, `deviceCtrlCmdFifoStart/StopRunlist_IMPL` у `.rodata`; BTF-рядки `hwRunlistId`, `runlistId`, `pRunlistPRIBaseRegister` | rizin `izz~runlist`, `izz~channel` | `ev_a1d57f103095667146a5f6812b5022766cc7c457cd669cd43d866a7df805bf33`, `ev_b5545ae0ecf22b594c27dbeab6552723831f5181203db44f5978759811766245` |
| `SUBDEV_EVENT_SET_NOTIFICATION`, `REGISTER_VIRTUAL_EVENT_BUFFER`, `CTRL_EVENT_BUFFER_UPDATE_GET`, `ALLOC_EVENT`, `SEND_EVENT` у `.rodata` | rizin `izz~event` | `ev_55c2ab2c01871defbd3d17f670cb8dfaea95e31dd265cb15663db24dfe6c4b16`, `ev_d36768e4a4a98a27a6638ca60434638b077530d663132287c17e60148b418280`, `ev_8cd0cb7618e77bb4918fbd05bf54100b3890133f996c4ef00adf794456177a05` |
| Символи event/notify у таблиці символів: `nv_get_event`, `nv_post_event`, `nv_gpu_bind_event`, `nv_gpu_unbind_event`, `nvswitch_lib_notify_client_events`, `nv_uvm_event_interrupt`, `rm_notify_gpu_addition/removal` | rizin `is~event`, `is~notify` | `ev_41ba59bdb7d209ea361591e08fb50023938299f69ad0348f0d83e2530f3a1d86`, `ev_175d63f7068176551e673e62d7f93cbc0b8dcee871d8ec1bdff69ade089e026e` |
| Символи channel-allocation/interfacing: `nvUvmInterfaceChannelAllocate`, `rm_gpu_ops_channel_allocate`, `nvUvmInterfacePagingChannelAllocate` тощо | rizin `is~channel` | `ev_d34f8c8a0c53fc42be81922b67a1b8fe875b59cbd219959cbe9c084e4b922af5` |
| Конфігураційний key coverage знайдено в REA/Rizin: `search.str.max_region_size` | rizin `el~str` | `ev_953e8782c8a5c905d559a6c1edfa2eee28ee15bb986a4fdbf4fd09c23b8b032e` |

Це **string/symbol inventory**, не доведений виклик, не формат структури, не
runtime-шлях і не mapping апаратних регістрів.

## Другий прохід — notification/GPFIFO та BOOT0-константа

| Факт | Свідоцтво | Evidence ID |
|---|---|---|
| `CTRL_GPFIFO_SCHEDULE`, `CTRL_GPFIFO_GET_WORK_SUBMIT_TOKEN`, `CTRL_GPFIFO_SET_WORK_SUBMIT_TOKEN_NOTIF_INDEX` присутні в `.rodata` | rizin `izz~GPFIFO` | `ev_b3a61f9e016151ce215097d356f42cd93c3456636762a256eb393e85dd20df31` |
| `REGISTER_VIRTUAL_EVENT_BUFFER` і `CTRL_EVENT_BUFFER_UPDATE_GET` підтверджені окремим запитом | rizin `izz~EVENT_BUFFER` | `ev_d29360c7c00aa0da5291a932c654cc4084837bcc49ef299ebda8db88a29279c3` |
| `SUBDEV_EVENT_SET_NOTIFICATION` підтверджено окремим запитом | rizin `izz~NOTIFICATION`, `izz~SUBDEV_EVENT` | `ev_a710cc1866b89152ef4526581fdf8e96b61fcab9059c8c4b624cbb04f70d34e6`, `ev_93542e594688be0dd79cbfc9224b6535aa20f53f2566d1a64a3d6df7d56b13c5` |
| `SEMAPHORE_SCHEDULE_CALLBACK`, `TIMED_SEMAPHORE_RELEASE` у `.rodata` | rizin `izz~SEMAPHORE` | `ev_24a1c411f1a0e7dece9389cba86f217639cf34753a71c46ccbf1ee54fdbd9fe8` |
| Сирий little-endian шаблон `a1 00 70 13` (для `0x137000A1`) у rizin-пошуку знайдено не було | rizin `/x a1007013` | `ev_4c777480992b351c7facad7fa59484f2a4d950ef052a0d1abadb9718d46f6be0` |
| Рядок `boot0` у піднятому рядковому інвентарі не знайдено | rizin `izz~boot0` | `ev_057f5e5208e8fcccd75b2873380c42e40d51726a90051b182753642692b67d32` |

Це **statically proven наявність control-імен**, зокрема явна назва Commander для
встановлення notifier-індексу для work-submit token. **interpretation**: пропрієтарний
RM має статичний механізм призначення notifier-індексу для GPFIFO submit. Це не
доводить, що він використовується для нашого каналу, на GP107 або в поточному boot.

## Межі й поточний статус питань

- `NONSTALL_EVENT_SUBSCRIPTION_OBSERVED` — **`UNPROVEN`**. Статично доведено
  лише наявність RM-імені `RMProcessNonStallIntrInLocklessIsr` і низки
  event/notification control-імен, включаючи
  `CTRL_GPFIFO_SET_WORK_SUBMIT_TOKEN_NOTIF_INDEX`. Прямого рядка `subscribe`
  не знайдено (`ev_7f339b53724a370bbb902cd48c227fff22c5661a4e8810f4b661338324d22564`,
  порожній інвентар), а headless log witness не містив `event`/`ntfy`. Порожні
  результати не підвищують статус.
- `CHANNEL_RUNLIST_CORRELATED` — **`UNPROVEN` / `PARTIAL`**. Статично доведено
  наявність `kchannelBindToRunlist_IMPL` та полів `runlistId`/`hwRunlistId`, але
  немає зв’язку конкретного нового каналу з конкретним видимим runlist у
  поточному runtime.
- `BOOT0` — **`UNPROVEN`**, без змін. Пошук `BOOT0`, `137000`, `137000a1`,
  `NON_STALL` у піднятому рядковому інвентарі порожній:
  `ev_7d36c354d45c8f789b7d2161cc18aa5eaa84cd144803b1a707fde0b6d4cdb772`,
  `ev_20be8bc2a3ada7b5cc79934444ef4467214e44aca77611f88348d5e3851f8bae`,
  `ev_fcc6be44137c044eb10ab99915fe247dad232de1b02787101ff7681dc46337db`,
  `ev_0d2a1438bb23d2befa7cf0c1dc429bde0da8edf9f0726f87bf3567ed9ea3c06f`.
  Додатково не знайдено сирий little-endian шаблон `a1 00 70 13`
  (`ev_4c777480992b351c7facad7fa59484f2a4d950ef052a0d1abadb9718d46f6be0`)
  і рядок `boot0` (`ev_057f5e5208e8fcccd75b2873380c42e40d51726a90051b182753642692b67d32`);
  це coverage-обмежений результат, не absence-proof. `0x137000A1` лишається
  `string-only` з kernel-log рядка, не BOOT0-вичиткою.

## Що не зроблено

- Не змінено `wsm-os-lisp/target-abi-pin.lisp`, CML, SENS, ADR чи target contract.
- Не запущено PR #21 executable; `PHYSICAL_GPU_TEST` для нього лишається `NOT_RUN`.
- Не робилось MMIO read/write, `nva`, custom reset, `Tested-by`, push/PR/tag/release.
- Не використано Ghidra-псевдокод і не скопійовано vendor source чи NVIDIA-код.

## Коротко українською

REA підняв coverage і дав статичні назви non-stall, channel→runlist та
event/notification у пропрієтарному модулі, але не перетворив їх на runtime-факти:
усі три відкриті питання лишаються відкритими.
