program rm_arch_info;

{
  G2 clean-room probe: RM architecture identity through /dev/nvidiactl.

  This is a SEPARATE channel from BOOT0/MMIO. It never maps BAR0, never
  opens resource0 and never claims a direct hardware register read.

  The GPU node is NOT hard-coded: it comes from the minor_number reported
  by NV_ESC_CARD_INFO for the unique PCI 10de:1c82 card. Ambiguity (0 or
  more than 1 match, or valid_cards <> 1 without a proven BDF <-> RM gpu_id
  mapping) is a hard failure, never a guess.

  The cuInit LD_PRELOAD trace on this host showed the required sequence:
    open /dev/nvidia<N> (must stay open), NV_ESC_SYS_PARAMS,
    NV_ESC_RM_ALLOC(NV01_ROOT_CLIENT),
    NV0000_CTRL_CMD_GPU_GET_PROBED_IDS,
    NV0000_CTRL_CMD_GPU_ATTACH_IDS,
    NV_ESC_RM_ALLOC(NV01_DEVICE_0 with NV0080_ALLOC_PARAMETERS),
    NV_ESC_RM_ALLOC(NV20_SUBDEVICE_0),
    NV2080_CTRL_CMD_MC_GET_ARCH_INFO.

  Lifecycle: RM objects are allocated under the root client. Closing the
  fds is NOT claimed here as a proven way to free every object; explicit
  NV_ESC_RM_FREE is issued in reverse creation order on every exit path,
  including a partial failure. The public NVOS00_PARAMETERS layout is
  hRoot/hObjectParent/hObjectOld/status (16 bytes).

  Optional fault injection for the gate only:
    WSM_RM_FAIL_STEP=after_alloc_client|after_alloc_device|after_alloc_subdev
  forces a named failure so the cleanup path can be observed. It is never
  set in the normal probe run.

  Understanding questions for this fragment:
    1) Why is this not evidence about NV_PMC_BOOT_0?
    2) Why does the opened /dev/nvidia<N> fd have to stay open until cleanup?
    3) What would change if device_id were the PCI device id 0x1c82?
    4) Why is a nonzero RM status a hard failure rather than a warning?
    5) Why is explicit RM_FREE not the same claim as "fd close frees all"?
}

{$mode objfpc}{$H+}

uses
  SysUtils, BaseUnix, Unix, Linux, nv_abi, nv_device, nv_rm;

const
  NV_SUCCESS = LongWord(0);
  RM_FAIL_ENV = 'WSM_RM_FAIL_STEP';

var
  ctl_fd:      cint = -1;
  gpu_fd:      cint = -1;
  card:        Tnv_card_info;
  matches:     Integer;
  valid_cards: Integer;
  gpu_path:    string;
  client:   Tnvos64;
  device:   Tnvos64;
  subdev:   Tnvos64;
  probed:   Tgpu_probed_params;
  attach:   Tgpu_attach_params;
  info2:    Tgpu_id_info_v2_params;
  devpars:  Tnv0080_alloc_params;
  subpars:  Tnv2080_alloc_params;
  arch:     Tarch_info_params;
  ctrl:     Tnvos54;
  gpu_id:   LongWord;
  i:        Integer;
  failed:   Boolean = False;
  cleanup_failed: Boolean = False;
  fail_step: string;
  injected_step: string;

procedure Die(const step: string; code: cint);
begin
  if failed then Exit;
  failed := True;
  fail_step := step;
  WriteLn(StdErr, 'RM-ARCH-FAIL step=', step, ' errno=', code);
end;

procedure DieStatus(const step: string; status: LongWord);
begin
  if failed then Exit;
  failed := True;
  fail_step := step;
  WriteLn(StdErr, 'RM-ARCH-FAIL step=', step, ' status=0x',
          IntToHex(status, 8));
end;

procedure DieInjected(const step: string);
begin
  if failed then Exit;
  failed := True;
  fail_step := step;
  WriteLn(StdErr, 'RM-ARCH-FAIL step=', step, ' injected=fail');
end;

