program bar_identity;

{
  G0/G1 clean-room probe: PCI identity and read-only BAR0 attempt.

  Two independent sources are cross-checked before any MMIO is attempted:
    NV_ESC_CARD_INFO (/dev/nvidiactl) and PCI config space (sysfs).
  BAR0 is then opened O_RDONLY and mapped with PROT_READ|MAP_SHARED ONLY.
  No PROT_WRITE, no MAP_FIXED, no write instruction exists in this program.
  A refusal is reported only as a named state (OPEN_DENIED or MMAP_DENIED).
  The errno alone never proves who owns BAR0 or why mmap was refused, and
  BOOT0 stays explicitly UNPROVEN -- never guessed.

  Understanding questions for this fragment:
    1) Why is sysfs PCI config a second source rather than a redundant one?
    2) Why is the sysfs resource0 fd opened O_RDONLY, not O_RDWR?
    3) Why must a failed mmap be a GREEN fail-closed witness here?
    4) What does a successful read of NV_PMC_BOOT_0 prove, and what not?
    5) Why is chipset 0x137 a hypothesis until the register is read?
}

{$mode objfpc}{$H+}

uses
  SysUtils, BaseUnix, Unix, Linux, nv_abi, nv_device;

const
  { Candidate mask from the public nouveau convention (libdrm cl0080.h:
    "chipset from NV_PMC_BOOT_0"), NOT verified on this host because the
    read-only BAR0 path was refused. Kept as a hypothesis, not a fact. }
  BOOT0_CHIPSET_MASK = LongWord($fff00000);
  GP107_CHIPSET      = LongWord($137);
  MMIO_PAGE_BYTES    = 4096;

  { Named evidence states. OPEN_DENIED means mmap was NEVER called.
    MMAP_DENIED means open succeeded and the read-only mapping failed.
    Neither state establishes the cause of the refusal. }
  STATE_OPEN_DENIED  = 'OPEN_DENIED';
  STATE_MMAP_DENIED  = 'MMAP_DENIED';

var
  card:  Tnv_card_info;
  id:    Tpci_identity;
  fd:    cint;
  p:     Pointer;
  boot0: LongWord;
  chipset: LongWord;
  path:  string;
  e:     cint;

function ErrText(code: cint): string;
begin
  case code of
    13: Result := 'EACCES';
    22: Result := 'EINVAL';
    1:  Result := 'EPERM';
  else
    Result := 'errno=' + IntToStr(code);
  end;
end;

procedure FailClosed(const state, note: string);
begin
  WriteLn('BAR0-STATE: ', state);
  WriteLn('BOOT0: UNPROVEN (', note, ')');
  WriteLn('G1-FAIL-CLOSED-OK');
end;

begin
  if not ReadFirstCard(card) then
  begin
    WriteLn(StdErr, 'NV_ESC_CARD_INFO unavailable: errno=', fpgeterrno);
    Halt(2);
  end;

  WriteLn('NV_ESC_CARD_INFO identity : ',
          IntToHex(card.pci.vendor_id, 4), ':', IntToHex(card.pci.device_id, 4),
          ' @ ', DeviceBdf(card),
          ' minor=', card.minor_number,
          ' BAR0=0x', IntToHex(card.reg_address, 8),
          '+0x', IntToHex(card.reg_size, 8));

  if not ReadPciConfig(card, id) then
  begin
    WriteLn(StdErr, 'PCI config space unavailable: errno=', fpgeterrno);
    Halt(2);
  end;

  WriteLn('PCI-CONFIG identity       : ',
          IntToHex(id.vendor, 4), ':', IntToHex(id.device, 4),
          ' BAR0=0x', IntToHex(id.bar0, 8));

  if (id.vendor <> card.pci.vendor_id) or (id.device <> card.pci.device_id) or
     (id.bar0 <> LongWord(card.reg_address)) then
  begin
    WriteLn(StdErr, 'CROSS-CHECK-FAIL: pci config and NV_ESC_CARD_INFO disagree');
    Halt(2);
  end;
  WriteLn('CROSS-CHECK-OK: pci-config == NV_ESC_CARD_INFO');

  { Read-only, non-destructive attempt. Fail closed on every refusal. }
  path := DevicePath(card, PCI_RESOURCE0_PATH_FMT);
  fd := FpOpen(PChar(path), O_RDONLY or O_CLOEXEC, 0);
  if fd < 0 then
  begin
    e := fpgeterrno;
    WriteLn('resource0 open            : DENIED errno=', e, ' (', ErrText(e), ')');
    { mmap has not been executed: never report an mmap failure here. }
    FailClosed(STATE_OPEN_DENIED, 'open denied; MMIO not attempted');
    Halt(0);
  end;
  WriteLn('resource0 open            : fd=', fd, ' O_RDONLY');

  p := FpMMap(nil, MMIO_PAGE_BYTES, PROT_READ, MAP_SHARED, fd, 0);
  if p = MAP_FAILED then
  begin
    e := fpgeterrno;
    WriteLn('resource0 mmap PROT_READ|MAP_SHARED: DENIED errno=',
            e, ' (', ErrText(e), ')');
    { The errno is an observation; the reason is not directly proven. }
    WriteLn('MMAP-DENIAL-CAUSE: UNPROVEN (errno alone proves no cause)');
    FailClosed(STATE_MMAP_DENIED, 'mmap denied; register not read');
    FpClose(fd);
    Halt(0);
  end;

  boot0 := PLongWord(p)^;
  FpMunmap(p, MMIO_PAGE_BYTES);
  FpClose(fd);

  WriteLn('NV_PMC_BOOT_0             : 0x', IntToHex(boot0, 8));
  chipset := (boot0 and BOOT0_CHIPSET_MASK) shr 20;
  WriteLn('BOOT0 chipset hypothesis  : 0x', IntToHex(chipset, 3),
          ' expected=0x', IntToHex(GP107_CHIPSET, 3));
  if chipset <> GP107_CHIPSET then
  begin
    WriteLn(StdErr, 'BOOT0-CHIPSET-FAIL');
    Halt(2);
  end;
  WriteLn('G1-MMIO-IDENTITY-OK');
end.
