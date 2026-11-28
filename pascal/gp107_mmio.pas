unit gp107_mmio;

{
  Clean-room Free Pascal counterpart of the C capability gate.

  This unit validates intent, sysfs identity, driver binding, BAR0 type/size,
  alignment and offset bounds. It then returns READ_SAFE_OFFSET_UNPROVEN.
  It never opens resource0, maps BAR0, or dereferences a hardware aperture.

  Load32Asm is retained only as an isolated instruction reference; Read32
  never calls it. Hardware MMIO is NOT AUTHORIZED / NOT RUN.
}

{$mode objfpc}{$H+}{$asmmode intel}{$codepage utf8}

interface

uses
  SysUtils, gp107_identity;

function RequireOptin(allow: LongInt; out err: string): LongInt;
function CheckDriver(const inv: Tgp107Inventory; out err: string): LongInt;
function Read32(const sysfsRoot, expectBdf: string; allow: LongInt;
                offset: LongWord; out value: LongWord;
                out err: string): LongInt;

implementation

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

function Read32(const sysfsRoot, expectBdf: string; allow: LongInt;
                offset: LongWord; out value: LongWord;
                out err: string): LongInt;
var
  inv: Tgp107Inventory;
  rc: LongInt;
begin
  err := '';
  value := 0;
  if (sysfsRoot = '') or (expectBdf = '') then
  begin
    err := 'MMIO-FAIL step=bad-argument code=' + IntToStr(STATUS_USAGE);
    Exit(STATUS_USAGE);
  end;

  rc := RequireOptin(allow, err);
  if rc <> STATUS_OK then
    Exit(rc);

  rc := ScanInventory(sysfsRoot, expectBdf, inv, err);
  if rc <> STATUS_OK then
    Exit(rc);

  rc := CheckDriver(inv, err);
  if rc <> STATUS_OK then
    Exit(rc);

  rc := VerifyPinnedIdentity(sysfsRoot, expectBdf, inv, err);
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

  err := 'MMIO-FAIL step=read-safe-offset-unproven code=' +
         IntToStr(STATUS_SAFE_OFFSET_UNPROVEN) + ' offset=0x' +
         HexNoPad(QWord(offset));
  Result := STATUS_SAFE_OFFSET_UNPROVEN;
end;

end.
