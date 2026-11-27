unit nv_abi;

{
  nv_abi.pas -- clean-room NVIDIA Linux ioctl ABI for Pascal probes.

  AUTHORITY (deliberately not blurred):
    SENS owns language semantics; CML owns parsing/admission/IR.
    wsm-os-lisp owns the target ABI, boot runtime and platform policy.
    This unit is a NON-AUTHORITATIVE protocol note for GP107 research:
    published/observed numbers and layouts only. It is not a driver and
    not a target-contract amendment.

  No vendor headers, no libc, no decompiled code. Verified against driver
  580.196.11, kernel 7.2.15+kali-amd64, GP107 (10de:1c82).

  Understanding questions for this fragment:
    1) Why must Tnv_card_info be 72 bytes rather than 64?
    2) What breaks if the ioctl request number is hand-typed incorrectly?
    3) Which of these constants are R580-specific and which are shared?
    4) Why does the PACKRECORDS C directive matter beyond field order?
    5) Why is this unit not allowed to define a WSM target ABI?
}

{$mode objfpc}{$H+}{$codepage utf8}
{$PACKRECORDS C}

interface

const
  NV_IOCTL_MAGIC  = $46;              // 'F' from nv-ioctl-numbers.h
  NV_ESC_CARD_INFO   = 200;           // NV_IOCTL_BASE + 0
  NV_ESC_REGISTER_FD = 201;           // NV_IOCTL_BASE + 1
  NV_ESC_SYS_PARAMS  = 214;           // NV_IOCTL_BASE + 14
  NV_MAX_CARDS       = 32;            // 2304 / 72

  { _IOC(dir, type, nr, size) -- dir=3 is READ|WRITE }
  NV_IOC_SYS_PARAMS  = $c00846d6;     // _IOWR('F', 214, 8)
  NV_IOC_CARD_INFO   = $c90046c8;     // _IOWR('F', 200, 2304)
  NV_IOC_REGISTER_FD = $c00446c9;     // _IOWR('F', 201, 4)

type
  Tnv_pci_info = record
    domain:    LongWord;              // NvU32
    bus:       Byte;                  // NvU8
    slot:      Byte;                  // NvU8
    function_: Byte;                  // NvU8
    vendor_id: Word;                  // NvU16
    device_id: Word;                  // NvU16
  end;

  Tnv_card_info = record
    valid:          LongWord;         // NvBool
    pci:            Tnv_pci_info;
    gpu_id:         LongWord;         // NvU32
    interrupt_line: Word;             // NvU16
    reg_address:    QWord;            // NvU64, aligned 8 by C ABI
    reg_size:       QWord;
    fb_address:     QWord;
    fb_size:        QWord;
    minor_number:   LongWord;
    dev_name:       array[0..9] of Byte;
  end;

{ Compile-time ABI proof, borrowed from wsm-lazarus's mechanical gates.
  FPC 3.2.2 folds SizeOf() into a constant: a wrong layout produces
  array[0..-1] and the build fails BEFORE any ioctl is attempted. }
type
  TAssertPciInfo12  = array[0..Ord(SizeOf(Tnv_pci_info)  = 12) - 1] of Byte;
  TAssertCardInfo72 = array[0..Ord(SizeOf(Tnv_card_info) = 72) - 1] of Byte;

const
  AbiPciProven  = SizeOf(TAssertPciInfo12);   // must be 1
  AbiCardProven = SizeOf(TAssertCardInfo72);  // must be 1

function NvIOC(dir_bits: LongWord; ioctl_type: LongWord; nr: LongWord;
               size: LongWord): LongWord; inline;
function NvIOC_RDWR(ioctl_type: LongWord; nr: LongWord;
                    size: LongWord): LongWord; inline;

implementation

function NvIOC(dir_bits: LongWord; ioctl_type: LongWord; nr: LongWord;
               size: LongWord): LongWord; inline;
begin
  Result := (dir_bits shl 30) or (size shl 16) or (ioctl_type shl 8) or nr;
end;

function NvIOC_RDWR(ioctl_type: LongWord; nr: LongWord;
                    size: LongWord): LongWord; inline;
begin
  Result := NvIOC(3, ioctl_type, nr, size);
end;

end.
