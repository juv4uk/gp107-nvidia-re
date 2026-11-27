unit gp107_mmio;

{
  Clean-room Free Pascal read-only aperture seam for GP107.

  This unit is the Pascal counterpart of lib/gp107_mmio.c. It keeps the same
  fail-closed gates and the same named error states. The inline assembler
  primitive is owned by this project and performs exactly one 32-bit load
  with a following load fence; it contains no register constants, no writes,
  no vendor sequence and no boot assumption.

  Hardware MMIO is NOT_RUN. This unit does not grant a right to touch a
  register; it only mirrors the C reference behaviour on a mapped read-only
  window that the caller has already gated.
}

{$mode objfpc}{$H+}{$asmmode intel}{$codepage utf8}

interface

uses
  SysUtils, gp107_identity;

function Load32Asm(addr: Pointer): LongWord; assembler;
function RequireOptin(allow: LongInt; out err: string): LongInt;
function CheckDriver(const inv: Tgp107Inventory; out err: string): LongInt;
function Read32(const root: string; const inv: Tgp107Inventory;
                allow: LongInt; offset: LongWord; out value: LongWord;
                out err: string): LongInt;

implementation

uses
  BaseUnix, Unix, Linux;

function HexNoPad(v: LongWord): string;
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

function Read32(const root: string; const inv: Tgp107Inventory;
                allow: LongInt; offset: LongWord; out value: LongWord;
                out err: string): LongInt;
var
  path: string;
  fd: cint;
  p: Pointer;
  v: LongWord;
  saved: cint;
begin
  err := '';
  value := 0;
  if root = '' then
  begin
    err := 'MMIO-FAIL step=bad-argument code=' + IntToStr(STATUS_USAGE);
    Exit(STATUS_USAGE);
  end;
  if allow = 0 then
  begin
    err := 'MMIO-FAIL step=opt-in-required code=' + IntToStr(STATUS_OPTIN);
    Exit(STATUS_OPTIN);
  end;
  if inv.driver.bound <> 0 then
  begin
    err := 'MMIO-FAIL step=driver-bound code=' +
           IntToStr(STATUS_DRIVER_BOUND) + ' driver=' +
           DriverName(inv.driver.name);
    Exit(STATUS_DRIVER_BOUND);
  end;
  if inv.pci.bar0_size < LongWord(MMIO_WINDOW) then
  begin
    err := 'MMIO-FAIL step=bar0-size-too-small code=' +
           IntToStr(STATUS_SIZE) + ' size=0x' + HexNoPad(inv.pci.bar0_size);
    Exit(STATUS_SIZE);
  end;
  if offset > LongWord(MMIO_WINDOW - 4) then
  begin
    err := 'MMIO-FAIL step=offset-out-of-window code=' +
           IntToStr(STATUS_OFFSET) + ' offset=0x' + HexNoPad(offset);
    Exit(STATUS_OFFSET);
  end;
  if QWord(offset) + 4 > QWord(inv.pci.bar0_size) then
  begin
    err := 'MMIO-FAIL step=offset-out-of-range code=' +
           IntToStr(STATUS_SIZE) + ' offset=0x' + HexNoPad(offset);
    Exit(STATUS_SIZE);
  end;

  path := root + '/bus/pci/devices/' + string(inv.bdf) + '/resource0';
  if Length(path) > 511 then
  begin
    err := 'MMIO-FAIL step=path-too-long code=' + IntToStr(STATUS_PARSE);
    Exit(STATUS_PARSE);
  end;

  fd := FpOpen(PChar(path), O_RDONLY or O_CLOEXEC, 0);
  if fd < 0 then
  begin
    err := 'MMIO-FAIL step=resource0-open code=' +
           IntToStr(STATUS_OPEN) + ' errno=' + IntToStr(fpgeterrno);
    Exit(STATUS_OPEN);
  end;

  p := FpMMap(nil, MMIO_WINDOW, PROT_READ, MAP_SHARED, fd, 0);
  if p = MAP_FAILED then
  begin
    saved := fpgeterrno;
    FpClose(fd);
    err := 'MMIO-FAIL step=read-only-map code=' +
           IntToStr(STATUS_MAP) + ' errno=' + IntToStr(saved);
    Exit(STATUS_MAP);
  end;
  FpClose(fd);

  v := Load32Asm(Pointer(PChar(p) + offset));
  FpMunmap(p, MMIO_WINDOW);
  value := v;
  Result := STATUS_OK;
end;

end.
