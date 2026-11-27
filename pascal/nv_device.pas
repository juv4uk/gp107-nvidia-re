unit nv_device;

{
  nv_device.pas -- shared clean-room device discovery for Pascal probes.

  Authority: non-authoritative protocol notes only. SENS owns language
  semantics; wsm-os-lisp owns the target ABI and platform policy.

  Two independent identity sources are kept separate on purpose:
    * NV_ESC_CARD_INFO through /dev/nvidiactl (driver's own report);
    * PCI config space through sysfs (firmware/PCI view).
  Neither is promoted to a claim about bare-metal MMIO access.
}

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses
  SysUtils, BaseUnix, Unix, Linux, nv_abi;

const
  PCI_CONFIG_PATH_FMT   = '/sys/bus/pci/devices/%s/config';
  PCI_RESOURCE0_PATH_FMT = '/sys/bus/pci/devices/%s/resource0';
  GPU_DEVICE_PATH_FMT   = '/dev/nvidia%d';

  { Цільова ідентичність для цього репозиторія. Це PCI vendor/device,
    НЕ RM device_id в NV0080_ALLOC_PARAMETERS (там значення 0 лишається
    незмінним до окремого підтвердження його семантики). }
  PCI_VENDOR_NVIDIA     = Word($10de);
  PCI_DEVICE_GP107      = Word($1c82);
  GPU_MINOR_MAX         = 255;

type
  Tpci_identity = record
    vendor: Word;
    device: Word;
    bar0:   LongWord;         { memory BAR address, low flag bits masked }
  end;

function ReadMemBlockSize(out value: QWord): Boolean;
function ReadFirstCard(out card: Tnv_card_info): Boolean;
function SelectTargetCard(out card: Tnv_card_info;
                          out matches, valid_cards: Integer): Boolean;
function GpuDevicePath(const card: Tnv_card_info): string;
function DeviceBdf(const card: Tnv_card_info): string;
function DevicePath(const card: Tnv_card_info; const fmt: string): string;
function ReadPciConfig(const card: Tnv_card_info; out id: Tpci_identity): Boolean;

implementation

function ReadMemBlockSize(out value: QWord): Boolean;
const
  BLOCK_SIZE_PATH = '/sys/devices/system/memory/block_size_bytes';
var
  fd:   cint;
  n:    ssize_t;
  buf:  array[0..63] of Byte;
  text: string;
begin
  Result := False;
  value := 0;

  fd := FpOpen(BLOCK_SIZE_PATH, O_RDONLY or O_CLOEXEC, 0);
  if fd < 0 then
    Exit;

  FillChar(buf, SizeOf(buf), 0);
  n := FpRead(fd, buf, SizeOf(buf) - 1);
  FpClose(fd);
  if n <= 0 then
    Exit;

  SetLength(text, n);
  Move(buf[0], text[1], n);
  text := Trim(text);
  try
    value := StrToQWord('$' + text);
    Result := True;
  except
    on EConvertError do
      Result := False;
  end;
end;

function ReadFirstCard(out card: Tnv_card_info): Boolean;
var
  ctl_fd:   cint;
  memblock: QWord;
  cards:    array[0..NV_MAX_CARDS - 1] of Tnv_card_info;
  i:        Integer;
begin
  Result := False;
  FillChar(card, SizeOf(card), 0);

  ctl_fd := FpOpen('/dev/nvidiactl', O_RDWR or O_CLOEXEC, 0);
  if ctl_fd < 0 then
    Exit;

  if not ReadMemBlockSize(memblock) then
  begin
    FpClose(ctl_fd);
    Exit;
  end;

  { NV_ESC_SYS_PARAMS is set-once: pass exactly what cuInit passes. }
  if FpIOCtl(ctl_fd, NV_IOC_SYS_PARAMS, @memblock) < 0 then
  begin
    FpClose(ctl_fd);
    Exit;
  end;

  FillChar(cards, SizeOf(cards), 0);
  if FpIOCtl(ctl_fd, NV_IOC_CARD_INFO, @cards[0]) < 0 then
  begin
    FpClose(ctl_fd);
    Exit;
  end;

  for i := 0 to NV_MAX_CARDS - 1 do
  begin
    if cards[i].valid = 0 then
      Continue;
    card := cards[i];
    Result := True;
    Break;
  end;

  FpClose(ctl_fd);
end;

function SelectTargetCard(out card: Tnv_card_info;
                          out matches, valid_cards: Integer): Boolean;
var
  ctl_fd:   cint;
  memblock: QWord;
  cards:    array[0..NV_MAX_CARDS - 1] of Tnv_card_info;
  i:        Integer;
begin
  Result := False;
  FillChar(card, SizeOf(card), 0);
  matches := 0;
  valid_cards := 0;

  ctl_fd := FpOpen('/dev/nvidiactl', O_RDWR or O_CLOEXEC, 0);
  if ctl_fd < 0 then
    Exit;

  if not ReadMemBlockSize(memblock) then
  begin
    FpClose(ctl_fd);
    Exit;
  end;

  { NV_ESC_SYS_PARAMS is set-once: pass exactly what cuInit passes. }
  if FpIOCtl(ctl_fd, NV_IOC_SYS_PARAMS, @memblock) < 0 then
  begin
    FpClose(ctl_fd);
    Exit;
  end;

  FillChar(cards, SizeOf(cards), 0);
  if FpIOCtl(ctl_fd, NV_IOC_CARD_INFO, @cards[0]) < 0 then
  begin
    FpClose(ctl_fd);
    Exit;
  end;

  for i := 0 to NV_MAX_CARDS - 1 do
  begin
    if cards[i].valid = 0 then
      Continue;
    Inc(valid_cards);
    if (cards[i].pci.vendor_id = PCI_VENDOR_NVIDIA) and
       (cards[i].pci.device_id = PCI_DEVICE_GP107) then
    begin
      Inc(matches);
      if matches = 1 then
        card := cards[i];
    end;
  end;

  FpClose(ctl_fd);
  { Ambiguity is never resolved silently: caller must reject matches <> 1. }
  Result := matches = 1;
end;

function GpuDevicePath(const card: Tnv_card_info): string;
begin
  Result := '';
  if card.minor_number > GPU_MINOR_MAX then
    Exit;
  Result := Format(GPU_DEVICE_PATH_FMT, [card.minor_number]);
end;

function DeviceBdf(const card: Tnv_card_info): string;
begin
  Result := LowerCase(IntToHex(card.pci.domain, 4)) + ':' +
            LowerCase(IntToHex(card.pci.bus, 2)) + ':' +
            LowerCase(IntToHex(card.pci.slot, 2)) + '.' +
            IntToStr(card.pci.function_);
end;

function DevicePath(const card: Tnv_card_info; const fmt: string): string;
begin
  Result := Format(fmt, [DeviceBdf(card)]);
end;

function ReadPciConfig(const card: Tnv_card_info; out id: Tpci_identity): Boolean;
var
  fd:   cint;
  n:    ssize_t;
  buf:  array[0..63] of Byte;
begin
  Result := False;
  FillChar(id, SizeOf(id), 0);

  fd := FpOpen(PChar(DevicePath(card, PCI_CONFIG_PATH_FMT)),
               O_RDONLY or O_CLOEXEC, 0);
  if fd < 0 then
    Exit;

  FillChar(buf, SizeOf(buf), 0);
  n := FpPRead(fd, buf[0], SizeOf(buf), 0);
  FpClose(fd);
  if n < $14 then
    Exit;

  { PCI config header is little-endian, independent of NVIDIA ioctl ABI. }
  id.vendor := Word(buf[$00]) or (Word(buf[$01]) shl 8);
  id.device := Word(buf[$02]) or (Word(buf[$03]) shl 8);
  id.bar0   := (LongWord(buf[$10]) or (LongWord(buf[$11]) shl 8) or
                (LongWord(buf[$12]) shl 16) or (LongWord(buf[$13]) shl 24))
                and LongWord($fffffff0);
  Result := (id.vendor <> 0) and (id.bar0 <> 0);
end;

end.
