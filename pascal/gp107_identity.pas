unit gp107_identity;

{
  Clean-room Free Pascal capability identity for GP107 / GTX 1050 Ti.

  Authority: this Pascal implementation over sysfs only. It is research code,
  not an ABI, not a kernel driver, and not a claim about register access.
  SENS, CML, wsm-os-lisp, target contract and ABI pins are untouched.

  Two sources are kept distinct on purpose:
    * sysfs PCI config/vendor/device = inventory fact;
    * sysfs driver link             = binding fact.
  Neither is promoted into a right to touch an aperture.

  Packed records and compile-time SizeOf assertions keep the record layout
  identical to the C reference implementation.
}

{$mode objfpc}{$H+}{$codepage utf8}{$packrecords 1}

interface

uses
  SysUtils, BaseUnix, Unix, Linux;

const
  PCI_VENDOR_NVIDIA   = $10de;
  PCI_DEVICE_GP107    = $1c82;
  EXPECTED_BDF        = '0000:01:00.0';
  DEFAULT_SYSFS       = '/sys';
  CONFIG_BYTES        = 32;
  MMIO_WINDOW         = 4096;

  STATUS_OK             = 0;
  STATUS_OPEN           = 2;
  STATUS_READ           = 3;
  STATUS_PARSE          = 4;
  STATUS_CONFIG         = 5;
  STATUS_NO_MATCH       = 12;
  STATUS_CARD_COUNT     = 13;
  STATUS_BDF            = 14;
  STATUS_OPTIN          = 15;
  STATUS_DRIVER_BOUND   = 16;
  STATUS_OFFSET         = 17;
  STATUS_MAP            = 18;
  STATUS_SIZE           = 19;
  STATUS_BINDING        = 20;
  STATUS_SAFE_OFFSET_UNPROVEN = 21;
  STATUS_USAGE          = 64;

type
  Tgp107Pci = record
    vendor: Word;            {  0 }
    device: Word;            {  2 }
    domain: Word;            {  4 }
    bus: Byte;               {  6 }
    slot: Byte;              {  7 }
    func: Byte;              {  8 }
    revision: Byte;          {  9 }
    command: Word;           { 10 }
    bar0_raw: LongWord;      { 12 }
    bar0_base: LongWord;     { 16 }
    bar0_size: LongWord;     { 20 }
    class_code: array[0..2] of Byte; { 24 }
    header_type: Byte;       { 27 }
    bar0_space: Byte;        { 28 }
    bar0_width: Byte;        { 29 }
    bar0_prefetch: Byte;     { 30 }
    cfg_bytes: Byte;         { 31 }
  end;

  Tgp107Driver = record
    name: array[0..63] of Char; {  0 }
    bound: LongInt;             { 64 }
  end;

  Tgp107Inventory = record
    pci: Tgp107Pci;             {   0 }
    driver: Tgp107Driver;       {  32 }
    bdf: array[0..31] of Char;  { 100 }
    candidate_count: LongInt;   { 132 }
    valid_count: LongInt;       { 136 }
  end;

{$if SizeOf(Tgp107Pci) <> 32}
{$fatal gp107-pci-layout-drift}
{$endif}
{$if SizeOf(Tgp107Driver) <> 68}
{$fatal gp107-driver-layout-drift}
{$endif}
{$if SizeOf(Tgp107Inventory) <> 140}
{$fatal gp107-inventory-layout-drift}
{$endif}

procedure FailNamed(const step: string; code: Integer);
function ReadSmallFile(const path: string; out text: string): Boolean;
function ParseHex16(const s: string; out value: Word): Boolean;
function ScanInventory(const root, expectBdf: string;
                       out inv: Tgp107Inventory; out err: string): Integer;
function VerifyPinnedIdentity(const root, expectBdf: string;
                              const expected: Tgp107Inventory;
                              out err: string): Integer;

implementation

const
  LINUX_O_DIRECTORY_FLAG = $10000;
  LINUX_O_NOFOLLOW_FLAG  = $20000;
  LINUX_O_NONBLOCK_FLAG  = $0800;

