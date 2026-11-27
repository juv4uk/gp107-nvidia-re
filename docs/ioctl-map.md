# Довідник NVIDIA Linux ioctl (спостережено на R580 / GP107)

Зведена таблиця для пошуку. Декодувати будь-який запит можна так:

```bash
python3 scripts/decode_ioctl.py 0xc90046c8
```

Запит кодується як `_IOC(dir, type, nr, size)`:

```text
dir  = (req >> 30) & 3       0=none, 1=write, 2=read, 3=read/write
size = (req >> 16) & 0x1fff
type = (req >>  8) & 0xff    NVIDIA control magic = 'F' = 0x46; UVM = 0x00
nr   =  req        & 0xff
```

## Escape-ioctl Resource Manager (тип `0x46`)

### Публічний діапазон (`nv-ioctl-numbers.h`, `NV_IOCTL_BASE = 200`)

| nr | Назва | Типовий запит | Примітки |
|---:|---|---|---|
| 200 | `NV_ESC_CARD_INFO` | `0xc90046c8` | 32 записи по 72 байти |
| 201 | `NV_ESC_REGISTER_FD` | `0xc00446c9` | Реєстрація GPU fd через ctl fd |
| 206 | `NV_ESC_ALLOC_OS_EVENT` | — | Подія ОС |
| 207 | `NV_ESC_FREE_OS_EVENT` | — | Подія ОС |
| 209 | `NV_ESC_STATUS_CODE` | `0xc00c46d1` | Шлях обробки помилки |
| 210 | `NV_ESC_CHECK_VERSION_STR` | — | Перевірка версії API RM |
| 211 | `NV_ESC_IOCTL_XFER_CMD` | — | Передавання параметрів великого розміру |
| 212 | `NV_ESC_ATTACH_GPUS_TO_FD` | — | Під'єднання кількох GPU |
| 213 | `NV_ESC_QUERY_DEVICE_INTR` | `0xc00846d5` | Стан переривань |
| 214 | `NV_ESC_SYS_PARAMS` | `0xc00846d6` | `uint64_t memblock_size` |
| 217 | `NV_ESC_EXPORT_TO_DMABUF_FD` | `0xca3046d9` | Експорт DMABUF |
| 218 | `NV_ESC_WAIT_OPEN_COMPLETE` | `0xc00846da` | Очікування завершення відкриття |

### Діапазон escape-команд RM (`nv_escape.h`)

| nr | Назва | Структура параметрів |
|---:|---|---|
| `0x27` | `NV_ESC_RM_ALLOC_MEMORY` | `NVOS02_PARAMETERS` |
| `0x28` | `NV_ESC_RM_ALLOC_OBJECT` | `NVOS05_PARAMETERS` |
| `0x29` | `NV_ESC_RM_FREE` | `NVOS00_PARAMETERS` |
| `0x2a` | `NV_ESC_RM_CONTROL` | `NVOS54_PARAMETERS` (32 байти) |
| `0x2b` | `NV_ESC_RM_ALLOC` | `NVOS64_PARAMETERS` (48 байтів) |
| `0x32` | `NV_ESC_RM_CONFIG_GET` | внутрішня |
| `0x33` | `NV_ESC_RM_CONFIG_SET` | внутрішня |
| `0x34` | `NV_ESC_RM_DUP_OBJECT` | внутрішня |
| `0x35` | `NV_ESC_RM_SHARE` | внутрішня |
| `0x4a` | `NV_ESC_RM_VID_HEAP_CONTROL` | `NVOS32_PARAMETERS` |
| `0x4d` | `NV_ESC_RM_ACCESS_REGISTRY` | внутрішня |
| `0x4e` | `NV_ESC_RM_MAP_MEMORY` | внутрішня |
| `0x4f` | `NV_ESC_RM_UNMAP_MEMORY` | внутрішня |
| `0x5c` | `NV_ESC_RM_EXPORT_OBJECT_TO_FD` | внутрішня |
| `0x5d` | `NV_ESC_RM_IMPORT_OBJECT_FROM_FD` | внутрішня |

