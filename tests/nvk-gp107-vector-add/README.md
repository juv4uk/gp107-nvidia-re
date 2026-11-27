# NVK GP107 vector-add smoke test

This test is a deliberately small **real Vulkan compute dispatch** for the
owner's NVIDIA GeForce GTX 1050 Ti (Pascal GP107, PCI `10de:1c82`).
It is not a graphics benchmark and does not treat `vkcube` as compute
evidence.

## What it proves

When it exits with code 0, the run has:

1. selected a physical device with vendor/device IDs `10de:1c82`;
2. matched its PCI domain:bus:device.function against the caller-supplied BDF
   using `VK_EXT_pci_bus_info`;
3. verified `VK_DRIVER_ID_MESA_NVK` via
   `VkPhysicalDeviceDriverProperties`;
4. found a queue family advertising `VK_QUEUE_COMPUTE_BIT`;
5. built a compute pipeline from the supplied SPIR-V and submitted
   `vkCmdDispatch`;
6. waited for a fence, invalidated non-coherent mapped memory when needed,
   and checked every output element plus an independent CPU checksum.

It reports the physical device API version returned by the driver and
supports two required sizes: 257 elements (to exercise the final partial
workgroup) and 1,048,576 elements (a larger dispatch/buffer case). The
expected Vulkan API version is intentionally **not hard-coded**: the current
NVK documentation headline and older per-device source snapshots have used
different scopes, so the physical device's actual `apiVersion` is the runtime
witness.

## Build

Requirements on the native Linux test boot:

- Vulkan headers and loader development package;
- Mesa NVK driver;
- `glslangValidator` (GLSL to SPIR-V);
- C11 compiler.

Example on Debian/Kali-derived systems (package names may vary by release):

```sh
sudo apt install build-essential libvulkan-dev glslang-tools vulkan-tools
glslangValidator -V --target-env vulkan1.1 -o vector_add.spv vector_add.comp
spirv-val --target-env vulkan1.1 vector_add.spv
spirv-dis vector_add.spv -o vector_add.spvasm
cc -std=c11 -O2 -Wall -Wextra -Wpedantic \
  -o nvk-vector-add nvk-vector-add.c -lvulkan
sha256sum vector_add.comp vector_add.spv vector_add.spvasm nvk-vector-add
```

Do not install, replace, or remove the working proprietary NVIDIA driver as
part of this build. Build on a separate native-Linux environment or a
rollback-capable test boot. WSL is suitable for source/build checks only, not
for claiming a native Nouveau hardware result.

## Run: identify the BDF dynamically

First discover the actual PCI address; never copy a BDF from this example:

```sh
lspci -Dnn -d 10de:1c82
```

Set the exact returned address, for example `0000:01:00.0`, then constrain
Mesa's Vulkan device enumeration to that PCI device:

```sh
BDF=0000:01:00.0
DRI_PRIME_DEBUG=1 DRI_PRIME="pci-$BDF!" \
  ./nvk-vector-add --bdf "$BDF" --elements 257 --spv vector_add.spv

DRI_PRIME_DEBUG=1 DRI_PRIME="pci-$BDF!" \
  ./nvk-vector-add --bdf "$BDF" --elements 1048576 --spv vector_add.spv
```

The example BDF is illustrative only. The executable independently checks
the PCI address through Vulkan; it fails closed if the PCI-bus or driver
properties are unavailable, the BDF differs, another matching GP107 is
ambiguous, or the driver is not Mesa NVK.

## Evidence bundle

Save together:

- exact command and exit code;
- stdout and stderr;
- `uname -a`, distribution release, `cat /proc/cmdline`;
- `lspci -Dnnk -s "$BDF"` and `lspci -Dvv -s "$BDF"`;
- `vulkaninfo --summary`;
- kernel journal for the same boot:
  `sudo journalctl -b -k -o short-monotonic --no-pager`;
- SHA-256 of `nvk-vector-add.c`, `vector_add.comp`, generated SPIR-V,
  and executable;
- exact kernel package/source revision and Mesa package/source revision.

Example capture:

```sh
set -o pipefail
BDF="$(lspci -Dnn -d 10de:1c82 | awk 'NR==1 {print $1}')"
test -n "$BDF" || { echo "GP107_NOT_FOUND"; exit 2; }

for N in 257 1048576; do
  DRI_PRIME_DEBUG=1 DRI_PRIME="pci-$BDF!" \
    ./nvk-vector-add --bdf "$BDF" --elements "$N" --spv vector_add.spv \
    2>&1 | tee "nvk-vector-add-$BDF-$N.log"
  rc=${PIPESTATUS[0]}
  printf 'EXIT_STATUS=%s\n' "$rc" | tee -a "nvk-vector-add-$BDF-$N.log"
  test "$rc" -eq 0 || exit "$rc"
done
```

## Failure classification

- `GP107_NOT_FOUND` / `GP107_AMBIGUOUS`: selection failure; no compute
  result.
- `PCI_IDENTITY_UNAVAILABLE` / `PCI_BDF_MISMATCH`: no proof that the
  tested Vulkan device is the physical target.
- `NVK_DRIVER_MISMATCH`: not an NVK acceptance run.
- `COMPUTE_QUEUE_NOT_FOUND`: no usable compute queue was exposed.
- Run both `--elements 257` (tail/bounds coverage) and
  `--elements 1048576` (larger buffer/dispatch coverage); retain their
  logs separately.
- If normal enumeration does not expose GP107, a separate diagnostic
  enumeration-only check may use
  `NVK_I_WANT_A_BROKEN_VULKAN_DRIVER=1 DRI_PRIME="pci-$BDF!" vulkaninfo --summary`.
  Do not run this compute harness under that override: the override result is
  `EXPERIMENTAL_ENUMERATION_ONLY`, not supported/working acceptance.
- pipeline, submit, fence, invalidate, or checksum failures are separate
  failure stages and must retain their raw error output.
- `NVK_GP107_VECTOR_ADD_PASS` means this one simple shader completed on the
  exact selected device. It does not prove general Vulkan conformance,
  graphics stability, Rusticl/OpenCL, video decode/encode, reclocking, or
  performance.

Current evidence state: `PHYSICAL_GPU_TEST=NOT_RUN`. Source/build validation
does not change this label. The GitHub Actions workflow added with this test
will compile and validate GLSL/SPIR-V and link the C harness without invoking
the executable or requiring a GPU.

Expected executable exit codes: `0` = exact-GP107 NVK vector-add PASS;
`2` = preflight/device/Vulkan-stage failure (inspect the emitted stage);
`3` = output or CPU checksum mismatch.

Do not run this before the separate read-only GPU passport, a native Nouveau
boot with rollback, and verification that the kernel package includes the
required GP107 atomic-KMS fix. Also do not run it until issue #18 has closed
the conditional FIFO/non-stall safety review or explicitly authorized a
controlled diagnostic boot. Never run it while the proprietary NVIDIA KMD
owns this GPU. No MMIO/register poking, firmware flashing, manual reset, or
custom devinit/Falcon scripts are part of this test.
