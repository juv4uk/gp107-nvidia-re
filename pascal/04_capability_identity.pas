program capability_identity;

{ G4 research slice: перетворити вже здобутий gate-лог у research-контракт
  capability identity для відкритого драйвера лісп-машини.

  Межа: Pascal обчислює факти й відмовляє названим кодом, але не задає
  жодної мовної семантики й не є ABI-авторитетом. SENS/CML/wsm-os-lisp тут
  не змінюються. Джерело — власний pascal-probe gate; нові MMIO-читання чи
  RM-запити цим зондом не виконуються. }

{$mode objfpc}{$H+}{$codepage utf8}

uses
  SysUtils, Classes;

const
  EXPECTED_ID  = '10DE:1C82';
  EXPECTED_BDF = '0000:01:00.0';

var
  Lines: TStringList;

procedure Bad(const step: string; code: Integer);
begin
  WriteLn(StdErr, 'IDENTITY-FAIL step=', step, ' code=', code);
  Halt(code);
end;

function FindLine(const needle: string): string;
var
  i: Integer;
begin
  for i := 0 to Lines.Count - 1 do
    if Pos(needle, Lines[i]) > 0 then
      Exit(Lines[i]);
  Bad('missing-line:' + needle, 10);
  Result := '';
end;

function TokenAfter(const s, key: string): string;
var
  p, q: Integer;
begin
  p := Pos(key, s);
  if p = 0 then
    Bad('missing-key:' + key, 11);
  q := p + Length(key);
  while (q <= Length(s)) and (s[q] <= ' ') do
    Inc(q);
  p := q;
  while (q <= Length(s)) and (s[q] > ' ') and (s[q] <> ',') do
    Inc(q);
  Result := Copy(s, p, q - p);
  if Result = '' then
    Bad('empty-key:' + key, 11);
end;

function BeforePlus(const s: string): string;
var
  p: Integer;
begin
  p := Pos('+', s);
  if p > 0 then
    Result := Copy(s, 1, p - 1)
  else
    Result := s;
end;

function CountGpuLines(out first: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  first := '';
  for i := 0 to Lines.Count - 1 do
    if Pos('NV_ESC_CARD_INFO   : GPU ', Lines[i]) > 0 then
    begin
      Inc(Result);
      if first = '' then
        first := Lines[i];
    end;
end;

procedure RejectAmbiguous;
var
  i: Integer;
begin
  for i := 0 to Lines.Count - 1 do
    if Pos('ambiguous valid_cards=', Lines[i]) > 0 then
      Bad('ambiguous-valid-cards', 13);
end;

procedure Run(const logPath: string);
var
  pciLine, rmLine, archLine, resLine, bootLine, gateLine, gpuLine: string;
  id, vendor, device, bdf, minor, gpuId: string;
  arch, impl, rev, subrev, bar0: string;
  p, cards: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(logPath);
    RejectAmbiguous;

    pciLine  := FindLine('PCI-CONFIG identity');
    rmLine   := FindLine('NV_ESC_CARD_INFO identity');
    archLine := FindLine('NV2080_CTRL_MC_GET_ARCH_INFO:');
    resLine  := FindLine('resource0 open');
    bootLine := FindLine('BOOT0: UNPROVEN');
    gateLine := FindLine('PASCAL-PROBE-GATE-OK');
    cards := CountGpuLines(gpuLine);
    if cards <> 1 then
      Bad('card-count', 12);
    if Pos('EACCES', resLine) = 0 then
      Bad('resource0-not-denied', 12);
    if (Pos('rmarch=runtime-proven', gateLine) = 0) or
       (Pos('boot0=unproven', gateLine) = 0) then
      Bad('gate-markers', 12);
    if bootLine = '' then
      Bad('boot0-marker', 12);

    id := TokenAfter(pciLine, ': ');
    if UpperCase(id) <> EXPECTED_ID then
      Bad('pci-id-mismatch', 12);
    if UpperCase(TokenAfter(rmLine, ': ')) <> EXPECTED_ID then
      Bad('rm-id-mismatch', 12);

    p := Pos(':', id);
    if p = 0 then
      Bad('bad-id-shape', 11);
    vendor := '0x' + LowerCase(Copy(id, 1, p - 1));
    device := '0x' + LowerCase(Copy(id, p + 1, MaxInt));

    bdf := TokenAfter(rmLine, '@ ');
    if bdf <> EXPECTED_BDF then
      Bad('bdf-mismatch', 12);
    minor := TokenAfter(rmLine, 'minor=');
    bar0 := LowerCase(BeforePlus(TokenAfter(pciLine, 'BAR0=')));
    gpuId := TokenAfter(gpuLine, 'gpu_id=');

    arch   := LowerCase(TokenAfter(archLine, 'arch='));
    impl   := LowerCase(TokenAfter(archLine, 'impl='));
    rev    := LowerCase(TokenAfter(archLine, 'rev='));
    subrev := LowerCase(TokenAfter(archLine, 'subrev='));

    WriteLn('((kind . wsm-open-driver-capability-identity-research)');
    WriteLn(' (authority . gp107-nvidia-re-research-not-abi)');
    WriteLn(' (abi-pin . untouched)');
    WriteLn(' (evidence-source . pascal-probe-gate-log)');
    WriteLn(' (pci-config');
    WriteLn('  (vendor . ', vendor, ')');
    WriteLn('  (device . ', device, ')');
    WriteLn('  (bdf . "', bdf, '")');
    WriteLn('  (bar0-base . ', bar0, ')');
    WriteLn('  (evidence . runtime-proven)');
    WriteLn('  (right . inventory-only)');
    WriteLn('  (mmio-right . none))');
    WriteLn(' (rm-control');
    WriteLn('  (gpu-id . ', LowerCase(gpuId), ')');
    WriteLn('  (minor . ', minor, ')');
    WriteLn('  (arch . ', arch, ') (impl . ', impl, ')');
    WriteLn('  (rev . ', rev, ') (subrev . ', subrev, ')');
    WriteLn('  (device-id . 0) (device-id-note . logical-not-pci)');
    WriteLn('  (valid-cards . 1) (evidence . runtime-proven)');
    WriteLn('  (right . identity-only)');
    WriteLn('  (mmio-right . none))');
    WriteLn(' (mmio');
    WriteLn('  (boot0 . unproven)');
    WriteLn('  (resource0-open . EACCES)');
    WriteLn('  (evidence . runtime-proven-negative)');
    WriteLn('  (provisioning . deferred-to-bare-metal-uefi)');
    WriteLn('  (right . none))');
    WriteLn(' (transitions');
    WriteLn('  ((pci-config -> rm-control) . allowed-when-single-card)');
    WriteLn('  ((rm-control -> mmio) . forbidden-on-hosted))');
    WriteLn(' (bounds');
    WriteLn('  (boot0-value . absent) (mmio-write . absent)');
    WriteLn('  (human-attestation . none))');
  finally
    Lines.Free;
  end;
end;

begin
  if ParamCount <> 1 then
    Bad('usage', 64);
  Run(ParamStr(1));
end.
