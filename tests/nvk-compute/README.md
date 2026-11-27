# GP107 NVK SPIR-V compute witness

This is a minimal Vulkan compute acceptance harness for the exact NVIDIA
GP107 / GeForce GTX 1050 Ti (`10de:1c82`). It does **not** treat `vkcube`,
Vulkan enumeration, or a CPU fallback as a compute result.

## Scope and safety

- The harness enumerates PCI devices through sysfs and requires exactly one
  `10de:1c82` device.
- It then matches the exact sysfs BDF against `VK_EXT_pci_bus_info` and
  requires `VK_DRIVER_ID_MESA_NVK` and Vulkan API 1.3. It fails closed if
  another GPU (Intel HD 530, llvmpipe, another NVIDIA card) is selected.
- It dispatches only a simple unsigned-integer vector-add SPIR-V shader.
- It does not access BAR/MMIO, write firmware, flash VBIOS, or use NVIDIA
  proprietary CUDA APIs.
- Build and SPIR-V validation are **not** physical GPU runtime evidence.
  The result is `NOT_RUN / UNPROVEN` until it executes on the actual
  `10de:1c82` under Nouveau/NVK and the complete log is retained.

## Build dependencies

On a Debian-like native Linux installation:

```sh
sudo apt install build-essential cmake libvulkan-dev glslang-tools spirv-tools pciutils
cmake -S tests/nvk-compute -B build/nvk-compute -DCMAKE_BUILD_TYPE=Release
cmake --build build/nvk-compute --parallel
ctest --test-dir build/nvk-compute --output-on-failure
```

The project creates and validates `vector_add.spv` for Vulkan 1.2. The
executable requires a Vulkan 1.3 device API from NVK on GP107.

## Hardware gate

First resolve the exact BDF and check which kernel driver owns the card:

```sh
lspci -Dnnk -d 10de:1c82
BDF=$(lspci -Dnn -d 10de:1c82 | awk 'NR == 1 { print $1 }')
[ -n "$BDF" ] || { echo "GP107 not found" >&2; exit 1; }
DRI_BDF=$(printf '%s' "$BDF" | tr ':.' '__')
```

Use a native Linux boot where the GP107 is bound to Nouveau. Do not run the
harness while proprietary `nvidia.ko` owns the same GPU. The harness itself
asserts the PCI BDF against Vulkan PCI properties and refuses another GPU.

After issue #18's TOP/runlist risk has been resolved or explicitly bounded:

```sh
DRI_PRIME="pci-$DRI_BDF!" \
MESA_VK_ABORT_ON_DEVICE_LOSS=1 \
  ./build/nvk-compute/nvk-vector-add ./build/nvk-compute/vector_add.spv
```

## Workload and expected evidence

The shader uses `local_size_x = 64`, three storage buffers and a 32-bit
push-constant element count. The harness runs two cases:

- 257 elements, including a partial final workgroup;
- 1,048,576 elements.

For each case it performs host-write → compute-read synchronization,
`vkCmdDispatch`, compute-write → host-read synchronization, queue submission,
a 30-second fence wait, non-coherent invalidation when needed, and a CPU
verification of every output element plus an independent checksum.

Retain:

- `lspci -Dnnk -d 10de:1c82` and the sysfs BDF;
- `vulkaninfo --summary` plus harness output (deviceName, driverName,
  driverInfo, driverID, API version and PCI BDF);
- harness stdout/stderr and exit status;
- kernel, Mesa, LLVM, libdrm and firmware package versions;
- SPIR-V SHA-256 and `spirv-val` output;
- corresponding `journalctl -b -k` excerpt.

`NVK-COMPUTE-ALL-PASS` is only valid when this executable actually runs on the
physical PCI `10de:1c82` with `VK_DRIVER_ID_MESA_NVK`. Until then, do not
record a hardware PASS.
