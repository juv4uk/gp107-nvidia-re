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
expected Vulkan API version is intentionally **not hard-coded**. It is pinned
to the exact upstream release tag `upstream-mesa-26.3.1`, commit
`fec8830e9c94b1d67f3d8469467d5529fb2978cd`, tarball SHA-256
`4e4e438eac7b840a9383988cbb7c08dad8041da544b9319fc26d319fa7348961`.
In that source, `nvk_get_vk_version()` returns 1.3 for
`MAXWELL_A <= cls_eng3d < TURING_A`, including Pascal/GP107, because
`hostImageCopy` is Turing+ only. It also enables `VK_EXT_pci_bus_info`
for discrete GPUs. Mesa 26.3.1's generic release headline is Vulkan 1.4, but
the release notes say the reported per-device `apiVersion` depends on the
driver. We therefore print the actual device value rather than substituting
the release headline for a hardware witness.

[Upstream Mesa tag](https://android.googlesource.com/platform/external/mesa3d/+/refs/tags/upstream-mesa-26.3.1) ·
[version source](https://android.googlesource.com/platform/external/mesa3d/+/refs/tags/upstream-mesa-26.3.1/src/nouveau/vulkan/nvk_physical_device.c) ·
[release notes](https://docs.mesa3d.org/relnotes/26.3.1.html)

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
# These flags explicitly opt into two different side-effect boundaries.
# Do not add them until the corresponding owner approvals and issue #18 gates
# have been completed.
# Enumeration-only witness: requires explicit owner approval; no queue/workload.
DRI_PRIME_DEBUG=1 DRI_PRIME="pci-$BDF!" \
  ./nvk-vector-add --bdf "$BDF" --allow-temp-gr-channel-init \
  --enumeration-only

# Compute acceptance: separate approval after issue #18 gates.
DRI_PRIME_DEBUG=1 DRI_PRIME="pci-$BDF!" \
  ./nvk-vector-add --bdf "$BDF" --allow-temp-gr-channel-init \
  --allow-gpu-submit --elements 257 --spv vector_add.spv

DRI_PRIME_DEBUG=1 DRI_PRIME="pci-$BDF!" \
  ./nvk-vector-add --bdf "$BDF" --allow-temp-gr-channel-init \
  --allow-gpu-submit --elements 1048576 --spv vector_add.spv
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
- Do not run a separate `vulkaninfo --summary` for evidence; the approved
  enumeration-only mode already performs device discovery and an additional
  invocation would create another temporary GR channel.
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
    ./nvk-vector-add --bdf "$BDF" --allow-temp-gr-channel-init \
      --allow-gpu-submit --elements "$N" --spv vector_add.spv \
    2>&1 | tee "nvk-vector-add-$BDF-$N.log"
  rc=${PIPESTATUS[0]}
  printf 'EXIT_STATUS=%s\n' "$rc" | tee -a "nvk-vector-add-$BDF-$N.log"
  test "$rc" -eq 0 || exit "$rc"
done
```

## Fail-closed execution gates

The executable defaults to **no Vulkan instance creation and no physical-device enumeration**. There are two separately acknowledged modes:

- `--allow-temp-gr-channel-init` is required for any NVK discovery. It acknowledges that physical-device enumeration may open the Nouveau render node read/write, initialize VM/NVIF state, and allocate/free a temporary GR channel and subchannel objects.
- `--enumeration-only` selects a limited witness. With the first flag, it enumerates the exact GP107 and verifies PCI/BDF plus Mesa NVK driver identity, then destroys the Vulkan instance and exits. It does not create a `VkDevice`, queue, fence, or submit a GPFIFO workload. This is still **not read-only** because discovery has the channel/VM/NVIF effects above.
- `--allow-gpu-submit` is required for compute mode and acknowledges continuing beyond enumeration to Vulkan device/queue creation and an actual compute submit/readback. It cannot be combined with `--enumeration-only`.

Without the applicable explicit flags, the process prints `ENUMERATION_NOT_AUTHORIZED`, states that no Vulkan instance or physical device was enumerated, and exits with code 4 before Vulkan instance creation. This guard is not a substitute for separate owner approval, issue #18 evidence gates, exact kernel/Mesa provenance, or a rollback plan. **Do not pass either acknowledgement flag now.**

The exact upstream Mesa source pin is `upstream-mesa-26.3.1` (commit `fec8830e9c94b1d67f3d8469467d5529fb2978cd`, tarball SHA-256 `4e4e438eac7b840a9383988cbb7c08dad8041da544b9319fc26d319fa7348961`). The source audit in [issue #18](https://github.com/juv4uk/gp107-nvidia-re/issues/18#issuecomment-7209842238) establishes the discovery and queue-init boundaries.

On this release, physical-device discovery calls `nvkmd_nouveau_try_create_pdev()` → `nouveau_ws_device_new()`. It opens the render node with `O_RDWR`, initializes VM/NVIF state, creates a temporary `NOUVEAU_FIFO_ENGINE_GR` context, queries engine classes, and destroys that context. Kernel channel setup allows a separate KILLED event; this is not the FIFO NONSTALL event. The `NON_STALL_INTR` object is created without ALLOW and remains `allowed=0`. There is no Mesa `DRM_NOUVEAU_EXEC` on this discovery path.

Device/queue creation is a different boundary: on the same exact Mesa 26.3.1 tag, NVK queue initialization builds initial engine state and reaches `nvk_queue_push()` / exec. It is therefore not a no-submit probe.

## Enumeration is not strictly read-only

We checked the exact versioned Debian Mesa `26.3.1-1` source snapshot (Debian experimental), not the older May `mirror/mesa` snapshot:
- [`nvkmd_nouveau_pdev.c`](https://sources.debian.org/src/mesa/26.3.1-1/src/nouveau/vulkan/nvkmd/nouveau/nvkmd_nouveau_pdev.c) calls `nouveau_ws_device_new()` during NVK physical-device discovery.
- [`nouveau_device.c`](https://sources.debian.org/src/mesa/26.3.1-1/src/nouveau/winsys/nouveau_device.c) creates a temporary `nouveau_ws_context_create(device, NOUVEAU_WS_ALL_3D_ENGINES, ...)` to query engine classes and destroys it after copying the class IDs.
- [`nouveau_context.c`](https://sources.debian.org/src/mesa/26.3.1-1/src/nouveau/winsys/nouveau_context.c) implements that 3D context through `DRM_NOUVEAU_CHANNEL_ALLOC` with `NOUVEAU_FIFO_ENGINE_GR`, then creates its subchannel objects; context destruction frees subchannels and the channel.
- Kernel channel initialization creates the Pascal `NON_STALL_INTR` event object through `nvif_event_ctor()` and `nvkm_uchan_uevent()`, but `nvkm_event_ntfy_add()` leaves it `allowed=0`; this does **not** enter the non-stall `nvkm_event_get/put` reference-count path.

Thus NVK enumeration can allocate and free a temporary GR channel and associated objects, without a GPFIFO workload submission on this exact discovery path. This is **not zero-side-effect** and is not a strictly read-only query. Treat `vulkaninfo --summary` with NVK selected as `ENUMERATION_WITH_TEMP_GR_CHANNEL_INIT`; do not run it until the target Mesa source/package has been checked and the owner has approved a controlled native Nouveau boot.

Do not use `vkCreateDevice`/compute queue creation as a no-submit substitute. In this exact 26.3.1 source, [`nvk_queue_create()`](https://sources.debian.org/src/mesa/26.3.1-1/src/nouveau/vulkan/nvk_queue.c) calls `nvk_queue_init_context_state()`, which builds draw/dispatch state and ends in `nvk_queue_push()`; `nvk_device.c` calls `nvk_queue_create()` for each requested device queue. This submits initial engine state. Do not create a Vulkan queue, wait on a fence, or dispatch a shader for the first channel witness.

Even if the enumeration callback is observed, record it only as `NONSTALL_EVENT_OBJECT_CREATED` with `allowed=0`. It does not prove `NONSTALL_EVENT_ENABLE` or an access to `nvkm_event_get/put`; those are separate states and must not be deliberately triggered at this stage.
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
- Do **not** use `vulkaninfo --summary`, `vkEnumeratePhysicalDevices`,
  or the `NVK_I_WANT_A_BROKEN_VULKAN_DRIVER=1` override as a passive
  preflight before owner approval. On Mesa 26.3.1-1, physical-device
  enumeration can allocate and free a temporary GR channel and create a
  `NON_STALL_INTR` event object (`allowed=0`); see
  [Enumeration is not strictly read-only](#enumeration-is-not-strictly-read-only).
  Any future enumeration-only run must be a separately approved,
  rollback-capable native Nouveau experiment with exact kernel/Mesa package
  provenance and capture. It is not part of this build-only acceptance.
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