function libc_openat(dirfd: cint; pathname: PChar; flags: cint;
                     mode: LongWord): cint; cdecl; external 'c' name 'openat';
function libc_readlinkat(dirfd: cint; pathname: PChar; buffer: PChar;
                         bufsiz: SizeUInt): ssize_t; cdecl; external 'c' name 'readlinkat';

procedure FailNamed(const step: string; code: Integer);
begin
  WriteLn(StdErr, step, ' code=', code);
  Halt(code);
end;

function ReadSmallFile(const path: string; out text: string): Boolean;
var
  fd: cint;
  n: ssize_t;
  buf: array[0..127] of Byte;
begin
  Result := False;
  text := '';
  fd := FpOpen(PChar(path), O_RDONLY or O_CLOEXEC, 0);
  if fd < 0 then
    Exit;
  FillChar(buf, SizeOf(buf), 0);
  n := FpRead(fd, buf[0], SizeOf(buf) - 1);
  FpClose(fd);
  if n < 0 then
    Exit;
  SetLength(text, n);
  if n > 0 then
    Move(buf[0], text[1], n);
  Result := True;
end;

function ParseHex16(const s: string; out value: Word): Boolean;
var
  t: string;
  v: LongInt;
begin
  Result := False;
  value := 0;
  t := Trim(s);
  if Copy(t, 1, 2) = '0x' then
    Delete(t, 1, 2);
  try
    v := StrToInt('$' + t);
  except
    on EConvertError do
      Exit;
  end;
  if (v < 0) or (v > $ffff) then
    Exit;
  value := Word(v);
  Result := True;
end;

function ReadSmallAt(dirfd: cint; const name: string;
                    out text: string; out savedErr: cint): Boolean;
var
  fd: cint;
  n: ssize_t;
  st: TStat;
  buf: array[0..2047] of Byte;
begin
  Result := False;
  text := '';
  savedErr := 0;
  fd := libc_openat(dirfd, PChar(name),
                    O_RDONLY or O_CLOEXEC or LINUX_O_NOFOLLOW_FLAG or
                    LINUX_O_NONBLOCK_FLAG, 0);
  if fd < 0 then
  begin
    savedErr := fpgeterrno;
    Exit;
  end;
  try
    if FpFStat(fd, st) <> 0 then
    begin
      savedErr := fpgeterrno;
      Exit;
    end;
    if (st.st_mode and S_IFMT) <> S_IFREG then
    begin
      savedErr := ESysEinval;
      Exit;
    end;
    FillChar(buf, SizeOf(buf), 0);
    n := FpRead(fd, buf[0], SizeOf(buf) - 1);
    if n < 0 then
    begin
      savedErr := fpgeterrno;
      Exit;
    end;
    if n >= SizeOf(buf) - 1 then
    begin
      savedErr := ESysEinval;
      Exit;
    end;
    SetLength(text, n);
    if n > 0 then
      Move(buf[0], text[1], n);
    Result := True;
  finally
    FpClose(fd);
  end;
end;

function ReadConfigAt(dirfd: cint; out cfg: array of Byte;
                      out savedErr: cint): Boolean;
var
  fd: cint;
  n: ssize_t;
  st: TStat;
begin
  Result := False;
  savedErr := 0;
  fd := libc_openat(dirfd, PChar('config'),
                    O_RDONLY or O_CLOEXEC or LINUX_O_NOFOLLOW_FLAG or
                    LINUX_O_NONBLOCK_FLAG, 0);
  if fd < 0 then
  begin
    savedErr := fpgeterrno;
    Exit;
  end;
  try
    if FpFStat(fd, st) <> 0 then
    begin
      savedErr := fpgeterrno;
      Exit;
    end;
    if (st.st_mode and S_IFMT) <> S_IFREG then
    begin
      savedErr := ESysEinval;
      Exit;
    end;
    FillChar(cfg[0], Length(cfg), 0);
    n := FpPRead(fd, cfg[0], Length(cfg), 0);
    if n < 0 then
    begin
      savedErr := fpgeterrno;
      Exit;
    end;
    Result := n = Length(cfg);
    if not Result then
      savedErr := ESysEio;
  finally
    FpClose(fd);
  end;
