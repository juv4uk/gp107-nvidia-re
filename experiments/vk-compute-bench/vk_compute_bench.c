/* Clean-room Vulkan compute benchmark for the same GP107 board under two ICDs.
 *
 * Driver-agnostic by design: it asserts the physical board by sysfs BDF
 * (10de:1c82 @ 0000:01:00.0) AND by VK_EXT_pci_bus_info, then RECORDS
 * whichever Vulkan driver answers — NVK or NVIDIA proprietary — instead of
 * filtering one of them out. No vendor headers, no vendor code, no PR #21
 * executable, no MMIO access. Timing is submit + fence wait only: no readback
 * inside the timed loop; correctness is checked before AND after the loop.
 */
#define _POSIX_C_SOURCE 200809L
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include <libgen.h>
#include "vk_min.h"
#include "shader.spv.h"

#define LOCAL_SIZE 64u
#define MAX_CASES 4
#define MAX_ITERS 512

typedef struct { uint32_t elements, warmup, iters; } Case;

static void fail(const char *step, const char *detail) {
    fprintf(stderr, "BENCH-FAIL step=%s detail=%s\n", step, detail ? detail : "-");
    exit(2);
}
static void vkfail(const char *step, VkResult r) {
    fprintf(stderr, "BENCH-FAIL step=%s vkResult=%d\n", step, (int)r);
    exit(2);
}
static uint32_t a_val(uint32_t i) { return i * 3u + 1u; }
static uint32_t b_val(uint32_t i) { return i * 5u + 7u; }
static uint32_t fnv1a(const unsigned char *p, size_t n) {
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 16777619u; }
    return h;
}
static double ns_now(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC_RAW, &ts) != 0) fail("clock", "monotonic-raw");
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}
static int cmp_double(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x < y) ? -1 : (x > y) ? 1 : 0;
}

static void parse_bdf(uint32_t *domain, uint32_t *bus, uint32_t *device,
                      uint32_t *function) {
    const char *bdf = getenv("BENCH_BDF");
    if (!bdf) bdf = "0000:01:00.0";
    if (sscanf(bdf, "%8x:%4x:%4x.%4x", domain, bus, device, function) != 4)
        fail("bdf-parse", bdf);
}

static void board_identity(char *binding, size_t cap) {
    const char *bdf = getenv("BENCH_BDF");
    if (!bdf) bdf = "0000:01:00.0";
    char path[256], buf[128];
    FILE *f;
    snprintf(path, sizeof path, "/sys/bus/pci/devices/%s/vendor", bdf);
    f = fopen(path, "r"); if (!f) fail("bdf-vendor", "sysfs unreadable");
    if (!fgets(buf, sizeof buf, f)) fail("bdf-vendor", "empty");
    fclose(f);
    if (strncmp(buf, "0x10de", 6) != 0) fail("bdf-vendor", buf);
    snprintf(path, sizeof path, "/sys/bus/pci/devices/%s/device", bdf);
    f = fopen(path, "r"); if (!f) fail("bdf-device", "sysfs unreadable");
    if (!fgets(buf, sizeof buf, f)) fail("bdf-device", "empty");
    fclose(f);
    if (strncmp(buf, "0x1c82", 6) != 0) fail("bdf-device", buf);
    snprintf(path, sizeof path, "/sys/bus/pci/devices/%s/driver", bdf);
    char link[256] = {0};
    ssize_t n = readlink(path, link, sizeof link - 1);
    if (n <= 0) fail("bdf-binding", "not bound");
    link[n] = 0;
    snprintf(binding, cap, "%s", basename(link));
    printf("BENCH-BOARD-OK bdf=%s vendor=0x10de device=0x1c82 binding=%s\n", bdf, binding);
}