Публічний `nv-ioctl-numbers.h`, що постачається з драйвером, **не** визначає діапазон `0x27`–`0x5d`. Для нього слід використовувати `src/nvidia/arch/nvalloc/unix/include/nv_escape.h` із `NVIDIA/open-gpu-kernel-modules` відповідного тегу.

## ioctl UVM (тип `0x00`)

| nr | Назва | Кодування запиту |
|---:|---|---|
| 1 | `UVM_INITIALIZE` | `0x30000001` |
| 2 | `UVM_RELEASE_VA` | `0x2` |
| 3 | `UVM_REGION_COMMIT` | `0x3` |
| 17 | `UVM_EVENT_CTRL` | `0x11` |
| 23 | `UVM_CREATE_RANGE_GROUP` | `0x17` |
| 25 | `UVM_REGISTER_GPU_VASPACE` | `0x19` |
| 33 | `UVM_MAP_EXTERNAL_ALLOCATION` | `0x21` |
| 34 | `UVM_FREE` | `0x22` |
| 35 | `UVM_MEM_MAP` | `0x23` |
| 37 | `UVM_REGISTER_GPU` | `0x25` |
| 39 | `UVM_PAGEABLE_MEM_ACCESS` | `0x27` |
| 55 | `UVM_DISABLE_SYSTEM_WIDE_ATOMICS` | `0x37` |
| 73 | `UVM_CREATE_EXTERNAL_RANGE` | `0x49` |
| 75 | `UVM_MM_INITIALIZE` | `0x4b` |

## Ідентифікатори команд RM (`NVOS54_PARAMETERS.cmd`)

| `cmd` | Символ | Заголовок |
|---|---|---|
| `0x20803801` | `NV2080_CTRL_CMD_GRMGR_GET_GR_FS_INFO` | `ctrl2080grmgr.h` |
| `0x20801346` | `NV2080_CTRL_CMD_FB_GET_FS_INFO` | `ctrl2080fb.h` |
| `0x00000101` | `NV0000_CTRL_CMD_CLIENT_GET_CAPABILITIES` | `ctrl0000client.h` |

Старші 16 бітів визначають клас RM (`0x2080` = `NV20_SUBDEVICE_0`); молодший байт — ідентифікатор команди в межах відповідного інтерфейсу.

## Розкладки ABI, використані в clean-room пробнику

`nv_pci_info_t` (12 байтів):

| Зсув | Тип | Поле |
|---:|---|---|
| 0 | u32 | `domain` |
| 4 | u8 | `bus` |
| 5 | u8 | `slot` |
| 6 | u8 | `function` |
| 8 | u16 | `vendor_id` |
| 10 | u16 | `device_id` |

`nv_ioctl_card_info_t` (72 байти):

| Зсув | Тип | Поле |
|---:|---|---|
| 0 | u32 | `valid` |
| 4 | `nv_pci_info_t` | `pci_info` |
| 16 | u32 | `gpu_id` |
| 20 | u16 | `interrupt_line` |
| 24 | u64 | `reg_address` |
| 32 | u64 | `reg_size` |
| 40 | u64 | `fb_address` |
| 48 | u64 | `fb_size` |
| 56 | u32 | `minor_number` |
| 60 | u8[10] | `dev_name` (доповнюється до 72 байтів) |

`NV_ESC_CARD_INFO` використовує 32 записи, разом 2304 байти; це відповідає спостереженому розміру запиту `0x900`.

## Походження даних

- `/usr/src/nvidia-580.196.11/common/inc/nv-ioctl-numbers.h`
- `/usr/src/nvidia-580.196.11/common/inc/nv-ioctl.h`
- Тег `580.196.11` репозиторію `NVIDIA/open-gpu-kernel-modules`: `nv_escape.h`, `uvm_ioctl.h`, `uvm_linux_ioctl.h`, `ctrl2080*.h`, `cl0040.h`
- Runtime-трасування `strace` для `cuInit`, `cuMemAlloc_v2`, `cuLaunchKernel` та `cuMemFree_v2`
