unit gp107_mmio;

{
  Clean-room Free Pascal read-only aperture seam for GP107.

  This unit is the Pascal counterpart of lib/gp107_mmio.c. The public
  operation re-scans sysfs identity, then enforces opt-in, driver binding,
  BAR0 space/size and offset gates before mapping. The inline assembler
  primitive is owned by this project and performs exactly one 32-bit load
  with a following load fence; it contains no register constants, no writes,
  no vendor sequence and no boot assumption.

  Hardware MMIO is NOT_RUN. This unit does not grant a right to touch a
  register; it only mirrors the C reference behaviour on a mapped read-only
  window that has passed all fail-closed gates.
}

{$mode objfpc}{$H+}{$asmmode intel}{$codepage utf8}

interface

uses
  SysUtils, gp107_identity;

function Load32Asm(addr: Pointer): LongWord; assembler;
function RequireOptin(allow: LongInt; out err: string): LongInt;
function CheckDriver(const inv: Tgp107Inventory; out err: string): LongInt;
function Read32(const sysfsRoot, expectBdf: string; allow: LongInt;
                offset: LongWord; out value: LongWord;
                out err: string): LongInt;

implementation

uses
  BaseUnix, Unix, Linux;

function COpenAt(dirfd: cint; pathname: PChar; flags: cint;
                 mode: TMode): cint; cdecl; external 'c' name 'openat';

function HexNoPad(v: QWord): string;
begin
  Result := LowerCase(IntToHex(v, 1));
end;

function DriverName(const name: array of Char): string;
var
  i: Integer;
begin
  Result := '';
  for i := Low(name) to High(name) do
  begin
    if name[i] = #0 then
      Break;
    Result := Result + name[i];
  end;
end;

function Load32Asm(addr: Pointer): LongWord; assembler;
asm
  mov eax,[rdi]
  lfence
end;

function RequireOptin(allow: LongInt; out err: string): LongInt;
begin
  err := '';
  if allow = 0 then
  begin
    err := 'MMIO-FAIL step=opt-in-required code=' + IntToStr(STATUS_OPTIN);
    Exit(STATUS_OPTIN);
  end;
  Result := STATUS_OK;
end;

function CheckDriver(const inv: Tgp107Inventory; out err: string): LongInt;
begin
  err := '';
  if inv.driver.bound <> 0 then
  begin
    err := 'MMIO-FAIL step=driver-bound code=' +
           IntToStr(STATUS_DRIVER_BOUND) + ' driver=' +
           DriverName(inv.driver.name);
    Exit(STATUS_DRIVER_BOUND);
  end;
  Result := STATUS_OK;
end;

function MapRead32(deviceFd: cint; const inv: Tgp107Inventory;
                   expectedSize: LongWord; offset: LongWord;
                   out value: LongWord; out err: string): LongInt;
var
  fd: cint;
  p: Pointer;
  v: LongWord;
  saved: cint;
  st: TStat;
  size: Int64;
  rc: LongInt;
  currentDriver: Tgp107Driver;
