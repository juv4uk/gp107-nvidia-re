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

implementation

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

  { Anchor the lookup like the C readlinkat() path: open and stat the PCI
    device directory first, so a disappearing parent cannot be mistaken for
    an unbound GPU. }
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