function Inject(const step: string): Boolean;
begin
  Result := (injected_step <> '') and (injected_step = step);
end;

procedure FreeRmObject(const root_handle, parent_handle, old_handle: LongWord;
                       const label_name: string);
var
  free_pars: Tnvos00;
  e: cint;
begin
  if old_handle = 0 then Exit;
  FillChar(free_pars, SizeOf(free_pars), 0);
  free_pars.h_root := root_handle;
  free_pars.h_parent := parent_handle;
  free_pars.h_old := old_handle;
  if ctl_fd < 0 then
  begin
    WriteLn(StdErr, 'RM-FREE-FAIL object=', label_name, ' ctl fd unavailable');
    cleanup_failed := True;
    Exit;
  end;
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_FREE, SizeOf(free_pars)),
            @free_pars) < 0 then
  begin
    e := fpgeterrno;
    WriteLn(StdErr, 'RM-FREE-FAIL object=', label_name, ' errno=', e);
    cleanup_failed := True;
    Exit;
  end;
  if free_pars.status <> NV_SUCCESS then
  begin
    WriteLn(StdErr, 'RM-FREE-FAIL object=', label_name, ' status=0x',
            IntToHex(free_pars.status, 8));
    cleanup_failed := True;
    Exit;
  end;
  WriteLn('RM-FREE-OK object=', label_name, ' status=0');
end;

procedure CleanupRm;
var
  freed: Integer;
begin
  freed := 0;
  if subdev.h_new <> 0 then
  begin
    FreeRmObject(client.h_new, device.h_new, subdev.h_new, 'NV20_SUBDEVICE_0');
    Inc(freed);
    subdev.h_new := 0;
  end;
  if device.h_new <> 0 then
  begin
    FreeRmObject(client.h_new, client.h_new, device.h_new, 'NV01_DEVICE_0');
    Inc(freed);
    device.h_new := 0;
  end;
  if client.h_new <> 0 then
  begin
    FreeRmObject(client.h_new, client.h_new, client.h_new, 'NV01_ROOT_CLIENT');
    Inc(freed);
    client.h_new := 0;
  end;
  if cleanup_failed then
    WriteLn(StdErr, 'RM-CLEANUP-FAIL objects=', freed)
  else
    WriteLn('RM-CLEANUP-COMPLETE objects=', freed);
end;

