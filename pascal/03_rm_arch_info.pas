program rm_arch_info;

{
  G2 clean-room probe: RM architecture identity through /dev/nvidiactl.

  This is a SEPARATE channel from BOOT0/MMIO. It never maps BAR0, never
  opens resource0 and never claims a direct hardware register read.

  The cuInit LD_PRELOAD trace on this host showed the required sequence:
    open /dev/nvidia0 (must stay open), NV_ESC_SYS_PARAMS,
    NV_ESC_RM_ALLOC(NV01_ROOT_CLIENT),
    NV0000_CTRL_CMD_GPU_GET_PROBED_IDS,
    NV0000_CTRL_CMD_GPU_ATTACH_IDS,
    NV_ESC_RM_ALLOC(NV01_DEVICE_0 with NV0080_ALLOC_PARAMETERS),
    NV_ESC_RM_ALLOC(NV20_SUBDEVICE_0),
    NV2080_CTRL_CMD_MC_GET_ARCH_INFO.
  Our earlier probe skipped the GPU fd and ATTACH_IDS and failed with
  NV_ERR_INSUFFICIENT_PERMISSIONS / NV_ERR_INVALID_ARGUMENT. Here we use
  the observed sequence with our own code and public ABI layouts only.

  Understanding questions for this fragment:
    1) Why is this not evidence about NV_PMC_BOOT_0?
    2) Why does the opened /dev/nvidia0 fd have to stay open until the end?
    3) What would change if device_id were the PCI device id 0x1c82?
    4) Why is a nonzero RM status a hard failure rather than a warning?
}

{$mode objfpc}{$H+}

uses
  SysUtils, BaseUnix, Unix, Linux, nv_abi, nv_device, nv_rm;

const
  NV_SUCCESS = LongWord(0);

var
  ctl_fd:   cint;
  gpu_fd:   cint;
  memblock: QWord;
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

procedure Die(const step: string; code: cint);
begin
  WriteLn(StdErr, 'RM-ARCH-FAIL step=', step, ' errno=', code);
  Halt(2);
end;

procedure DieStatus(const step: string; status: LongWord);
begin
  WriteLn(StdErr, 'RM-ARCH-FAIL step=', step, ' status=0x',
          IntToHex(status, 8));
  Halt(2);
end;

