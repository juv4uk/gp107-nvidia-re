unit gp107_mmio;

{
  Fail-closed Pascal API for the GP107 research profile.

  The unit intentionally has no resource0 open, mmap, pointer dereference or
  inline assembly path. --allow-mmio is a CLI flag, not owner authorization.
  The public API remains for C/Pascal CLI parity and always denies physical
  MMIO until a separate owner decision and independent review.
}

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses
  SysUtils;

function Read32(const sysfsRoot, expectBdf: string; allow: LongInt;
                offset: LongWord; out value: LongWord;
                out err: string): LongInt;

implementation

uses
  gp107_identity;

function Read32(const sysfsRoot, expectBdf: string; allow: LongInt;
                offset: LongWord; out value: LongWord;
                out err: string): LongInt;
begin
  value := 0;
  err := '';

  if (sysfsRoot = '') or (expectBdf = '') then
  begin
    err := 'MMIO-FAIL step=bad-argument code=' + IntToStr(STATUS_USAGE);
    Exit(STATUS_USAGE);
  end;

  { Neither the flag nor an inventory snapshot grants physical device access. }
  if allow < 0 then
    allow := 0;
  if offset > High(LongWord) then
    offset := 0;

  err := 'MMIO-FAIL step=owner-authorization-required code=' +
         IntToStr(STATUS_NOT_AUTHORIZED);
  Result := STATUS_NOT_AUTHORIZED;
end;

end.