end;

function UeventValue(const uevent, key: string; out value: string): Boolean;
var
  remaining, line: string;
  newlineAt, prefixLength: SizeInt;
begin
  Result := False;
  value := '';
  remaining := uevent;
  prefixLength := Length(key) + 1;
  while remaining <> '' do
  begin
    newlineAt := Pos(#10, remaining);
    if newlineAt > 0 then
    begin
      line := Copy(remaining, 1, newlineAt - 1);
      Delete(remaining, 1, newlineAt);
    end
    else
    begin
      line := remaining;
      remaining := '';
    end;
    if (Length(line) > prefixLength) and
       (Copy(line, 1, prefixLength) = key + '=') then
    begin
      value := Trim(Copy(line, prefixLength + 1, MaxInt));
      Result := value <> '';
      Exit;
    end;
  end;
end;

function ParseHexPair(const text: string; out first, second: Word): Boolean;
var
  separator: SizeInt;
begin
  Result := False;
  first := 0;
  second := 0;
  separator := Pos(':', text);
  if separator <= 1 then
    Exit;
  if not ParseHex16(Copy(text, 1, separator - 1), first) then
    Exit;
  if not ParseHex16(Copy(text, separator + 1, MaxInt), second) then
    Exit;
  Result := True;
end;

function InventoryBdf(const inv: Tgp107Inventory): string;
var
  i: Integer;
begin
  Result := '';
  for i := Low(inv.bdf) to High(inv.bdf) do
  begin
    if inv.bdf[i] = #0 then
      Break;
    Result := Result + inv.bdf[i];
  end;
end;

function DriverName(const driver: Tgp107Driver): string;
var
  i: Integer;
begin
  Result := '';
  for i := Low(driver.name) to High(driver.name) do
  begin
    if driver.name[i] = #0 then
      Break;
    Result := Result + driver.name[i];
  end;
end;

function ReadBindingAt(dirfd: cint; var outDriver: Tgp107Driver;
                       out err: string): Integer;
var
  buf: array[0..511] of Byte;
  n: ssize_t;
  saved: cint;
  target, base: string;
  i: Integer;
begin
  err := '';
  FillChar(outDriver, SizeOf(outDriver), 0);
  FillChar(buf, SizeOf(buf), 0);
  n := libc_readlinkat(dirfd, PChar('driver'), PChar(@buf[0]), SizeOf(buf) - 1);
  if n < 0 then
  begin
    saved := fpgeterrno;
    if saved = ESysEnoent then
      Exit(STATUS_OK);
    err := 'MMIO-FAIL step=driver-binding-read code=' +
           IntToStr(STATUS_BINDING) + ' errno=' + IntToStr(saved);
    Exit(STATUS_BINDING);
  end;
  if (n = 0) or (n >= SizeOf(buf) - 1) then
  begin
    err := 'MMIO-FAIL step=driver-binding-read code=' +
           IntToStr(STATUS_BINDING);
    Exit(STATUS_BINDING);
  end;
  SetLength(target, n);
  Move(buf[0], target[1], n);
  i := LastDelimiter('/', target);
  if i > 0 then
    base := Copy(target, i + 1, MaxInt)
  else
    base := target;
  if (Length(base) = 0) or (Length(base) >= Length(outDriver.name)) then
  begin
    err := 'MMIO-FAIL step=driver-name-invalid code=' +
           IntToStr(STATUS_BINDING);
    Exit(STATUS_BINDING);
  end;
  for i := 1 to Length(base) do
    outDriver.name[i - 1] := base[i];
  outDriver.bound := 1;
  Result := STATUS_OK;
end;

function PinnedIdentityError(const step: string; code: Integer;
                             const detail: string; out err: string): Integer;
begin
  err := 'MMIO-FAIL step=' + step + ' code=' + IntToStr(code);
  if detail <> '' then
    err := err + ' ' + detail;
  Result := code;
end;

function VerifyPinnedIdentity(const root, expectBdf: string;
                              const expected: Tgp107Inventory;
                              out err: string): Integer;
var
  expectedBdf, devdir: string;
  dirfd, saved: cint;
  st: TStat;
  uevent, slotName, pciId, pciSubsystemId: string;
  vendorText, deviceText, revisionText: string;
  subsystemVendorText, subsystemDeviceText: string;
  vendor, device, revision: Word;
  subsystemVendor, subsystemDevice: Word;
  eventVendor, eventDevice, eventSubsystemVendor, eventSubsystemDevice: Word;
  cfg: array[0..CONFIG_BYTES - 1] of Byte;
  liveDriver: Tgp107Driver;
begin
  err := '';
  expectedBdf := InventoryBdf(expected);
  if (root = '') or (expectBdf = '') or (expectedBdf = '') then
    Exit(PinnedIdentityError('bad-argument', STATUS_USAGE, '', err));
  if (expectBdf <> LowerCase(expectBdf)) or (expectedBdf <> expectBdf) then
    Exit(PinnedIdentityError('pinned-bdf-mismatch', STATUS_BDF,
         'expected=' + expectBdf + ' inventory=' + expectedBdf, err));

  devdir := IncludeTrailingPathDelimiter(root) +
            'bus/pci/devices/' + expectBdf;
  if Length(devdir) > 511 then
    Exit(PinnedIdentityError('device-path-too-long', STATUS_PARSE, '', err));
  dirfd := FpOpen(PChar(devdir),
                  O_RDONLY or O_CLOEXEC or LINUX_O_DIRECTORY_FLAG, 0);
  if dirfd < 0 then
  begin
    saved := fpgeterrno;
    Exit(PinnedIdentityError('device-directory-open', STATUS_OPEN,
         'errno=' + IntToStr(saved), err));
  end;
  try
    if FpFStat(dirfd, st) <> 0 then
    begin
      saved := fpgeterrno;
      Exit(PinnedIdentityError('device-directory-stat', STATUS_OPEN,
           'errno=' + IntToStr(saved), err));
    end;
    if (st.st_mode and S_IFMT) <> S_IFDIR then
      Exit(PinnedIdentityError('device-directory-stat', STATUS_OPEN,
           'errno=' + IntToStr(ESysEnotdir), err));

    if not ReadSmallAt(dirfd, 'uevent', uevent, saved) then
      Exit(PinnedIdentityError('pinned-uevent-read', STATUS_CONFIG,
           'errno=' + IntToStr(saved), err));
    if not UeventValue(uevent, 'PCI_SLOT_NAME', slotName) then
      Exit(PinnedIdentityError('pinned-uevent-read', STATUS_CONFIG,
           'field=PCI_SLOT_NAME', err));
    if slotName <> expectBdf then
      Exit(PinnedIdentityError('pinned-bdf-mismatch', STATUS_BDF,
           'expected=' + expectBdf + ' got=' + slotName, err));

    if not UeventValue(uevent, 'PCI_ID', pciId) or
       not UeventValue(uevent, 'PCI_SUBSYS_ID', pciSubsystemId) or
       not ParseHexPair(pciId, eventVendor, eventDevice) or
       not ParseHexPair(pciSubsystemId, eventSubsystemVendor,
                        eventSubsystemDevice) then
      Exit(PinnedIdentityError('pinned-pci-uevent', STATUS_CONFIG, '', err));

    if not ReadSmallAt(dirfd, 'vendor', vendorText, saved) or
       not ReadSmallAt(dirfd, 'device', deviceText, saved) or
       not ReadSmallAt(dirfd, 'revision', revisionText, saved) or
       not ReadSmallAt(dirfd, 'subsystem_vendor', subsystemVendorText, saved) or
       not ReadSmallAt(dirfd, 'subsystem_device', subsystemDeviceText, saved) or
       not ParseHex16(vendorText, vendor) or
       not ParseHex16(deviceText, device) or
       not ParseHex16(revisionText, revision) or
       not ParseHex16(subsystemVendorText, subsystemVendor) or
       not ParseHex16(subsystemDeviceText, subsystemDevice) then
      Exit(PinnedIdentityError('pinned-pci-attributes', STATUS_CONFIG,
           'errno=' + IntToStr(saved), err));

    if not ReadConfigAt(dirfd, cfg, saved) then
      Exit(PinnedIdentityError('pinned-config-read', STATUS_CONFIG,
           'errno=' + IntToStr(saved), err));

    if (vendor <> PCI_VENDOR_NVIDIA) or (device <> PCI_DEVICE_GP107) or
       (vendor <> expected.pci.vendor) or (device <> expected.pci.device) or
       (revision <> expected.pci.revision) or
       (eventVendor <> vendor) or (eventDevice <> device) or
       (eventSubsystemVendor <> subsystemVendor) or
       (eventSubsystemDevice <> subsystemDevice) or
       (cfg[0] <> Byte(vendor and $ff)) or
       (cfg[1] <> Byte(vendor shr 8)) or
       (cfg[2] <> Byte(device and $ff)) or
       (cfg[3] <> Byte(device shr 8)) or
       (cfg[$08] <> Byte(revision)) then
      Exit(PinnedIdentityError('pinned-pci-identity', STATUS_CONFIG,
           'bdf=' + expectBdf + ' vendor=0x' + LowerCase(IntToHex(vendor, 1)) +
           ' device=0x' + LowerCase(IntToHex(device, 1)) +
           ' revision=0x' + LowerCase(IntToHex(revision, 1)), err));

    Result := ReadBindingAt(dirfd, liveDriver, err);
    if Result <> STATUS_OK then
      Exit;
    if liveDriver.bound <> 0 then
    begin
      err := 'MMIO-FAIL step=driver-bound code=' +
             IntToStr(STATUS_DRIVER_BOUND) + ' driver=' +
             DriverName(liveDriver);
      Exit(STATUS_DRIVER_BOUND);
    end;
    Result := STATUS_OK;
  finally
    FpClose(dirfd);
  end;
end;

function ReadConfig(const path: string; out cfg: array of Byte): Boolean;
var
  fd: cint;
  n: ssize_t;
begin
  Result := False;
  fd := FpOpen(PChar(path), O_RDONLY or O_CLOEXEC, 0);
  if fd < 0 then
    Exit;
  FillChar(cfg[0], Length(cfg), 0);
  n := FpPRead(fd, cfg[0], Length(cfg), 0);
  FpClose(fd);
  Result := n = Length(cfg);
end;

function ParseBdf(const name: string; var id: Tgp107Pci;
                  out bdf: string): Boolean;
var
  d, b, s, f: LongInt;
begin
  Result := False;
  bdf := '';
  if Length(name) < 12 then
    Exit;
  if (name[5] <> ':') or (name[8] <> ':') or (name[11] <> '.') then
    Exit;
  if not TryStrToInt('$' + Copy(name, 1, 4), d) then Exit;
  if not TryStrToInt('$' + Copy(name, 6, 2), b) then Exit;
  if not TryStrToInt('$' + Copy(name, 9, 2), s) then Exit;
  if not TryStrToInt(Copy(name, 12, MaxInt), f) then Exit;
  if (d < 0) or (d > $ffff) or (b < 0) or (b > $ff) or
     (s < 0) or (s > $1f) or (f < 0) or (f > 7) then
    Exit;
  id.domain := Word(d);
  id.bus := Byte(b);
  id.slot := Byte(s);
  id.func := Byte(f);
  bdf := LowerCase(IntToHex(d, 4) + ':' + IntToHex(b, 2) + ':' +
                   IntToHex(s, 2) + '.' + IntToStr(f));
  Result := True;
end;

function BindingError(const marker: string; out err: string): LongInt;
begin
  err := marker;
  Result := STATUS_BINDING;
end;

function ReadBinding(const devdir: string; var outDriver: Tgp107Driver;
                     out err: string): LongInt;
var
  dirfd, saved: cint;
  st: TStat;
  path, target, base: string;
  n: ssize_t;
  buf: array[0..511] of Byte;
  i: Integer;
begin
  err := '';
  FillChar(outDriver, SizeOf(outDriver), 0);

  { Preliminary inventory observation only. Read32() repeats driver binding
    from the pinned directory fd in VerifyPinnedIdentity() before returning
    its safe-offset refusal; this pathname lookup is not that authorization gate. }
  dirfd := FpOpen(PChar(devdir), O_RDONLY or O_CLOEXEC, 0);
  if dirfd < 0 then
  begin
    saved := fpgeterrno;
    Exit(BindingError('IDENTITY-FAIL step=driver-binding-open code=' +
      IntToStr(STATUS_BINDING) + ' errno=' + IntToStr(saved), err));
  end;
  try
    if FpFStat(dirfd, st) <> 0 then
    begin
      saved := fpgeterrno;
      Exit(BindingError('IDENTITY-FAIL step=driver-binding-open code=' +
        IntToStr(STATUS_BINDING) + ' errno=' + IntToStr(saved), err));
    end;
    if (st.st_mode and S_IFMT) <> S_IFDIR then
      Exit(BindingError('IDENTITY-FAIL step=driver-binding-open code=' +
        IntToStr(STATUS_BINDING) + ' errno=' + IntToStr(ESysEnotdir), err));
  finally
    FpClose(dirfd);
  end;

  { FPC 3.2.2 RTL provides FpReadLink but no FpReadLinkAt; use the equivalent
    path-based FpReadLink against the already-validated device directory and
    preserve the C named markers and errno reporting. }
  path := IncludeTrailingPathDelimiter(devdir) + 'driver';
  FillChar(buf, SizeOf(buf), 0);
  n := FpReadLink(PChar(path), PChar(@buf[0]), SizeOf(buf) - 1);
  if n < 0 then
  begin
    saved := fpgeterrno;
    if saved = ESysEnoent then
      Exit(STATUS_OK);
    Exit(BindingError('IDENTITY-FAIL step=driver-binding-read code=' +
      IntToStr(STATUS_BINDING) + ' errno=' + IntToStr(saved), err));
  end;
  if (n = 0) or (n >= SizeOf(buf) - 1) then
    Exit(BindingError('IDENTITY-FAIL step=driver-binding-read code=' +
      IntToStr(STATUS_BINDING), err));

  SetLength(target, n);
  Move(buf[0], target[1], n);
  i := LastDelimiter('/', target);
  if i > 0 then
    base := Copy(target, i + 1, MaxInt)
  else
    base := target;
  if (Length(base) = 0) or (Length(base) >= Length(outDriver.name)) then
    Exit(BindingError('IDENTITY-FAIL step=driver-name-invalid code=' +
      IntToStr(STATUS_BINDING), err));
  for i := 1 to Length(base) do
    outDriver.name[i - 1] := base[i];
  outDriver.bound := 1;
  Result := STATUS_OK;
end;

procedure ReadBar0Size(const devdir: string; var id: Tgp107Pci);
var
  path: string;
  st: TStat;
begin
  id.bar0_size := 0;
  path := IncludeTrailingPathDelimiter(devdir) + 'resource0';
  if FpStat(PChar(path), st) = 0 then
    if st.st_size > 0 then
      id.bar0_size := LongWord(st.st_size and $ffffffff);
end;

function ScanInventory(const root, expectBdf: string;
                       out inv: Tgp107Inventory; out err: string): Integer;
var
  devdir, path, vpath, dpath, cpath, text, foundBdf: string;
  cfg: array[0..CONFIG_BYTES - 1] of Byte;
  sr: TSearchRec;
  candidate: Tgp107Pci;
  sv, sd, cv, cd: Word;
  rc, flags: LongInt;
begin
  err := '';
  FillChar(inv, SizeOf(inv), 0);
  foundBdf := '';
  devdir := IncludeTrailingPathDelimiter(root) + 'bus/pci/devices';

  if FindFirst(devdir + '/*', faAnyFile, sr) <> 0 then
  begin
    err := 'IDENTITY-FAIL step=pci-devices-open code=' + IntToStr(STATUS_OPEN);
    Exit(STATUS_OPEN);
  end;
  try
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then
        Continue;
      path := IncludeTrailingPathDelimiter(devdir) + sr.Name;
      vpath := IncludeTrailingPathDelimiter(path) + 'vendor';
      dpath := IncludeTrailingPathDelimiter(path) + 'device';
      cpath := IncludeTrailingPathDelimiter(path) + 'config';

      if not ReadSmallFile(vpath, text) then Continue;
      if not ParseHex16(text, sv) then Continue;
      if not ReadSmallFile(dpath, text) then Continue;
      if not ParseHex16(text, sd) then Continue;
      if (sv <> PCI_VENDOR_NVIDIA) or (sd <> PCI_DEVICE_GP107) then Continue;
      Inc(inv.candidate_count);

      if not ReadConfig(cpath, cfg) then
      begin
        err := 'IDENTITY-FAIL step=pci-config-read code=' +
               IntToStr(STATUS_CONFIG) + ' bdf=' + sr.Name;
        Exit(STATUS_CONFIG);
      end;
      cv := Word(cfg[0] or (Word(cfg[1]) shl 8));
      cd := Word(cfg[2] or (Word(cfg[3]) shl 8));
      if (cv <> sv) or (cd <> sd) then
      begin
        err := 'IDENTITY-FAIL step=pci-config-mismatch code=' +
               IntToStr(STATUS_CONFIG) + ' bdf=' + sr.Name;
        Exit(STATUS_CONFIG);
      end;

      FillChar(candidate, SizeOf(candidate), 0);
      candidate.vendor := cv;
      candidate.device := cd;
      candidate.command := Word(cfg[$04] or (Word(cfg[$05]) shl 8));
      candidate.revision := cfg[$08];
      candidate.class_code[0] := cfg[$09];
      candidate.class_code[1] := cfg[$0a];
      candidate.class_code[2] := cfg[$0b];
      candidate.header_type := cfg[$0e];
      candidate.bar0_raw := LongWord(cfg[$10]) or
                            (LongWord(cfg[$11]) shl 8) or
                            (LongWord(cfg[$12]) shl 16) or
                            (LongWord(cfg[$13]) shl 24);
      flags := candidate.bar0_raw and $0f;
      if (flags and 1) <> 0 then candidate.bar0_space := 1 else candidate.bar0_space := 0;
      if ((flags shr 1) and 3) = 2 then candidate.bar0_width := 1 else candidate.bar0_width := 0;
      if (flags and 8) <> 0 then candidate.bar0_prefetch := 1 else candidate.bar0_prefetch := 0;
      if candidate.bar0_space <> 0 then
        candidate.bar0_base := candidate.bar0_raw and $fffffffc
      else
        candidate.bar0_base := candidate.bar0_raw and $fffffff0;
      candidate.cfg_bytes := CONFIG_BYTES;

      if not ParseBdf(sr.Name, candidate, foundBdf) then
      begin
        err := 'IDENTITY-FAIL step=bdf-parse code=' +
               IntToStr(STATUS_USAGE) + ' name=' + sr.Name;
        Exit(STATUS_USAGE);
      end;
      rc := ReadBinding(path, inv.driver, err);
      if rc <> STATUS_OK then
        Exit(rc);
      ReadBar0Size(path, candidate);
      inv.pci := candidate;
      Inc(inv.valid_count);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;

  if inv.candidate_count = 0 then
  begin
    err := 'IDENTITY-FAIL step=pci-no-match code=' + IntToStr(STATUS_NO_MATCH);
    Exit(STATUS_NO_MATCH);
  end;
  if inv.valid_count <> 1 then
  begin
    err := 'IDENTITY-FAIL step=card-count code=' + IntToStr(STATUS_CARD_COUNT) +
           ' count=' + IntToStr(inv.valid_count);
    Exit(STATUS_CARD_COUNT);
  end;
  if foundBdf <> LowerCase(expectBdf) then
  begin
    err := 'IDENTITY-FAIL step=bdf-mismatch code=' + IntToStr(STATUS_BDF) +
           ' expected=' + LowerCase(expectBdf) + ' got=' + foundBdf;
    Exit(STATUS_BDF);
  end;
  for rc := 1 to Length(foundBdf) do
    inv.bdf[rc - 1] := foundBdf[rc];
  Result := STATUS_OK;
end;

end.