begin
  if not ReadMemBlockSize(memblock) then
    Die('read sysfs block_size_bytes', fpgeterrno);

  ctl_fd := FpOpen('/dev/nvidiactl', O_RDWR or O_CLOEXEC, 0);
  if ctl_fd < 0 then Die('open /dev/nvidiactl', fpgeterrno);
  gpu_fd := FpOpen('/dev/nvidia0', O_RDWR or O_CLOEXEC, 0);
  if gpu_fd < 0 then Die('open /dev/nvidia0', fpgeterrno);

  { Set-once driver parameter; same value as the cuInit probe, so it is
    idempotent here. A different cached value would be a real failure. }
  if FpIOCtl(ctl_fd, NV_IOC_SYS_PARAMS, @memblock) < 0 then
    Die('NV_ESC_SYS_PARAMS', fpgeterrno);

  FillChar(client, SizeOf(client), 0);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_ALLOC, SizeOf(client)), @client) < 0 then
    Die('alloc NV01_ROOT_CLIENT', fpgeterrno);
  if (client.status <> NV_SUCCESS) or (client.h_new = 0) then
    DieStatus('alloc NV01_ROOT_CLIENT', client.status);

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
    Die('GPU_GET_PROBED_IDS', fpgeterrno);
  if ctrl.status <> NV_SUCCESS then DieStatus('GPU_GET_PROBED_IDS', ctrl.status);

  gpu_id := 0;
  for i := 0 to NV_MAX_PROBED_GPUS - 1 do
    if probed.gpu_ids[i] <> LongWord(-1) then
    begin
      gpu_id := probed.gpu_ids[i];
      Break;
    end;
  if gpu_id = 0 then
  begin
    WriteLn(StdErr, 'RM-ARCH-FAIL step=GPU_GET_PROBED_IDS no valid gpu id');
    Halt(2);
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
    Die('GPU_ATTACH_IDS', fpgeterrno);
  if ctrl.status <> NV_SUCCESS then DieStatus('GPU_ATTACH_IDS', ctrl.status);

  FillChar(info2, SizeOf(info2), 0);
  info2[0] := gpu_id;
  FillChar(ctrl, SizeOf(ctrl), 0);
  ctrl.h_client := client.h_new;
  ctrl.h_object := client.h_new;
  ctrl.cmd := NV0000_CTRL_CMD_GPU_GET_ID_INFO_V2;
  ctrl.params_ptr := QWord(PtrUInt(@info2));
  ctrl.params_size := SizeOf(info2);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_CONTROL, SizeOf(ctrl)), @ctrl) < 0 then
    Die('GPU_GET_ID_INFO_V2', fpgeterrno);
  if ctrl.status <> NV_SUCCESS then DieStatus('GPU_GET_ID_INFO_V2', ctrl.status);

  WriteLn('GPU_ATTACH_IDS            : gpu=0x', IntToHex(gpu_id, 3),
          ' status=0 deviceInstance=', info2[2],
          ' subDeviceInstance=', info2[3]);

  FillChar(devpars, SizeOf(devpars), 0);
  devpars.device_id := 0;
  devpars.h_client_share := client.h_new;
  FillChar(device, SizeOf(device), 0);
  device.h_root := client.h_new;
  device.h_parent := client.h_new;
  device.h_class := NV01_DEVICE_0;
  device.alloc_parms_ptr := QWord(PtrUInt(@devpars));
  device.params_size := SizeOf(devpars);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_ALLOC, SizeOf(device)), @device) < 0 then
    Die('alloc NV01_DEVICE_0', fpgeterrno);
  if device.status <> NV_SUCCESS then DieStatus('alloc NV01_DEVICE_0', device.status);

  FillChar(subpars, SizeOf(subpars), 0);
  subpars.sub_device_id := 0;
  FillChar(subdev, SizeOf(subdev), 0);
  subdev.h_root := client.h_new;
  subdev.h_parent := device.h_new;
  subdev.h_class := NV20_SUBDEVICE_0;
  subdev.alloc_parms_ptr := QWord(PtrUInt(@subpars));
  subdev.params_size := SizeOf(subpars);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_ALLOC, SizeOf(subdev)), @subdev) < 0 then
    Die('alloc NV20_SUBDEVICE_0', fpgeterrno);
  if subdev.status <> NV_SUCCESS then
    DieStatus('alloc NV20_SUBDEVICE_0', subdev.status);

  FillChar(arch, SizeOf(arch), 0);
  FillChar(ctrl, SizeOf(ctrl), 0);
  ctrl.h_client := client.h_new;
  ctrl.h_object := subdev.h_new;
  ctrl.cmd := NV2080_CTRL_CMD_MC_GET_ARCH_INFO;
  ctrl.params_ptr := QWord(PtrUInt(@arch));
  ctrl.params_size := SizeOf(arch);
  if FpIOCtl(ctl_fd, RmIOC(NV_ESC_RM_CONTROL, SizeOf(ctrl)), @ctrl) < 0 then
    Die('MC_GET_ARCH_INFO', fpgeterrno);
  if ctrl.status <> NV_SUCCESS then DieStatus('MC_GET_ARCH_INFO', ctrl.status);

  WriteLn('NV2080_CTRL_MC_GET_ARCH_INFO: arch=0x',
          IntToHex(arch.architecture, 8),
          ' impl=0x', IntToHex(arch.impl, 8),
          ' rev=0x', IntToHex(arch.revision, 8),
          ' subrev=0x', IntToHex(arch.sub_revision, 2));
  WriteLn('BOOT0: UNPROVEN (RM arch info is a separate channel)');
  WriteLn('RM-ARCH-OK');

  FpClose(ctl_fd);
  FpClose(gpu_fd);
end.
