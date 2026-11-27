# NVIDIA Linux ioctl reference (observed on R580 / GP107)

Consolidated lookup table. Decode any request with:

```bash
python3 scripts/decode_ioctl.py 0xc90046c8
```

A request encodes as `_IOC(dir, type, nr, size)`:

```text
dir  = (req >> 30) & 3       0=none, 1=write, 2=read, 3=read/write
size = (req >> 16) & 0x1fff
type = (req >>  8) & 0xff    NVIDIA control magic = 'F' = 0x46; UVM = 0x00
nr   =  req        & 0xff
```

## RM escape ioctls (type `0x46`)

### Public range (`nv-ioctl-numbers.h`, `NV_IOCTL_BASE = 200`)

| nr | Name | Typical request | Notes |
|---:|---|---|---|
| 200 | `NV_ESC_CARD_INFO` | `0xc90046c8` | 32 x 72-byte entries |
| 201 | `NV_ESC_REGISTER_FD` | `0xc00446c9` | Register GPU fd with ctl fd |
| 206 | `NV_ESC_ALLOC_OS_EVENT` | — | OS event |
| 207 | `NV_ESC_FREE_OS_EVENT` | — | OS event |
| 209 | `NV_ESC_STATUS_CODE` | `0xc00c46d1` | Error path |
| 210 | `NV_ESC_CHECK_VERSION_STR` | — | RM API version check |
| 211 | `NV_ESC_IOCTL_XFER_CMD` | — | Large-parameter transfer |
| 212 | `NV_ESC_ATTACH_GPUS_TO_FD` | — | Multi-GPU attach |
| 213 | `NV_ESC_QUERY_DEVICE_INTR` | `0xc00846d5` | Interrupt status |
| 214 | `NV_ESC_SYS_PARAMS` | `0xc00846d6` | `uint64_t memblock_size` |
| 217 | `NV_ESC_EXPORT_TO_DMABUF_FD` | `0xca3046d9` | DMABUF export |
| 218 | `NV_ESC_WAIT_OPEN_COMPLETE` | `0xc00846da` | Open completion |

### RM escape range (`nv_escape.h`)

| nr | Name | Parameter struct |
|---:|---|---|
| `0x27` | `NV_ESC_RM_ALLOC_MEMORY` | `NVOS02_PARAMETERS` |
| `0x28` | `NV_ESC_RM_ALLOC_OBJECT` | `NVOS05_PARAMETERS` |
| `0x29` | `NV_ESC_RM_FREE` | `NVOS00_PARAMETERS` |
| `0x2a` | `NV_ESC_RM_CONTROL` | `NVOS54_PARAMETERS` (32 bytes) |
| `0x2b` | `NV_ESC_RM_ALLOC` | `NVOS64_PARAMETERS` (48 bytes) |
| `0x32` | `NV_ESC_RM_CONFIG_GET` | internal |
| `0x33` | `NV_ESC_RM_CONFIG_SET` | internal |
| `0x34` | `NV_ESC_RM_DUP_OBJECT` | internal |
| `0x35` | `NV_ESC_RM_SHARE` | internal |
| `0x4a` | `NV_ESC_RM_VID_HEAP_CONTROL` | `NVOS32_PARAMETERS` |
| `0x4d` | `NV_ESC_RM_ACCESS_REGISTRY` | internal |
| `0x4e` | `NV_ESC_RM_MAP_MEMORY` | internal |
| `0x4f` | `NV_ESC_RM_UNMAP_MEMORY` | internal |
| `0x5c` | `NV_ESC_RM_EXPORT_OBJECT_TO_FD` | internal |
| `0x5d` | `NV_ESC_RM_IMPORT_OBJECT_FROM_FD` | internal |

The public `nv-ioctl-numbers.h` shipped with the driver does **not** define the `0x27`–`0x5d` range; use `src/nvidia/arch/nvalloc/unix/include/nv_escape.h` from `NVIDIA/open-gpu-kernel-modules` at the matching tag.

## UVM ioctls (type `0x00`)

| nr | Name | Request encoding |
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

## RM command ids (`NVOS54_PARAMETERS.cmd`)

| `cmd` | Symbol | Header |
|---|---|---|
| `0x20803801` | `NV2080_CTRL_CMD_GRMGR_GET_GR_FS_INFO` | `ctrl2080grmgr.h` |
| `0x20801346` | `NV2080_CTRL_CMD_FB_GET_FS_INFO` | `ctrl2080fb.h` |
| `0x00000101` | `NV0000_CTRL_CMD_CLIENT_GET_CAPABILITIES` | `ctrl0000client.h` |

The high 16 bits identify the RM class (`0x2080` = `NV20_SUBDEVICE_0`); the low byte is the per-interface command id.

## ABI layouts used in the clean-room probe

`nv_pci_info_t` (12 bytes):

| Offset | Type | Field |
|---:|---|---|
| 0 | u32 | `domain` |
| 4 | u8 | `bus` |
| 5 | u8 | `slot` |
| 6 | u8 | `function` |
| 8 | u16 | `vendor_id` |
| 10 | u16 | `device_id` |

`nv_ioctl_card_info_t` (72 bytes):

| Offset | Type | Field |
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
| 60 | u8[10] | `dev_name` (padded to 72) |

`NV_ESC_CARD_INFO` uses 32 entries = 2304 bytes, matching the observed request size `0x900`.

## Provenance

- `/usr/src/nvidia-580.196.11/common/inc/nv-ioctl-numbers.h`
- `/usr/src/nvidia-580.196.11/common/inc/nv-ioctl.h`
- `NVIDIA/open-gpu-kernel-modules` tag `580.196.11`: `nv_escape.h`, `uvm_ioctl.h`, `uvm_linux_ioctl.h`, `ctrl2080*.h`, `cl0040.h`
- Runtime `strace` of `cuInit`, `cuMemAlloc_v2`, `cuLaunchKernel`, `cuMemFree_v2`
