program min_cuinit;

{
  No-libcuda cuInit-like probe, Pascal edition.

  Direct BaseUnix syscalls: FpOpen / FpIOCtl / FpRead / FpClose.
  FpMMap is reserved for the next (BAR mapping) step and is not needed here.
  Record sizes are proved at compile time in nv_abi.pas; a layout drift
  fails the build rather than issuing a malformed ioctl at runtime.

  Understanding questions for this fragment:
    1) Why is the sysfs value parsed as hexadecimal, not decimal?
    2) Why must NV_ESC_SYS_PARAMS receive the exact memblock_size?
    3) On which fd is NV_ESC_REGISTER_FD issued, and what is its argument?
    4) Which evidence here is runtime-proven and which is only static?
    5) Why does this prove nothing about a bare-metal GPU driver?
}

{$mode objfpc}{$H+}

uses
  SysUtils, BaseUnix, Unix, Linux, nv_abi;

const
  BLOCK_SIZE_PATH = '/sys/devices/system/memory/block_size_bytes';

var
  ctl_fd:   cint;
  gpu_fd:   cint;
  uvm_fd:   cint;
  arg_fd:   cint;
  memblock: QWord;
  cards:    array[0..NV_MAX_CARDS - 1] of Tnv_card_info;
  path:     string;
  i:        Integer;
  found:    Integer;

function ReadMemBlockSize(out value: QWord): Boolean;
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

procedure Fail(const what: string);
begin
  WriteLn(StdErr, what, ': errno=', fpgeterrno);
end;

begin
  { Sanity-check the hand-written request encoding against the macro. }
  if (NvIOC_RDWR(NV_IOCTL_MAGIC, NV_ESC_CARD_INFO, 2304) <> NV_IOC_CARD_INFO) or
     (NvIOC_RDWR(NV_IOCTL_MAGIC, NV_ESC_SYS_PARAMS, 8) <> NV_IOC_SYS_PARAMS) or
     (NvIOC_RDWR(NV_IOCTL_MAGIC, NV_ESC_REGISTER_FD, 4) <> NV_IOC_REGISTER_FD) then
  begin
    WriteLn(StdErr, 'ABI mismatch: ioctl request encoding');
    Halt(2);
  end;

  ctl_fd := FpOpen('/dev/nvidiactl', O_RDWR or O_CLOEXEC, 0);
  if ctl_fd < 0 then
  begin
    Fail('open(/dev/nvidiactl)');
    Halt(1);
  end;

  if not ReadMemBlockSize(memblock) then
  begin
    Fail('read(' + BLOCK_SIZE_PATH + ')');
    Halt(1);
  end;
  WriteLn('sysfs block_size_bytes : 0x', IntToHex(memblock, 8));

  { NV_ESC_SYS_PARAMS is set-once: pass exactly what cuInit passes. }
  if FpIOCtl(ctl_fd, NV_IOC_SYS_PARAMS, @memblock) < 0 then
  begin
    Fail('ioctl(NV_ESC_SYS_PARAMS)');
    Halt(1);
  end;
  WriteLn('NV_ESC_SYS_PARAMS  : memblock_size = ', memblock, ' bytes');

  FillChar(cards, SizeOf(cards), 0);
  if FpIOCtl(ctl_fd, NV_IOC_CARD_INFO, @cards[0]) < 0 then
  begin
    Fail('ioctl(NV_ESC_CARD_INFO)');
    Halt(1);
  end;

  found := 0;
  for i := 0 to NV_MAX_CARDS - 1 do
  begin
    if cards[i].valid = 0 then
      Continue;
    Inc(found);
    WriteLn('NV_ESC_CARD_INFO   : GPU ', i,
            ': ', IntToHex(cards[i].pci.vendor_id, 4), ':',
            IntToHex(cards[i].pci.device_id, 4),
            ' @ ', IntToHex(cards[i].pci.domain, 4), ':',
            IntToHex(cards[i].pci.bus, 2), ':',
            IntToHex(cards[i].pci.slot, 2), '.',
            cards[i].pci.function_,
            ', gpu_id=0x', IntToHex(cards[i].gpu_id, 1),
            ', minor=', cards[i].minor_number,
            ', BAR0=0x', IntToHex(cards[i].reg_address, 8),
            '+0x', IntToHex(cards[i].reg_size, 8),
            ', FB=0x', IntToHex(cards[i].fb_address, 8),
            '+0x', IntToHex(cards[i].fb_size, 8));

    path := '/dev/nvidia' + IntToStr(cards[i].minor_number);
    gpu_fd := FpOpen(PChar(path), O_RDWR or O_CLOEXEC, 0);
    if gpu_fd < 0 then
    begin
      Fail(path);
      Continue;
    end;
    WriteLn('open(', path, ')     : fd=', gpu_fd);

    { cuInit issues this on the GPU fd, with the control fd as 4-byte arg. }
    arg_fd := ctl_fd;
    if FpIOCtl(gpu_fd, NV_IOC_REGISTER_FD, @arg_fd) < 0 then
      Fail('ioctl(NV_ESC_REGISTER_FD)');

    FpClose(gpu_fd);
  end;

  uvm_fd := FpOpen('/dev/nvidia-uvm', O_RDWR or O_CLOEXEC, 0);
  if uvm_fd < 0 then
    Fail('open(/dev/nvidia-uvm)')
  else
  begin
    WriteLn('open(/dev/nvidia-uvm) : fd=', uvm_fd);
    FpClose(uvm_fd);
  end;

  FpClose(ctl_fd);

  if found = 0 then
  begin
    WriteLn(StdErr, 'no valid GPU entries returned');
    Halt(2);
  end;
end.