#define LOAD(dst, name, inst) do {                                      \
    (dst) = (PFN_##name)gipa((inst), #name);                            \
    if (!(dst)) fail("dlsym", #name);                                   \
} while (0)

static VkResult make_buffer(
        PFN_vkCreateBuffer createBuffer,
        PFN_vkGetBufferMemoryRequirements getReqs,
        PFN_vkAllocateMemory allocateMemory,
        PFN_vkBindBufferMemory bindBufferMemory,
        PFN_vkMapMemory mapMemory,
        VkDevice dev, uint32_t memType, VkDeviceSize size,
        VkBuffer *buf, VkDeviceMemory *mem, void **ptr) {
    VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, NULL, 0,
        size, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_SHARING_MODE_EXCLUSIVE, 0, NULL };
    VkResult r = createBuffer(dev, &bci, NULL, buf);
    if (r != VK_SUCCESS) return r;
    VkMemoryRequirements req = {0};
    getReqs(dev, *buf, &req);
    VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, NULL,
        req.size, memType };
    r = allocateMemory(dev, &mai, NULL, mem);
    if (r != VK_SUCCESS) return r;
    r = bindBufferMemory(dev, *buf, *mem, 0);
    if (r != VK_SUCCESS) return r;
    return mapMemory(dev, *mem, 0, size, 0, ptr);
}

