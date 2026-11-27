unit nv_rm;

{
  nv_rm.pas -- clean-room RM ioctl ABI for the arch-info research probe.

  AUTHORITY (deliberately not blurred):
    SENS owns language semantics; CML owns parsing/admission/IR.
    wsm-os-lisp owns the target ABI, boot runtime and platform policy.
    This unit is a NON-AUTHORITATIVE protocol note for GP107 research only:
    published command ids and public C layouts. It is not a driver and not
    a target-contract amendment.

  Public ABI evidence:
    NV2080_CTRL_CMD_MC_GET_ARCH_INFO = 0x20801701 and its params layout come
    from NVIDIA/open-gpu-kernel-modules ctrl2080/ctrl2080mc.h; the 0x0000
    command ids and layouts come from ctrl0000/ctrl0000gpu.h. NVOS54/64/00
    layouts come from the public Linux ioctl ABI. No vendor source is copied.

  Understanding questions for this fragment:
    1) Why is GPU_ATTACH_IDS needed before NV01_DEVICE_0 is allocated?
    2) Why must an opened /dev/nvidia0 fd stay open during the RM sequence?
    3) What breaks if NVOS64.params_size is hand-typed instead of SizeOf()?
    4) Why does arch=0x130/impl=0x7 still not prove the BOOT0 register?
}

{$mode objfpc}{$H+}{$codepage utf8}
{$PACKRECORDS C}

interface

uses
  nv_abi;

const
  NV_ESC_RM_FREE    = 41;   { NV_IOCTL_BASE + 0x29 }
  NV_ESC_RM_CONTROL = 42;   { NV_IOCTL_BASE + 0x2a }
  NV_ESC_RM_ALLOC   = 43;   { NV_IOCTL_BASE + 0x2b }

  NV01_ROOT_CLIENT  = LongWord($00000041);
  NV01_DEVICE_0     = LongWord($00000080);
  NV20_SUBDEVICE_0  = LongWord($00002080);

  NV0000_CTRL_CMD_GPU_GET_ID_INFO_V2 = LongWord($00000205);
  NV0000_CTRL_CMD_GPU_GET_PROBED_IDS = LongWord($00000214);
  NV0000_CTRL_CMD_GPU_ATTACH_IDS     = LongWord($00000215);
  NV2080_CTRL_CMD_MC_GET_ARCH_INFO   = LongWord($20801701);

  NV_MAX_PROBED_GPUS = 32;  { 0x180 / (3 * 4) observed in cuInit trace }

type
  Tnvos00 = record
    h_root:   LongWord;
    h_parent: LongWord;
    h_old:    LongWord;
    status:   LongWord;
  end;

  Tnvos54 = record
    h_client:    LongWord;
    h_object:    LongWord;
    cmd:         LongWord;
    flags:       LongWord;
    params_ptr:  QWord;
    params_size: LongWord;
    status:      LongWord;
  end;

  Tnvos64 = record
    h_root:           LongWord;
    h_parent:         LongWord;
    h_new:            LongWord;
    h_class:          LongWord;
    alloc_parms_ptr:  QWord;
    rights_ptr:       QWord;
    params_size:      LongWord;
    flags:            LongWord;
    status:           LongWord;
    pad:              LongWord;
  end;

  Tnv0080_alloc_params = record
    device_id:        LongWord;
    h_client_share:   LongWord;
    h_target_client:  LongWord;
    h_target_device:  LongWord;
    flags:            LongWord;
    pad0:             LongWord;
    va_space_size:    QWord;
    va_start_internal: QWord;
    va_limit_internal: QWord;
    va_mode:          LongWord;
    pad1:             LongWord;
  end;

  Tnv2080_alloc_params = record
    sub_device_id: LongWord;
  end;

  Tgpu_probed_params = record
    gpu_ids:       array[0..NV_MAX_PROBED_GPUS - 1] of LongWord;
    excluded_ids:  array[0..NV_MAX_PROBED_GPUS - 1] of LongWord;
    gpu_flags:     array[0..NV_MAX_PROBED_GPUS - 1] of LongWord;
  end;

  Tgpu_attach_params = record
    gpu_ids:  array[0..NV_MAX_PROBED_GPUS - 1] of LongWord;
    failed_id: LongWord;
  end;

  Tgpu_id_info_v2_params = array[0..7] of LongWord;

  Tarch_info_params = record
    architecture:   LongWord;
    impl:           LongWord;
    revision:       LongWord;
    sub_revision:   Byte;
    pad:            array[0..2] of Byte;
  end;

{ Compile-time ABI proof: a wrong layout makes SizeOf() differ and the
  array bound array[0..-1] fails the build BEFORE any ioctl is attempted. }
type
  TAssertNvos00    = array[0..Ord(SizeOf(Tnvos00)             = 16) - 1] of Byte;
  TAssertNvos54    = array[0..Ord(SizeOf(Tnvos54)             = 32) - 1] of Byte;
  TAssertNvos64    = array[0..Ord(SizeOf(Tnvos64)             = 48) - 1] of Byte;
  TAssertDevParams = array[0..Ord(SizeOf(Tnv0080_alloc_params) = 56) - 1] of Byte;
  TAssertSubParams = array[0..Ord(SizeOf(Tnv2080_alloc_params) = 4) - 1] of Byte;
  TAssertProbed    = array[0..Ord(SizeOf(Tgpu_probed_params)   = 384) - 1] of Byte;
  TAssertAttach    = array[0..Ord(SizeOf(Tgpu_attach_params)   = 132) - 1] of Byte;
  TAssertIdInfoV2  = array[0..Ord(SizeOf(Tgpu_id_info_v2_params) = 32) - 1] of Byte;
  TAssertArchInfo  = array[0..Ord(SizeOf(Tarch_info_params)    = 16) - 1] of Byte;

const
  AbiRmProven = SizeOf(TAssertNvos00) * SizeOf(TAssertNvos54) *
                SizeOf(TAssertNvos64) * SizeOf(TAssertDevParams) *
                SizeOf(TAssertSubParams) * SizeOf(TAssertProbed) *
                SizeOf(TAssertAttach) * SizeOf(TAssertIdInfoV2) *
                SizeOf(TAssertArchInfo);  { must be 1 }

function RmIOC(nr, size: LongWord): LongWord; inline;

implementation

function RmIOC(nr, size: LongWord): LongWord; inline;
begin
  Result := NvIOC_RDWR(NV_IOCTL_MAGIC, nr, size);
end;

end.
