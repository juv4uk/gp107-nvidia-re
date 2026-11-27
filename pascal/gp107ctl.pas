program gp107ctl_pascal;

{
  Free Pascal CLI for the GP107 userspace capability identity slice.

  Own clean-room code. It reads sysfs only, keeps fail-closed named errors,
  and uses the Pascal inline assembler primitive solely for one read-only
  32-bit load after all gates have passed. Hardware MMIO is NOT_RUN.
}

{$mode objfpc}{$H+}{$codepage utf8}{$packrecords 1}

uses
  SysUtils, gp107_identity, gp107_mmio, gp107_capabilities;

function HexN(v: QWord; width: Integer): string;
begin
  Result := LowerCase(IntToHex(v, width));
end;

function BoolStr(cond: Boolean; const yesText, noText: string): string;
begin
  if cond then Result := yesText else Result := noText;
end;

function FixedString(const chars: array of Char): string;
var
  i: Integer;
begin
  Result := '';
  for i := Low(chars) to High(chars) do
  begin
    if chars[i] = #0 then
      Break;
    Result := Result + chars[i];
  end;
end;

function Usage: LongInt;
begin
  WriteLn(StdErr,
    'USAGE gp107ctl inventory [--sysfs-root=PATH] [--expect-bdf=BDF]');
  WriteLn(StdErr,
    '      gp107ctl mmio-read --offset=0xNN [--allow-mmio]');
  WriteLn(StdErr,
    '                         [--sysfs-root=PATH] [--expect-bdf=BDF]');
  WriteLn(StdErr,
    '      gp107ctl capabilities [--allow-mmio]');
  WriteLn(StdErr,
    '                            [--sysfs-root=PATH] [--expect-bdf=BDF]');
  WriteLn(StdErr, '      gp107ctl layout');
  Result := STATUS_USAGE;
end;

function ParseOffset(const s: string; out value: LongWord): Boolean;
var
  t, rest: string;
  i, digit: LongInt;
  acc: QWord;
begin
  Result := False;
  value := 0;
  t := Trim(s);
  if t = '' then
    Exit;
  acc := 0;
  if (Length(t) > 2) and (t[1] = '0') and (t[2] in ['x', 'X']) then
  begin
    rest := Copy(t, 3, MaxInt);
    if rest = '' then
      Exit;
    for i := 1 to Length(rest) do
    begin
      case rest[i] of
        '0'..'9': digit := Ord(rest[i]) - Ord('0');
        'a'..'f': digit := Ord(rest[i]) - Ord('a') + 10;
        'A'..'F': digit := Ord(rest[i]) - Ord('A') + 10;
      else
        Exit;
      end;
      acc := acc * 16 + QWord(digit);
      if acc > $ffffffff then
        Exit;
    end;
  end
  else if (Length(t) > 1) and (t[1] = '0') then
  begin
    rest := Copy(t, 2, MaxInt);
    for i := 1 to Length(rest) do
    begin
      if not (rest[i] in ['0'..'7']) then
        Exit;
      digit := Ord(rest[i]) - Ord('0');
      acc := acc * 8 + QWord(digit);
      if acc > $ffffffff then
        Exit;
    end;
  end
  else
  begin
    for i := 1 to Length(t) do
    begin
      if not (t[i] in ['0'..'9']) then
        Exit;
      digit := Ord(t[i]) - Ord('0');
      acc := acc * 10 + QWord(digit);
      if acc > $ffffffff then
        Exit;
    end;
  end;
  value := LongWord(acc);
  Result := True;
end;

procedure PrintInventory(const inv: Tgp107Inventory);
begin
  WriteLn('((kind . gp107-userspace-capability-identity)');
  WriteLn(' (authority . gp107-research-not-abi)');
  WriteLn(' (abi-pin . untouched)');
  WriteLn(' (pci (vendor . 0x', HexN(inv.pci.vendor, 4),
          ') (device . 0x', HexN(inv.pci.device, 4),
          ') (bdf . "', FixedString(inv.bdf), '")');
  WriteLn('  (bar0-base . 0x', HexN(inv.pci.bar0_base, 8),
          ') (bar0-size . 0x', HexN(inv.pci.bar0_size, 8), '))');
  WriteLn(' (config (revision . 0x', HexN(inv.pci.revision, 2),
          ') (class . 0x', HexN(inv.pci.class_code[2], 2),
          HexN(inv.pci.class_code[1], 2), HexN(inv.pci.class_code[0], 2),
          ') (header . 0x', HexN(inv.pci.header_type, 2),
          ') (command . 0x', HexN(inv.pci.command, 4), '))');
  WriteLn(' (bar0 (raw . 0x', HexN(inv.pci.bar0_raw, 8),
          ') (space . ', BoolStr(inv.pci.bar0_space <> 0, 'io', 'memory'),
          ') (width . ', BoolStr(inv.pci.bar0_width <> 0, '64-bit', '32-bit'),
          ') (prefetch . ', BoolStr(inv.pci.bar0_prefetch <> 0, 'yes', 'no'),
          ') (source . public-pci-header))');
  WriteLn(' (driver (bound . ', BoolStr(inv.driver.bound <> 0, 'yes', 'no'),
          ') (name . "', FixedString(inv.driver.name), '"))');
  WriteLn(' (rights (pci . inventory-only) (rm-control . none) (mmio . none))');
  WriteLn(' (evidence (pci . runtime-proven) (driver . runtime-proven) (boot0 . unproven))');
  WriteLn(' (summary . IDENTITY-OK))');
