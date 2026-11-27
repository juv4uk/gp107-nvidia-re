# GP107 Vulkan compute smoke test

This is a minimal correctness witness, not a benchmark and not a generic
Vulkan conformance suite. It uses a conservative SPIR-V compute shader
(integer vector addition; no subgroup operations, images, fp16, atomics, or
optional shader extensions).

## What a PASS means

The program reports GP107-VK-COMPUTE-PASS only after all of the following:

1. It finds PCI vendor/device 10de:1c82 at the exact BDF supplied by the
   wrapper, using VK_EXT_pci_bus_info.
2. Vulkan reports a driver name containing NVK or Nouveau.
3. The physical device advertises Vulkan API 1.3 or newer.
4. It finds a queue family with VK_QUEUE_COMPUTE_BIT.
5. It creates a compute pipeline, submits vkCmdDispatch, waits for a fence,
   reads the output buffer back on the CPU, and verifies every element.
6. It reports a deterministic checksum for the verified output.

A graphics-only run of vkcube, vkmark, or glmark2 is not a compute PASS.
A vendor NVIDIA Vulkan driver is not an NVK PASS. A run on Intel HD 530 or
llvmpipe is not a GP107 PASS.

Exit status 77 means the test could not be performed because a required
capability/tool/device was unavailable. Exit status 1 means an actual test
or Vulkan operation failed. Do not turn either into a PASS.

## Build dependencies

On Debian/Ubuntu-like systems, the usual packages are:

    sudo apt install build-essential libvulkan-dev glslc pciutils

If glslc is unavailable, install glslang-tools; the Makefile has a
glslangValidator fallback. A Vulkan loader/ICD and Mesa NVK build are
required at runtime. Package names differ by distribution.

Build without changing the system graphics driver:

    make

## Run

Run this only from a native Linux test boot where Nouveau is bound to the
physical GTX 1050 Ti. Do not use the ordinary WSL GPU-PV path as a Nouveau
witness. Keep a known-good boot entry and rollback path.

    uname -a
    cat /etc/os-release
    lspci -Dnnk -d 10de:1c82
    modinfo -F version nouveau
    vulkaninfo --summary
    make run

run-gp107.sh requires exactly one 10de:1c82 device, derives its BDF
dynamically, sets Mesa DRI_PRIME=pci-<BDF>!, and exports
GP107_EXPECTED_BDF. The C harness checks the PCI BDF again through
VK_EXT_pci_bus_info; it does not trust device ordering or the device name.

Record a fresh evidence bundle for every run:

    date -u --iso-8601=seconds
    uname -a
    cat /etc/os-release
    cat /proc/cmdline
    lspci -Dnnk -d 10de:1c82
    modinfo -F version nouveau
    journalctl -b -k --no-pager -o short-monotonic
    make run
    printf 'exit=%s\n' "$?"

Save stdout, stderr, exit code, Mesa/kernel/libdrm/LLVM/firmware package
versions, BDF, and the full kernel log. VK_EXT_pci_bus_info is required so
the test fails closed rather than accidentally validating the Intel GPU.

## Memory and scope

The smoke test uses a host-visible storage buffer so the CPU can initialise
and verify data. It handles non-coherent memory with flush/invalidate calls.
This does not measure device-local VRAM throughput, clocks, power management,
video encode/decode, Rusticl/OpenCL, or CUDA.

No BAR/MMIO access, firmware writes, VBIOS changes, device unbind, or reset is
performed. It does not modify the system driver configuration.

The source build has not been compiled in this ChatGPT environment because
the Vulkan development headers and shader compiler are not installed here.
A successful source review/build is not a physical GP107 runtime witness.
