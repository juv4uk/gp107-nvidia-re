# gp107-nvidia-re

Protocol notes and clean-room probes for the NVIDIA Pascal **GP107** (GeForce GTX 1050 Ti) Linux driver ABI.

This repository documents **how user space talks to the NVIDIA kernel driver** on Pascal: device nodes, `ioctl` numbers, RM command classes, and the path from public CUDA entry points down to `/dev/nvidia*`. It is a research knowledge base with small, independently written C and Free Pascal probes — **not** a replacement CUDA runtime and **not** a dump of decompiled vendor code.

## Environment the findings were verified on

| Item | Value |
|---|---|
| GPU | `01:00.0 NVIDIA Corporation GP107 [GeForce GTX 1050 Ti] [10de:1c82]` |
| Architecture | Pascal, SM 6.1 (`sm_61`) |
| Driver | `580.196.11` (kernel module + userspace) |
| Kernel | `7.2.15+kali-amd64` |
| Distribution | Kali GNU/Linux Rolling 2026.3, glibc 2.43, GCC 16.2.0 |
| CUDA toolkit (for control tests only) | 12.6.3, `nvcc` V12.6.85 |
| REA/Ghidra | Ghidra 12.2 via REA, `libcuda.so.580.196.11` SHA-256 `20ad440390dad2c5fd06c14e518990512a8e7b31f8b6add7bb1581832fd4d331` |

> Internal RM layouts change between major driver branches. Treat every table here as valid for **R580 / GP107** unless stated otherwise.

## Repository layout

```text
README.md                     this file
LICENSE                       ВОЛЬНІСТЬ (same license as the author's other repos)
docs/
  01-cuInit-flow.md            cuInit -> RM device discovery: flow, nodes, ioctls
  02-cuMemAlloc-and-launch.md  allocation (UVM) and kernel launch (no ioctl)
  03-fpc-clean-room-probe.md   FPC 3.2.2 substrate, evidence states, toolchain pin
  ioctl-map.md                 consolidated ioctl / RM command reference
probes/
  01_min_cuinit.c              clean-room C: enumerate GPUs via /dev/nvidiactl, no libcuda
  Makefile
pascal/
  nv_abi.pas                   clean-room ioctl ABI, {$PACKRECORDS C}, compile-time SizeOf proof
  01_min_cuinit.pas            BaseUnix-only probe, static ELF
  Makefile
scripts/
  decode_ioctl.py              decode raw ioctl request numbers / strace lines
  test-pascal-probe.sh         fail-closed gate: FPC pin, firewall, runtime, static ELF
```

## Quick start

```bash
make -C probes
sudo ./probes/01_min_cuinit          # or run as a user in the `video` group
echo 0xc90046c8 | python3 scripts/decode_ioctl.py

bash scripts/test-pascal-probe.sh    # FPC 3.2.2 pin + static-ELF + runtime witness
```

## Method and verification

1. **Static**: REA/Ghidra 12.2 decompiled public exports of `libcuda.so.580.196.11`; only control flow, call graphs, constant numbers and structure layouts were recorded.
2. **Dynamic**: minimal `dlopen`/`dlsym` programs called `cuInit`, `cuMemAlloc_v2`, `cuLaunchKernel`, and `cuMemFree_v2` under `strace`, plus an `LD_PRELOAD` interposer printing RM parameter words.
3. **Cross-check**: constants resolved against the driver's public headers (`nv-ioctl-numbers.h`, `nv-ioctl.h`, `nv_escape.h`, `uvm_ioctl.h`, `ctrl2080*.h`) from the matching `580.196.11` source tree.

Nothing from step 1 is reproduced verbatim in this repository.

## Legal / scope notes

- This project is **Clean Room Design**: documentation is written from observed behaviour and published ABI facts; no Ghidra pseudocode, vendor source, or binary blobs are vendored.
- The repository's own text and code are released under the **ВОЛЬНІСТЬ** license in [LICENSE](LICENSE) — the same license the author uses in other repositories. NVIDIA driver headers were used only as a reference for numeric constants and ABI layout; they are not redistributed here.
- NVIDIA, CUDA, and GeForce are trademarks of NVIDIA Corporation. This project is not affiliated with or endorsed by NVIDIA.

## Non-goals

- No reimplementation of the Resource Manager, UVM, or the CUDA driver API.
- No support for architectures other than Pascal GP107 (though most escape numbers are shared across branches).
- No bypassing of driver security, signing, or access controls.