procedure Run;
begin
  FillChar(client, SizeOf(client), 0);
  FillChar(device, SizeOf(device), 0);
  FillChar(subdev, SizeOf(subdev), 0);

  if not SelectTargetCard(card, matches, valid_cards) then
  begin
    WriteLn(StdErr, 'RM-ARCH-FAIL step=NV_ESC_CARD_INFO target=10de:1c82 ',
            'matches=', matches, ' valid_cards=', valid_cards);
    failed := True;
    fail_step := 'NV_ESC_CARD_INFO';
    Exit;
  end;

  { Without a proven PCI BDF <-> RM gpu_id mapping, a second valid NVIDIA
    card makes the single RM id ambiguous. Never promote it to a witness. }
  if valid_cards <> 1 then
  begin
    WriteLn(StdErr,
            'RM-ARCH-FAIL step=NV_ESC_CARD_INFO ambiguous valid_cards=',
            IntToStr(valid_cards), ' matches=', IntToStr(matches));
    failed := True;
    fail_step := 'NV_ESC_CARD_INFO';
    Exit;
  end;
  WriteLn('NV_ESC_CARD_INFO target   : ',
          IntToHex(card.pci.vendor_id, 4), ':',
          IntToHex(card.pci.device_id, 4),
          ' @ ', DeviceBdf(card),
          ' minor=', card.minor_number);

  gpu_path := GpuDevicePath(card);
  if gpu_path = '' then
  begin
    Die('GPU minor_number out of range', card.minor_number);
    Exit;
  end;
  WriteLn('GPU device node           : ', gpu_path);

  ctl_fd := FpOpen('/dev/nvidiactl', O_RDWR or O_CLOEXEC, 0);
  if ctl_fd < 0 then
  begin
    Die('open /dev/nvidiactl', fpgeterrno);
    Exit;
  end;
  gpu_fd := FpOpen(PChar(gpu_path), O_RDWR or O_CLOEXEC, 0);
  if gpu_fd < 0 then
  begin
    Die('open ' + gpu_path, fpgeterrno);
    Exit;
  end;

  FillChar(client, SizeOf(client), 0);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_ALLOC, SizeOf(client)), @client) < 0 then
  begin
    Die('alloc NV01_ROOT_CLIENT', fpgeterrno);
    Exit;
  end;
  if (client.status <> NV_SUCCESS) or (client.h_new = 0) then
  begin
    DieStatus('alloc NV01_ROOT_CLIENT', client.status);
    Exit;
  end;
  if Inject('after_alloc_client') then
  begin
    DieInjected('INJECT-after_alloc_client');
    Exit;
  end;

  FillChar(probed, SizeOf(probed), 0);
  for i := 0 to NV_MAX_PROBED_GPUS - 1 do
    probed.gpu_ids[i] := LongWord(-1);
  FillChar(ctrl, SizeOf(ctrl), 0);
  ctrl.h_client := client.h_new;
  ctrl.h_object := client.h_new;
  ctrl.cmd := NV0000_CTRL_CMD_GPU_GET_PROBED_IDS;
  ctrl.params_ptr := QWord(PtrUInt(@probed));
  ctrl.params_size := SizeOf(probed);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_CONTROL, SizeOf(ctrl)), @ctrl) < 0 then
  begin
    Die('GPU_GET_PROBED_IDS', fpgeterrno);
    Exit;
  end;
  if ctrl.status <> NV_SUCCESS then
  begin
    DieStatus('GPU_GET_PROBED_IDS', ctrl.status);
    Exit;
  end;

  gpu_id := 0;
  for i := 0 to NV_MAX_PROBED_GPUS - 1 do
    if probed.gpu_ids[i] <> LongWord(-1) then
    begin
      gpu_id := probed.gpu_ids[i];
      Break;
    end;
  if gpu_id = 0 then
  begin
    Die('GPU_GET_PROBED_IDS no valid gpu id', 0);
    Exit;
  end;

  FillChar(attach, SizeOf(attach), 0);
  for i := 0 to NV_MAX_PROBED_GPUS - 1 do
    attach.gpu_ids[i] := LongWord(-1);
  attach.gpu_ids[0] := gpu_id;
  attach.failed_id := LongWord(-1);
  FillChar(ctrl, SizeOf(ctrl), 0);
  ctrl.h_client := client.h_new;
  ctrl.h_object := client.h_new;
  ctrl.cmd := NV0000_CTRL_CMD_GPU_ATTACH_IDS;
  ctrl.params_ptr := QWord(PtrUInt(@attach));
  ctrl.params_size := SizeOf(attach);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_CONTROL, SizeOf(ctrl)), @ctrl) < 0 then
  begin
    Die('GPU_ATTACH_IDS', fpgeterrno);
    Exit;
  end;
  if ctrl.status <> NV_SUCCESS then
  begin
    DieStatus('GPU_ATTACH_IDS', ctrl.status);
    Exit;
  end;

  FillChar(info2, SizeOf(info2), 0);
  info2[0] := gpu_id;
  FillChar(ctrl, SizeOf(ctrl), 0);
  ctrl.h_client := client.h_new;
  ctrl.h_object := client.h_new;
  ctrl.cmd := NV0000_CTRL_CMD_GPU_GET_ID_INFO_V2;
  ctrl.params_ptr := QWord(PtrUInt(@info2));
  ctrl.params_size := SizeOf(info2);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_CONTROL, SizeOf(ctrl)), @ctrl) < 0 then
  begin
    Die('GPU_GET_ID_INFO_V2', fpgeterrno);
    Exit;
  end;
  if ctrl.status <> NV_SUCCESS then
  begin
    DieStatus('GPU_GET_ID_INFO_V2', ctrl.status);
    Exit;
  end;

  WriteLn('GPU_ATTACH_IDS            : gpu=0x', IntToHex(gpu_id, 3),
          ' status=0 deviceInstance=', info2[2],
          ' subDeviceInstance=', info2[3]);

  FillChar(devpars, SizeOf(devpars), 0);
  { RM device_id stays 0: this is NOT the PCI device id 0x1c82 and its
    semantics have not been independently confirmed. Do not change it. }
  devpars.device_id := 0;
  devpars.h_client_share := client.h_new;
  FillChar(device, SizeOf(device), 0);
  device.h_root := client.h_new;
  device.h_parent := client.h_new;
  device.h_class := NV01_DEVICE_0;
  device.alloc_parms_ptr := QWord(PtrUInt(@devpars));
  device.params_size := SizeOf(devpars);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_ALLOC, SizeOf(device)), @device) < 0 then
  begin
    Die('alloc NV01_DEVICE_0', fpgeterrno);
    Exit;
  end;
  if device.status <> NV_SUCCESS then
  begin
    DieStatus('alloc NV01_DEVICE_0', device.status);
    Exit;
  end;
  if Inject('after_alloc_device') then
  begin
    DieInjected('INJECT-after_alloc_device');
    Exit;
  end;

  FillChar(subpars, SizeOf(subpars), 0);
  subpars.sub_device_id := 0;
  FillChar(subdev, SizeOf(subdev), 0);
  subdev.h_root := client.h_new;
  subdev.h_parent := device.h_new;
  subdev.h_class := NV20_SUBDEVICE_0;
  subdev.alloc_parms_ptr := QWord(PtrUInt(@subpars));
  subdev.params_size := SizeOf(subpars);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_ALLOC, SizeOf(subdev)), @subdev) < 0 then
  begin
    Die('alloc NV20_SUBDEVICE_0', fpgeterrno);
    Exit;
  end;
  if subdev.status <> NV_SUCCESS then
  begin
    DieStatus('alloc NV20_SUBDEVICE_0', subdev.status);
    Exit;
  end;
  if Inject('after_alloc_subdev') then
  begin
    DieInjected('INJECT-after_alloc_subdev');
    Exit;
  end;

  FillChar(arch, SizeOf(arch), 0);
  FillChar(ctrl, SizeOf(ctrl), 0);
  ctrl.h_client := client.h_new;
  ctrl.h_object := subdev.h_new;
  ctrl.cmd := NV2080_CTRL_CMD_MC_GET_ARCH_INFO;
  ctrl.params_ptr := QWord(PtrUInt(@arch));
  ctrl.params_size := SizeOf(arch);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_CONTROL, SizeOf(ctrl)), @ctrl) < 0 then
  begin
    Die('MC_GET_ARCH_INFO', fpgeterrno);
    Exit;
  end;
  if ctrl.status <> NV_SUCCESS then
  begin
    DieStatus('MC_GET_ARCH_INFO', ctrl.status);
    Exit;
  end;

  WriteLn('NV2080_CTRL_MC_GET_ARCH_INFO: arch=0x',
          IntToHex(arch.architecture, 8),
          ' impl=0x', IntToHex(arch.impl, 8),
          ' rev=0x', IntToHex(arch.revision, 8),
          ' subrev=0x', IntToHex(arch.sub_revision, 2));
  WriteLn('BOOT0: UNPROVEN (RM arch info is a separate channel)');
  WriteLn('RM-ARCH-OK');
end;

begin
  injected_step := GetEnvironmentVariable(RM_FAIL_ENV);
  Run;
  CleanupRm;
  if ctl_fd >= 0 then FpClose(ctl_fd);
  if gpu_fd >= 0 then FpClose(gpu_fd);
  if cleanup_failed and (not failed) then
  begin
    failed := True;
    fail_step := 'NV_ESC_RM_FREE';
    WriteLn(StdErr, 'RM-ARCH-FAIL step=NV_ESC_RM_FREE cleanup=fail');
  end;
  if failed then Halt(2);
end.