end;

var
  root, expect, mode, err, arg: string;
  inv: Tgp107Inventory;
  offset, value: LongWord;
  allow, i, rc: LongInt;
begin
  if ParamCount < 1 then
    Halt(Usage);
  mode := ParamStr(1);

  if mode = 'layout' then
  begin
    WriteLn('LAYOUT-OK identity=', SizeOf(Tgp107Pci),
            ' binding=', SizeOf(Tgp107Driver),
            ' inventory=', SizeOf(Tgp107Inventory));
    Halt(STATUS_OK);
  end;
  if (mode <> 'inventory') and (mode <> 'mmio-read') and
     (mode <> 'capabilities') then
    Halt(Usage);

  root := DEFAULT_SYSFS;
  expect := EXPECTED_BDF;
  offset := 0;
  value := 0;
  allow := 0;

  for i := 2 to ParamCount do
  begin
    arg := ParamStr(i);
    if Copy(arg, 1, 13) = '--sysfs-root=' then
      root := Copy(arg, 14, MaxInt)
    else if Copy(arg, 1, 13) = '--expect-bdf=' then
      expect := Copy(arg, 14, MaxInt)
    else if Copy(arg, 1, 9) = '--offset=' then
    begin
      if not ParseOffset(Copy(arg, 10, MaxInt), offset) then
      begin
        WriteLn(StdErr, 'USAGE-FAIL step=offset code=', STATUS_USAGE,
                ' value=', Copy(arg, 10, MaxInt));
        Halt(STATUS_USAGE);
      end;
    end
    else if arg = '--allow-mmio' then
      allow := 1
    else if arg = '--help' then
      Halt(Usage)
    else
    begin
      WriteLn(StdErr, 'USAGE-FAIL step=unknown-option code=', STATUS_USAGE,
              ' value=', arg);
      Halt(STATUS_USAGE);
    end;
  end;

  if mode = 'inventory' then
  begin
    rc := ScanInventory(root, LowerCase(expect), inv, err);
    if rc <> STATUS_OK then
    begin
      WriteLn(StdErr, err);
      Halt(rc);
    end;
    PrintInventory(inv);
    Halt(STATUS_OK);
  end;

  if mode = 'capabilities' then
  begin
    rc := ScanInventory(root, LowerCase(expect), inv, err);
    if rc <> STATUS_OK then
    begin
      WriteLn(StdErr, err);
      Halt(rc);
    end;
    Write(CapabilityReport(inv, allow));
    Halt(STATUS_OK);
  end;

  rc := RequireOptin(allow, err);
  if rc <> STATUS_OK then
  begin
    WriteLn(StdErr, err);
    Halt(rc);
  end;
  rc := ScanInventory(root, LowerCase(expect), inv, err);
  if rc <> STATUS_OK then
  begin
    WriteLn(StdErr, err);
    Halt(rc);
  end;
  rc := CheckDriver(inv, err);
  if rc <> STATUS_OK then
  begin
    WriteLn(StdErr, err);
    Halt(rc);
  end;
  rc := Read32(root, inv, allow, offset, value, err);
  if rc <> STATUS_OK then
  begin
    WriteLn(StdErr, err);
    Halt(rc);
  end;
  WriteLn('((kind . gp107-mmio-read)');
  WriteLn(' (offset . 0x', HexN(offset, 1), ') (value . 0x', HexN(value, 8), ')');
  WriteLn(' (right . read-only) (evidence . runtime-proven)');
  WriteLn(' (boot0 . unproven) (summary . MMIO-READ-OK))');
  Halt(STATUS_OK);
end.