int main(void) {
    char binding[128] = "unknown";
    board_identity(binding, sizeof binding);

    void *lib = dlopen("libvulkan.so.1", RTLD_NOW);
    if (!lib) fail("dlopen", dlerror());
    PFN_vkGetInstanceProcAddr gipa = dlsym(lib, "vkGetInstanceProcAddr");
    if (!gipa) fail("dlsym", "vkGetInstanceProcAddr");

    PFN_vkCreateInstance createInstance;
    PFN_vkEnumeratePhysicalDevices enumerateDevices;
    PFN_vkGetPhysicalDeviceProperties2 getProps2;
    PFN_vkGetPhysicalDeviceMemoryProperties getMemProps;
    PFN_vkGetPhysicalDeviceQueueFamilyProperties getQueueFamilies;
    PFN_vkCreateDevice createDevice;
    PFN_vkGetDeviceQueue getDeviceQueue;
    PFN_vkCreateBuffer createBuffer;
    PFN_vkGetBufferMemoryRequirements getReqs;
    PFN_vkAllocateMemory allocateMemory;
    PFN_vkBindBufferMemory bindMemory;
    PFN_vkMapMemory mapMemory;
    PFN_vkUnmapMemory unmapMemory;
    PFN_vkDestroyBuffer destroyBuffer;
    PFN_vkFreeMemory freeMemory;
    PFN_vkCreateDescriptorSetLayout createSetLayout;
    PFN_vkCreatePipelineLayout createPipelineLayout;
    PFN_vkCreateShaderModule createShaderModule;
    PFN_vkCreateComputePipelines createComputePipelines;
    PFN_vkCreateDescriptorPool createDescriptorPool;
    PFN_vkAllocateDescriptorSets allocateDescriptorSets;
    PFN_vkUpdateDescriptorSets updateDescriptorSets;
    PFN_vkCreateCommandPool createCommandPool;
    PFN_vkAllocateCommandBuffers allocateCommandBuffers;
    PFN_vkBeginCommandBuffer beginCommandBuffer;
    PFN_vkCmdBindPipeline cmdBindPipeline;
    PFN_vkCmdBindDescriptorSets cmdBindDescriptorSets;
    PFN_vkCmdDispatch cmdDispatch;
    PFN_vkEndCommandBuffer endCommandBuffer;
    PFN_vkCreateFence createFence;
    PFN_vkResetFences resetFences;
    PFN_vkQueueSubmit queueSubmit;
    PFN_vkWaitForFences waitForFences;
    PFN_vkGetFenceStatus getFenceStatus;

    LOAD(createInstance, vkCreateInstance, NULL);
    VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO, NULL,
        "wsm-cleanroom-bench", 1, "clean-room", 1, VK_API_VERSION_1_3 };
    VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, NULL,
        0, &app, 0, NULL, 0, NULL };
    VkInstance inst = NULL;
    VkResult r = createInstance(&ici, NULL, &inst);
    if (r != VK_SUCCESS) vkfail("create-instance", r);

    LOAD(enumerateDevices, vkEnumeratePhysicalDevices, inst);
    LOAD(getProps2, vkGetPhysicalDeviceProperties2, inst);
    LOAD(getMemProps, vkGetPhysicalDeviceMemoryProperties, inst);
    LOAD(getQueueFamilies, vkGetPhysicalDeviceQueueFamilyProperties, inst);
    LOAD(createDevice, vkCreateDevice, inst);
    LOAD(getDeviceQueue, vkGetDeviceQueue, inst);
    LOAD(createBuffer, vkCreateBuffer, inst);
    LOAD(getReqs, vkGetBufferMemoryRequirements, inst);
    LOAD(allocateMemory, vkAllocateMemory, inst);
    LOAD(bindMemory, vkBindBufferMemory, inst);
    LOAD(mapMemory, vkMapMemory, inst);
    LOAD(unmapMemory, vkUnmapMemory, inst);
    LOAD(destroyBuffer, vkDestroyBuffer, inst);
    LOAD(freeMemory, vkFreeMemory, inst);
    LOAD(createSetLayout, vkCreateDescriptorSetLayout, inst);
    LOAD(createPipelineLayout, vkCreatePipelineLayout, inst);
    LOAD(createShaderModule, vkCreateShaderModule, inst);
    LOAD(createComputePipelines, vkCreateComputePipelines, inst);
    LOAD(createDescriptorPool, vkCreateDescriptorPool, inst);
    LOAD(allocateDescriptorSets, vkAllocateDescriptorSets, inst);
    LOAD(updateDescriptorSets, vkUpdateDescriptorSets, inst);
    LOAD(createCommandPool, vkCreateCommandPool, inst);
    LOAD(allocateCommandBuffers, vkAllocateCommandBuffers, inst);
    LOAD(beginCommandBuffer, vkBeginCommandBuffer, inst);
    LOAD(cmdBindPipeline, vkCmdBindPipeline, inst);
    LOAD(cmdBindDescriptorSets, vkCmdBindDescriptorSets, inst);
    LOAD(cmdDispatch, vkCmdDispatch, inst);
    LOAD(endCommandBuffer, vkEndCommandBuffer, inst);
    LOAD(createFence, vkCreateFence, inst);
    LOAD(resetFences, vkResetFences, inst);
    LOAD(queueSubmit, vkQueueSubmit, inst);
    LOAD(waitForFences, vkWaitForFences, inst);
    LOAD(getFenceStatus, vkGetFenceStatus, inst);

    uint32_t ndev = 0;
    r = enumerateDevices(inst, &ndev, NULL);
    if (r != VK_SUCCESS || ndev == 0) vkfail("enumerate", r);
    VkPhysicalDevice *devices = calloc(ndev, sizeof *devices);
    if (!devices) fail("calloc", "devices");
    r = enumerateDevices(inst, &ndev, devices);
    if (r != VK_SUCCESS) vkfail("enumerate-2", r);

    uint32_t want_domain = 0, want_bus = 0, want_device = 0, want_function = 0;
    parse_bdf(&want_domain, &want_bus, &want_device, &want_function);

    VkPhysicalDevice gpu = NULL;
    VkPhysicalDeviceProperties2Min props2 = {0};
    VkPhysicalDeviceDriverProperties drv = {0};
    VkPhysicalDevicePCIBusInfoPropertiesEXT pci = {0};
    for (uint32_t i = 0; i < ndev; i++) {
        VkPhysicalDeviceProperties2Min p = {0};
        VkPhysicalDeviceDriverProperties d = {0};
        VkPhysicalDevicePCIBusInfoPropertiesEXT b = {0};
        p.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
        p.pNext = &d;
        d.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES;
        d.pNext = &b;
        b.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PCI_BUS_INFO_PROPERTIES_EXT;
        getProps2(devices[i], &p);
        if (p.properties.vendorID == 0x10de && p.properties.deviceID == 0x1c82 &&
            b.pciDomain == want_domain && b.pciBus == want_bus &&
            b.pciDevice == want_device && b.pciFunction == want_function) {
            gpu = devices[i]; props2 = p; drv = d; pci = b; break;
        }
    }
    if (!gpu) fail("pci-bdf", "no 10de:1c82 physical device at BENCH_BDF");
    printf("BENCH-PCI-RECORD bdf=%04x:%02x:%02x.%x match=yes\n",
           pci.pciDomain, pci.pciBus, pci.pciDevice, pci.pciFunction);
    printf("BENCH-DRIVER-RECORD id=%u name=%s info=%s device=%s api=0x%08x\n",
           (unsigned)drv.driverID, drv.driverName, drv.driverInfo,
           props2.properties.deviceName, props2.properties.apiVersion);
    printf("BENCH-ICD-RECORD icd=%s\n", getenv("VK_ICD_FILENAMES") ? getenv("VK_ICD_FILENAMES") : "default");

    uint32_t nq = 0;
    getQueueFamilies(gpu, &nq, NULL);
    VkQueueFamilyProperties *qs = calloc(nq, sizeof *qs);
    if (!qs) fail("calloc", "queue-families");
    getQueueFamilies(gpu, &nq, qs);
    uint32_t qfam = 0xffffffffu;
    for (uint32_t i = 0; i < nq; i++)
        if (qs[i].queueFlags & VK_QUEUE_COMPUTE_BIT) { qfam = i; break; }
    if (qfam == 0xffffffffu) fail("queue-family", "no compute queue");
    float prio = 1.0f;
    VkDeviceQueueCreateInfo dqci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        NULL, 0, qfam, 1, &prio };
    /* VK_EXT_pci_bus_info is a DEVICE extension: enable it here, fail closed
     * on create-device if the ICD does not provide it. */
    const char *device_exts[] = { "VK_EXT_pci_bus_info" };
    VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, NULL, 0,
        1, &dqci, 0, NULL, 1, device_exts, NULL };
    VkDevice dev = NULL;
    r = createDevice(gpu, &dci, NULL, &dev);
    if (r != VK_SUCCESS) vkfail("create-device", r);
    VkQueue queue = NULL;
    getDeviceQueue(dev, qfam, 0, &queue);

    VkPhysicalDeviceMemoryProperties mp = {0};
    getMemProps(gpu, &mp);
    uint32_t memType = 0xffffffffu;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++) {
        VkMemoryPropertyFlags f = mp.memoryTypes[i].propertyFlags;
        if ((f & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) &&
            (f & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) { memType = i; break; }
    }
    if (memType == 0xffffffffu) fail("memory-type", "no HOST_VISIBLE|COHERENT");
    printf("BENCH-MEMORY-RECORD memType=%u path=HOST_VISIBLE|HOST_COHERENT\n", memType);

    VkDescriptorSetLayoutBinding bindings[3];
    for (uint32_t i = 0; i < 3; i++) {
        bindings[i].binding = i;
        bindings[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        bindings[i].descriptorCount = 1;
        bindings[i].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
        bindings[i].pImmutableSamplers = NULL;
    }
    VkDescriptorSetLayoutCreateInfo dslci = {
        VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, NULL, 0, 3, bindings };
    VkDescriptorSetLayout setLayout = NULL;
    r = createSetLayout(dev, &dslci, NULL, &setLayout);
    if (r != VK_SUCCESS) vkfail("descriptor-set-layout", r);
    VkPipelineLayoutCreateInfo plci = { VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        NULL, 0, 1, &setLayout, 0, NULL };
    VkPipelineLayout pipelineLayout = NULL;
    r = createPipelineLayout(dev, &plci, NULL, &pipelineLayout);
    if (r != VK_SUCCESS) vkfail("pipeline-layout", r);
    VkShaderModuleCreateInfo smci = { VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        NULL, 0, vector_add_spirv_words * sizeof(uint32_t), vector_add_spirv };
    VkShaderModule shader = NULL;
    r = createShaderModule(dev, &smci, NULL, &shader);
    if (r != VK_SUCCESS) vkfail("shader-module", r);
    VkPipelineShaderStageCreateInfo stage = {
        VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, NULL, 0,
        VK_SHADER_STAGE_COMPUTE_BIT, shader, "main", NULL };
    VkComputePipelineCreateInfo cpci = {
        VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO, NULL, 0,
        stage, pipelineLayout, NULL, 0 };
    VkPipeline pipeline = NULL;
    r = createComputePipelines(dev, NULL, 1, &cpci, NULL, &pipeline);
    if (r != VK_SUCCESS) vkfail("compute-pipeline", r);
    VkDescriptorPoolSize poolSize = { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 3 };
    VkDescriptorPoolCreateInfo dpci = { VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        NULL, 0, 1, 1, &poolSize };
    VkDescriptorPool pool = NULL;
    r = createDescriptorPool(dev, &dpci, NULL, &pool);
    if (r != VK_SUCCESS) vkfail("descriptor-pool", r);
    VkDescriptorSetAllocateInfo dsai = {
        VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, NULL, pool, 1, &setLayout };
    VkDescriptorSet set = NULL;
    r = allocateDescriptorSets(dev, &dsai, &set);
    if (r != VK_SUCCESS) vkfail("descriptor-alloc", r);

    VkFenceCreateInfo fci = { VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, NULL, 0 };
    VkFence fence = NULL;
    r = createFence(dev, &fci, NULL, &fence);
    if (r != VK_SUCCESS) vkfail("create-fence", r);

    Case cases[MAX_CASES] = {
        { 4096u, 20u, 200u },
        { 1u << 20, 10u, 50u },
        { 1u << 23, 5u, 20u },
        { 0u, 0u, 0u }
    };
    const char *override = getenv("BENCH_ELEMENTS");
    if (override && *override) {
        unsigned long n = strtoul(override, NULL, 0);
        if (n == 0 || n > (1u << 26)) fail("bench-elements", "out of range");
        cases[0].elements = (uint32_t)n;
        cases[0].warmup = 5; cases[0].iters = 20;
        cases[1].elements = 0;
    }
    const char *iters_override = getenv("BENCH_ITERS");
    if (iters_override && *iters_override) {
        unsigned long k = strtoul(iters_override, NULL, 0);
        if (k == 0 || k > MAX_ITERS) fail("bench-iters", "out of range");
        for (uint32_t c = 0; c < MAX_CASES && cases[c].elements; c++)
            cases[c].iters = (uint32_t)k;
    }

    for (uint32_t c = 0; c < MAX_CASES && cases[c].elements; c++) {
        uint32_t elements = cases[c].elements;
        VkDeviceSize bytes = (VkDeviceSize)elements * sizeof(uint32_t);
        VkBuffer bufs[3] = {0}; VkDeviceMemory mems[3] = {0}; void *ptrs[3] = {0};
        for (int i = 0; i < 3; i++) {
            r = make_buffer(createBuffer, getReqs, allocateMemory, bindMemory,
                            mapMemory, dev, memType, bytes,
                            &bufs[i], &mems[i], &ptrs[i]);
            if (r != VK_SUCCESS) vkfail("buffer-memory-map", r);
        }
        uint32_t *A = ptrs[0], *B = ptrs[1], *C = ptrs[2];
        for (uint32_t i = 0; i < elements; i++) {
            A[i] = a_val(i); B[i] = b_val(i); C[i] = 0xDEADBEEFu;
        }

        VkDescriptorBufferInfo dbi[3];
        for (int i = 0; i < 3; i++) {
            dbi[i].buffer = bufs[i]; dbi[i].offset = 0; dbi[i].range = bytes;
        }
        VkWriteDescriptorSet writes[3];
        for (int i = 0; i < 3; i++) {
            writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[i].pNext = NULL; writes[i].dstSet = set;
            writes[i].dstBinding = (uint32_t)i; writes[i].dstArrayElement = 0;
            writes[i].descriptorCount = 1;
            writes[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            writes[i].pImageInfo = NULL; writes[i].pBufferInfo = &dbi[i];
            writes[i].pTexelBufferView = NULL;
        }
        updateDescriptorSets(dev, 3, writes, 0, NULL);

        VkCommandPoolCreateInfo cpi = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            NULL, 0, qfam };
        VkCommandPool cmdPool = NULL;
        r = createCommandPool(dev, &cpi, NULL, &cmdPool);
        if (r != VK_SUCCESS) vkfail("command-pool", r);
        VkCommandBufferAllocateInfo cbai = {
            VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, NULL, cmdPool, 0, 1 };
        VkCommandBuffer cmd = NULL;
        r = allocateCommandBuffers(dev, &cbai, &cmd);
        if (r != VK_SUCCESS) vkfail("command-buffer", r);
        VkCommandBufferBeginInfo cbbi = {
            VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, NULL, 0, NULL };
        r = beginCommandBuffer(cmd, &cbbi);
        if (r != VK_SUCCESS) vkfail("begin-command-buffer", r);
        cmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        cmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout,
                              0, 1, &set, 0, NULL);
        uint32_t groups = (elements + LOCAL_SIZE - 1) / LOCAL_SIZE;
        cmdDispatch(cmd, groups, 1, 1);
        r = endCommandBuffer(cmd);
        if (r != VK_SUCCESS) vkfail("end-command-buffer", r);

        VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO, NULL,
            0, NULL, NULL, 1, &cmd, 0, NULL };

        /* Correctness first: one dispatch and CPU comparison. */
        r = resetFences(dev, 1, &fence);
        if (r != VK_SUCCESS) vkfail("reset-fence-correctness", r);
        r = queueSubmit(queue, 1, &si, fence);
        if (r != VK_SUCCESS) vkfail("submit-correctness", r);
        r = waitForFences(dev, 1, &fence, VK_TRUE, 30000000000ULL);
        if (r != VK_SUCCESS) vkfail("wait-correctness", r);
        if (getFenceStatus(dev, fence) != VK_SUCCESS) fail("fence", "not signaled");
        uint32_t mismatch = 0;
        for (uint32_t i = 0; i < elements; i++)
            if (C[i] != a_val(i) + b_val(i)) { mismatch = 1; break; }
        uint32_t got = fnv1a((const unsigned char *)C, bytes);
        printf("BENCH-CORRECT elements=%u mismatch=%u checksum=0x%08x\n",
               elements, mismatch, got);
        if (mismatch) fail("correctness", "GPU result differs from CPU reference");

        double samples[MAX_ITERS];
        uint32_t total = cases[c].warmup + cases[c].iters;
        if (total > MAX_ITERS) fail("bench-iters", "exceeds MAX_ITERS");
        for (uint32_t k = 0; k < total; k++) {
            r = resetFences(dev, 1, &fence);
            if (r != VK_SUCCESS) vkfail("reset-fence", r);
            double t0 = ns_now();
            r = queueSubmit(queue, 1, &si, fence);
            if (r != VK_SUCCESS) vkfail("queue-submit", r);
            r = waitForFences(dev, 1, &fence, VK_TRUE, 30000000000ULL);
            if (r != VK_SUCCESS) vkfail("wait-fences", r);
            double dt = ns_now() - t0;
            if (getFenceStatus(dev, fence) != VK_SUCCESS) fail("fence-status", "not signaled");
            if (k >= cases[c].warmup) samples[k - cases[c].warmup] = dt;
        }

        /* Correctness again AFTER the timed loop: a fast but stale/wrong
         * result must not be reported as a benchmark PASS. */
        uint32_t mismatch_after = 0;
        for (uint32_t i = 0; i < elements; i++)
            if (C[i] != a_val(i) + b_val(i)) { mismatch_after = 1; break; }
        uint32_t got_after = fnv1a((const unsigned char *)C, bytes);
        printf("BENCH-CORRECT-AFTER elements=%u mismatch=%u checksum=0x%08x\n",
               elements, mismatch_after, got_after);
        if (mismatch_after) fail("correctness-after", "result changed or is wrong");
        if (got_after != got) fail("checksum-after", "post-loop checksum differs");

        qsort(samples, cases[c].iters, sizeof samples[0], cmp_double);
        double sum = 0;
        for (uint32_t k = 0; k < cases[c].iters; k++) sum += samples[k];
        double min_ns = samples[0];
        double med_ns = samples[cases[c].iters / 2];
        double mean_ns = sum / cases[c].iters;
        /* c[i] = a[i] + b[i]: 2 loads + 1 store = 12 bytes per element. */
        double traffic = 12.0 * (double)elements;
        printf("BENCH-CASE elements=%u bytes_per_buffer=%llu groups=%u "
               "warmup=%u iters=%u min_ns=%.0f median_ns=%.0f mean_ns=%.0f "
               "median_gb_s=%.4f traffic_bytes=%.0f\n",
               elements, (unsigned long long)bytes, groups,
               cases[c].warmup, cases[c].iters, min_ns, med_ns, mean_ns,
               traffic / med_ns, traffic);
        fflush(stdout);
    }

    printf("BENCH-OK board=10de:1c82@0000:01:00.0 driver_id=%u driver_name=%s "
           "binding=%s pr21=NOT-RUN mmio=none\n",
           (unsigned)drv.driverID, drv.driverName, binding);
    return 0;
}
