unit gp107_capabilities;

{
  Machine-readable projection of what this Pascal slice may actually do.
  It is research code, not a runtime capability word and not an ABI. It never
  upgrades a sysfs inventory fact into a register right.

  Pascal counterpart of lib/gp107_capabilities.c; output is byte-identical to
  the C reference so the fail-closed gate can compare implementations.
}

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses
  gp107_identity;

function CapabilityReport(const inv: Tgp107Inventory;
                          allowMmio: LongInt): string;

implementation

uses
  SysUtils;

function CapabilityReport(const inv: Tgp107Inventory;
                          allowMmio: LongInt): string;
var
  state, reason, decode: string;
begin
  { CLI opt-in is not owner approval: physical MMIO always remains denied. }
  allowMmio := 0;
  state := 'denied';
  if inv.driver.bound <> 0 then
    reason := 'driver-bound'
  else
    reason := 'owner-authorization-required';

  if inv.pci.cfg_bytes = CONFIG_BYTES then
    decode := 'complete'
  else
    decode := 'partial';

  Result :=
    '((kind . gp107-capability-ledger)'#10 +
    ' (authority . gp107-research-not-abi)'#10 +
    ' (abi-pin . untouched)'#10 +
    ' (pci-inventory . observed) (evidence . caller-supplied-sysfs)'#10 +
    ' (bar0-decode . ' + decode + ') (evidence . statically-proven-layout)'#10 +
    ' (rm-identity . deferred) (reason . not-in-this-slice)'#10 +
    ' (mmio-read-software-gate . ' + state + ') (reason . ' + reason + ')'#10 +
    ' (owner-approval . not-inferred)'#10 +
    ' (physical-mmio . not-authorized)'#10 +
    ' (boot0 . unproven) (evidence . unproven)'#10 +
    ' (rights (write . none) (dispatch . none) (rm . none))'#10 +
    ' (summary . CAPABILITY-LEDGER-OK))'#10;
end;

end.