begin
  err := '';
  value := 0;

  rc := VerifyPinnedIdentityAt(deviceFd, FixedString(inv.bdf), inv, err);
  if rc <> STATUS_OK then
    Exit(rc);

  rc := ReadBindingAt(deviceFd, currentDriver, err);
  if rc <> STATUS_OK then
    Exit(rc);
  if currentDriver.bound <> 0 then
  begin
    err := 'MMIO-FAIL step=driver-bound code=' +
      IntToStr(STATUS_DRIVER_BOUND) + ' driver=' +
      DriverName(currentDriver.name);
    Exit(STATUS_DRIVER_BOUND);
  end;

  fd := COpenAt(deviceFd, 'resource0',
                O_RDONLY or O_CLOEXEC or O_NOFOLLOW or O_NONBLOCK, 0);
  if fd < 0 then
  begin
    err := 'MMIO-FAIL step=resource0-open code=' +
      IntToStr(STATUS_OPEN) + ' errno=' + IntToStr(fpgeterrno);
    Exit(STATUS_OPEN);
  end;
  try
    if FpFStat(fd, st) <> 0 then
    begin
      saved := fpgeterrno;
      err := 'MMIO-FAIL step=bar0-stat code=' +
        IntToStr(STATUS_SIZE) + ' errno=' + IntToStr(saved);
      Exit(STATUS_SIZE);
    end;

    size := st.st_size;
    if (size < MMIO_WINDOW) or (QWord(size) <> QWord(expectedSize)) then
    begin
      err := 'MMIO-FAIL step=bar0-size-too-small code=' +
        IntToStr(STATUS_SIZE) + ' size=0x' + HexNoPad(QWord(size));
      Exit(STATUS_SIZE);
    end;

    { Repeat binding check immediately before mapping, using the same
      pinned PCI directory descriptor used for identity and resource0. }
    rc := ReadBindingAt(deviceFd, currentDriver, err);
    if rc <> STATUS_OK then
      Exit(rc);
    if currentDriver.bound <> 0 then
    begin
      err := 'MMIO-FAIL step=driver-bound code=' +
        IntToStr(STATUS_DRIVER_BOUND) + ' driver=' +
        DriverName(currentDriver.name);
      Exit(STATUS_DRIVER_BOUND);
    end;

    p := FpMMap(nil, MMIO_WINDOW, PROT_READ, MAP_SHARED, fd, 0);
    if p = MAP_FAILED then
    begin
      saved := fpgeterrno;
      err := 'MMIO-FAIL step=read-only-map code=' +
        IntToStr(STATUS_MAP) + ' errno=' + IntToStr(saved);
      Exit(STATUS_MAP);
    end;
    try
      v := Load32Asm(Pointer(PChar(p) + offset));
      value := v;
    finally
      FpMunmap(p, MMIO_WINDOW);
    end;
    Result := STATUS_OK;
  finally
    FpClose(fd);
  end;
end;

function Read32(const sysfsRoot, expectBdf: string; allow: LongInt;
                offset: LongWord; out value: LongWord;
                out err: string): LongInt;
var
  inv: Tgp107Inventory;
  rc, deviceFd: LongInt;
begin
  err := '';
  value := 0;
  if sysfsRoot = '' then
  begin
    err := 'MMIO-FAIL step=bad-argument code=' + IntToStr(STATUS_USAGE);
    Exit(STATUS_USAGE);
  end;

  rc := RequireOptin(allow, err);
  if rc <> STATUS_OK then
    Exit(rc);

  deviceFd := -1;
  rc := ScanInventoryPinned(sysfsRoot, expectBdf, inv, deviceFd, err);
  if rc <> STATUS_OK then
    Exit(rc);
  try
    rc := CheckDriver(inv, err);
    if rc <> STATUS_OK then
      Exit(rc);

    if inv.pci.bar0_space <> 0 then
    begin
      err := 'MMIO-FAIL step=bar0-not-memory code=' + IntToStr(STATUS_CONFIG);
      Exit(STATUS_CONFIG);
    end;
    if inv.pci.bar0_size < LongWord(MMIO_WINDOW) then
    begin
      err := 'MMIO-FAIL step=bar0-size-too-small code=' +
             IntToStr(STATUS_SIZE) + ' size=0x' +
             HexNoPad(QWord(inv.pci.bar0_size)) + ' required=' +
             IntToStr(MMIO_WINDOW);
      Exit(STATUS_SIZE);
    end;
    if (offset and 3) <> 0 then
    begin
      err := 'MMIO-FAIL step=offset-unaligned code=' +
             IntToStr(STATUS_OFFSET) + ' offset=0x' + HexNoPad(QWord(offset));
      Exit(STATUS_OFFSET);
    end;
    if (offset > LongWord(MMIO_WINDOW - 4)) or
       (QWord(offset) + 4 > QWord(inv.pci.bar0_size)) then
    begin
      err := 'MMIO-FAIL step=offset-out-of-window code=' +
             IntToStr(STATUS_OFFSET) + ' offset=0x' + HexNoPad(QWord(offset)) +
             ' size=0x' + HexNoPad(QWord(inv.pci.bar0_size));
      Exit(STATUS_OFFSET);
    end;

    Result := MapRead32(deviceFd, inv, inv.pci.bar0_size,
                        offset, value, err);
  finally
    if deviceFd >= 0 then
      FpClose(deviceFd);
  end;
end;

end.
