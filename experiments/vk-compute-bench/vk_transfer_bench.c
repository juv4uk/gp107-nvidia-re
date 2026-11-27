/* Clean-room transfer/compute phase benchmark for the same GP107 board.
 *
 * Separate from vk_compute_bench: this measures HOST_VISIBLE staging ->
 * DEVICE_LOCAL buffers -> compute -> DEVICE_LOCAL -> HOST_VISIBLE staging,
 * with a separate fence per phase. It does NOT replace the canonical
 * HOST_VISIBLE benchmark and does not claim peak VRAM bandwidth.
 * Driver-agnostic, BDF asserted from sysfs and VK_EXT_pci_bus_info.
 * No PR #21 executable, no MMIO, no RM ioctl, no vendor source.
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
#define MAX_ITERS 256
#define NPH 4

static void fail(const char *step, const char *detail) {
    fprintf(stderr, "TRANSFER-FAIL step=%s detail=%s\n", step, detail ? detail : "-");
    exit(2);
}
static void vkfail(const char *step, VkResult r) {
    fprintf(stderr, "TRANSFER-FAIL step=%s vkResult=%d\n", step, (int)r);
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

static void parse_bdf(uint32_t *d, uint32_t *b, uint32_t *dev, uint32_t *fn) {
    const char *s = getenv("BENCH_BDF");
    if (!s) s = "0000:01:00.0";
    if (sscanf(s, "%8x:%4x:%4x.%4x", d, b, dev, fn) != 4) fail("bdf-parse", s);
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
    printf("TRANSFER-BOARD-OK bdf=%s vendor=0x10de device=0x1c82 binding=%s\n",
           bdf, binding);
}

#define LOAD(dst, name, inst) do {                                      \
    (dst) = (PFN_##name)gipa((inst), #name);                            \
    if (!(dst)) fail("dlsym", #name);                                   \
} while (0)

static VkResult make_buf(
        PFN_vkCreateBuffer createBuffer,
        PFN_vkGetBufferMemoryRequirements getReqs,
        PFN_vkAllocateMemory allocateMemory,
        PFN_vkBindBufferMemory bindBufferMemory,
        PFN_vkMapMemory mapMemory,
        VkDevice dev, uint32_t memType, VkBufferUsageFlags usage,
        VkDeviceSize size, VkBuffer *buf, VkDeviceMemory *mem, void **ptr) {
    VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, NULL, 0,
        size, usage, VK_SHARING_MODE_EXCLUSIVE, 0, NULL };
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
    if (ptr) return mapMemory(dev, *mem, 0, size, 0, ptr);
    return VK_SUCCESS;
}

#define RUN_PHASE(CB, FENCE, ARRAY, INDEX) do {                          \
    r = resetFences(dev, 1, &(FENCE));                                   \
    if (r != VK_SUCCESS) vkfail("reset-fence", r);                       \
    double t0_ = ns_now();                                              \
    r = queueSubmit(queue, 1, &(VkSubmitInfo){                           \
        VK_STRUCTURE_TYPE_SUBMIT_INFO, NULL, 0, NULL, NULL,              \
        1, &(CB), 0, NULL }, (FENCE));                                   \
    if (r != VK_SUCCESS) vkfail("submit", r);                            \
    r = waitForFences(dev, 1, &(FENCE), VK_TRUE, 30000000000ULL);         \
    if (r != VK_SUCCESS) vkfail("wait-fence", r);                        \
    if (getFenceStatus(dev, (FENCE)) != VK_SUCCESS) fail("fence", "unsignaled"); \
    (ARRAY)[(INDEX)] = ns_now() - t0_;                                   \
} while (0)

int main(void) {
    char binding[128] = "unknown";
    board_identity(binding, sizeof binding);

    void *lib = dlopen("libvulkan.so.1", RTLD_NOW);
    if (!lib) fail("dlopen", dlerror());
    PFN_vkGetInstanceProcAddr gipa = dlsym(lib, "vkGetInstanceProcAddr");
    if (!gipa) fail("dlsym", "vkGetInstanceProcAddr");
    PFN_vkCreateInstance createInstance = NULL;
    PFN_vkEnumeratePhysicalDevices enumerateDevices = NULL;
    PFN_vkGetPhysicalDeviceProperties2 getProps2 = NULL;
    PFN_vkGetPhysicalDeviceMemoryProperties getMemProps = NULL;
    PFN_vkGetPhysicalDeviceQueueFamilyProperties getQueueFamilies = NULL;
    PFN_vkCreateDevice createDevice = NULL;
    PFN_vkGetDeviceQueue getDeviceQueue = NULL;
    PFN_vkCreateBuffer createBuffer = NULL;
    PFN_vkGetBufferMemoryRequirements getReqs = NULL;
    PFN_vkAllocateMemory allocateMemory = NULL;
    PFN_vkBindBufferMemory bindMemory = NULL;
    PFN_vkMapMemory mapMemory = NULL;
    PFN_vkUnmapMemory unmapMemory = NULL;
    PFN_vkCreateDescriptorSetLayout createSetLayout = NULL;
    PFN_vkCreatePipelineLayout createPipelineLayout = NULL;
    PFN_vkCreateShaderModule createShaderModule = NULL;
    PFN_vkCreateComputePipelines createComputePipelines = NULL;
    PFN_vkCreateDescriptorPool createDescriptorPool = NULL;
    PFN_vkAllocateDescriptorSets allocateDescriptorSets = NULL;
    PFN_vkUpdateDescriptorSets updateDescriptorSets = NULL;
    PFN_vkCreateCommandPool createCommandPool = NULL;
    PFN_vkAllocateCommandBuffers allocateCommandBuffers = NULL;
    PFN_vkBeginCommandBuffer beginCommandBuffer = NULL;
    PFN_vkCmdBindPipeline cmdBindPipeline = NULL;
    PFN_vkCmdBindDescriptorSets cmdBindDescriptorSets = NULL;
    PFN_vkCmdDispatch cmdDispatch = NULL;
    PFN_vkCmdCopyBuffer cmdCopyBuffer = NULL;
    PFN_vkEndCommandBuffer endCommandBuffer = NULL;
    PFN_vkCreateFence createFence = NULL;
    PFN_vkResetFences resetFences = NULL;
    PFN_vkQueueSubmit queueSubmit = NULL;
    PFN_vkWaitForFences waitForFences = NULL;
    PFN_vkGetFenceStatus getFenceStatus = NULL;
    LOAD(createInstance, vkCreateInstance, NULL);

    VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO, NULL,
        "wsm-cleanroom-transfer", 1, "clean-room", 1, VK_API_VERSION_1_3 };
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

    uint32_t ndev = 0;
    r = enumerateDevices(inst, &ndev, NULL);
    if (r != VK_SUCCESS || ndev == 0) vkfail("enumerate", r);
    VkPhysicalDevice *devices = calloc(ndev, sizeof *devices);
    if (!devices) fail("calloc", "devices");
    r = enumerateDevices(inst, &ndev, devices);
    if (r != VK_SUCCESS) vkfail("enumerate-2", r);

    uint32_t wd = 0, wb = 0, wdev = 0, wf = 0;
    parse_bdf(&wd, &wb, &wdev, &wf);
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
            b.pciDomain == wd && b.pciBus == wb &&
            b.pciDevice == wdev && b.pciFunction == wf) {
            gpu = devices[i]; props2 = p; drv = d; pci = b; break;
        }
    }
    if (!gpu) fail("pci-bdf", "no 10de:1c82 device at BENCH_BDF");
    printf("TRANSFER-PCI-RECORD bdf=%04x:%02x:%02x.%x match=yes\n",
           pci.pciDomain, pci.pciBus, pci.pciDevice, pci.pciFunction);
    printf("TRANSFER-DRIVER-RECORD id=%u name=%s info=%s device=%s\n",
           (unsigned)drv.driverID, drv.driverName, drv.driverInfo,
           props2.properties.deviceName);
    printf("TRANSFER-ICD-RECORD icd=%s\n",
           getenv("VK_ICD_FILENAMES") ? getenv("VK_ICD_FILENAMES") : "default");

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
    const char *device_exts[] = { "VK_EXT_pci_bus_info" };
    VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, NULL, 0,
        1, &dqci, 0, NULL, 1, device_exts, NULL };
    VkDevice dev = NULL;
    r = createDevice(gpu, &dci, NULL, &dev);
    if (r != VK_SUCCESS) vkfail("create-device", r);
    VkQueue queue = NULL;
    getDeviceQueue(dev, qfam, 0, &queue);
    LOAD(createBuffer, vkCreateBuffer, inst);
    LOAD(getReqs, vkGetBufferMemoryRequirements, inst);
    LOAD(allocateMemory, vkAllocateMemory, inst);
    LOAD(bindMemory, vkBindBufferMemory, inst);
    LOAD(mapMemory, vkMapMemory, inst);
    LOAD(unmapMemory, vkUnmapMemory, inst);
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
    LOAD(cmdCopyBuffer, vkCmdCopyBuffer, inst);
    LOAD(endCommandBuffer, vkEndCommandBuffer, inst);
    LOAD(createFence, vkCreateFence, inst);
    LOAD(resetFences, vkResetFences, inst);
    LOAD(queueSubmit, vkQueueSubmit, inst);
    LOAD(waitForFences, vkWaitForFences, inst);
    LOAD(getFenceStatus, vkGetFenceStatus, inst);

    VkPhysicalDeviceMemoryProperties mp = {0};
    getMemProps(gpu, &mp);
    uint32_t hostType = 0xffffffffu, devType = 0xffffffffu, devOnly = 0;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++) {
        VkMemoryPropertyFlags f = mp.memoryTypes[i].propertyFlags;
        if (hostType == 0xffffffffu && (f & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) &&
            (f & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) hostType = i;
        if ((f & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) &&
            !(f & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) && devType == 0xffffffffu) {
            devType = i; devOnly = 1;
        }
    }
    if (devType == 0xffffffffu)
        for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
            if (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
                { devType = i; break; }
    if (hostType == 0xffffffffu || devType == 0xffffffffu)
        fail("memory-type", "need HOST_VISIBLE|COHERENT and DEVICE_LOCAL");
    printf("TRANSFER-MEM-RECORD host_type=%u device_type=%u device_local_only=%u\n",
           hostType, devType, devOnly);

    unsigned long ne = 0;
    const char *es = getenv("BENCH_ELEMENTS");
    if (es && *es) ne = strtoul(es, NULL, 0);
    if (ne == 0 || ne > (1u << 26)) fail("bench-elements", "out of range");
    uint32_t elements = (uint32_t)ne;
    unsigned long iters = 20;
    const char *is = getenv("BENCH_ITERS");
    if (is && *is) iters = strtoul(is, NULL, 0);
    if (iters == 0 || iters > MAX_ITERS) fail("bench-iters", "out of range");
    printf("TRANSFER-CONFIG elements=%u iters=%lu warmup=2 local_size=%u "
           "pr21=NOT-RUN mmio=none\n", elements, iters, LOCAL_SIZE);

    VkDeviceSize bytes = (VkDeviceSize)elements * sizeof(uint32_t);
    VkBuffer hostA, hostB, hostC, devA, devB, devC;
    VkDeviceMemory memHA, memHB, memHC, memDA, memDB, memDC;
    void *pA, *pB, *pC;
    VkBufferUsageFlags hsrc = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    VkBufferUsageFlags hdst = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    VkBufferUsageFlags dusage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT |
        VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    if (make_buf(createBuffer, getReqs, allocateMemory, bindMemory, mapMemory,
                 dev, hostType, hsrc, bytes, &hostA, &memHA, &pA) != VK_SUCCESS)
        fail("host-a", "buffer-memory-map");
    if (make_buf(createBuffer, getReqs, allocateMemory, bindMemory, mapMemory,
                 dev, hostType, hsrc, bytes, &hostB, &memHB, &pB) != VK_SUCCESS)
        fail("host-b", "buffer-memory-map");
    if (make_buf(createBuffer, getReqs, allocateMemory, bindMemory, mapMemory,
                 dev, hostType, hdst, bytes, &hostC, &memHC, &pC) != VK_SUCCESS)
        fail("host-c", "buffer-memory-map");
    if (make_buf(createBuffer, getReqs, allocateMemory, bindMemory, mapMemory,
                 dev, devType, dusage, bytes, &devA, &memDA, NULL) != VK_SUCCESS)
        fail("dev-a", "buffer-memory-map");
    if (make_buf(createBuffer, getReqs, allocateMemory, bindMemory, mapMemory,
                 dev, devType, dusage, bytes, &devB, &memDB, NULL) != VK_SUCCESS)
        fail("dev-b", "buffer-memory-map");
    if (make_buf(createBuffer, getReqs, allocateMemory, bindMemory, mapMemory,
                 dev, devType, dusage, bytes, &devC, &memDC, NULL) != VK_SUCCESS)
        fail("dev-c", "buffer-memory-map");

    uint32_t *A = pA, *B = pB, *C = pC;
    for (uint32_t i = 0; i < elements; i++) {
        A[i] = a_val(i); B[i] = b_val(i); C[i] = 0xDEADBEEFu;
    }
    unmapMemory(dev, memHA); unmapMemory(dev, memHB);

    VkDescriptorSetLayoutBinding bind[3];
    for (uint32_t i = 0; i < 3; i++) {
        bind[i].binding = i; bind[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        bind[i].descriptorCount = 1; bind[i].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
        bind[i].pImmutableSamplers = NULL;
    }
    VkDescriptorSetLayoutCreateInfo dslci = {
        VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, NULL, 0, 3, bind };
    VkDescriptorSetLayout setLayout = NULL;
    r = createSetLayout(dev, &dslci, NULL, &setLayout);
    if (r != VK_SUCCESS) vkfail("set-layout", r);
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
    VkComputePipelineCreateInfo cpci = { VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        NULL, 0, stage, pipelineLayout, NULL, 0 };
    VkPipeline pipeline = NULL;
    r = createComputePipelines(dev, NULL, 1, &cpci, NULL, &pipeline);
    if (r != VK_SUCCESS) vkfail("compute-pipeline", r);
    VkDescriptorPoolSize ps = { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 3 };
    VkDescriptorPoolCreateInfo dpci = { VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        NULL, 0, 1, 1, &ps };
    VkDescriptorPool pool = NULL;
    r = createDescriptorPool(dev, &dpci, NULL, &pool);
    if (r != VK_SUCCESS) vkfail("descriptor-pool", r);
    VkDescriptorSetAllocateInfo dsai = {
        VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, NULL, pool, 1, &setLayout };
    VkDescriptorSet set = NULL;
    r = allocateDescriptorSets(dev, &dsai, &set);
    if (r != VK_SUCCESS) vkfail("descriptor-alloc", r);
    VkBuffer bufs[3] = { devA, devB, devC };
    VkDescriptorBufferInfo dbi[3];
    VkWriteDescriptorSet writes[3];
    for (uint32_t i = 0; i < 3; i++) {
        dbi[i].buffer = bufs[i]; dbi[i].offset = 0; dbi[i].range = bytes;
        writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[i].pNext = NULL; writes[i].dstSet = set;
        writes[i].dstBinding = i; writes[i].dstArrayElement = 0;
        writes[i].descriptorCount = 1;
        writes[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        writes[i].pImageInfo = NULL; writes[i].pBufferInfo = &dbi[i];
        writes[i].pTexelBufferView = NULL;
    }
    updateDescriptorSets(dev, 3, writes, 0, NULL);

    VkCommandPoolCreateInfo cpci2 = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        NULL, 0, qfam };
    VkCommandPool cmdPool = NULL;
    r = createCommandPool(dev, &cpci2, NULL, &cmdPool);
    if (r != VK_SUCCESS) vkfail("command-pool", r);
    VkCommandBufferAllocateInfo cbai = {
        VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, NULL, cmdPool, 0, NPH };
    VkCommandBuffer cb[NPH] = {0};
    r = allocateCommandBuffers(dev, &cbai, cb);
    if (r != VK_SUCCESS) vkfail("command-buffers", r);
    VkCommandBufferBeginInfo cbbi = {
        VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, NULL, 0, NULL };
    VkBufferCopy cp = { 0, 0, bytes };
    for (uint32_t i = 0; i < NPH; i++) {
        r = beginCommandBuffer(cb[i], &cbbi);
        if (r != VK_SUCCESS) vkfail("begin-command-buffer", r);
    }
    cmdCopyBuffer(cb[0], hostA, devA, 1, &cp);
    cmdCopyBuffer(cb[1], hostB, devB, 1, &cp);
    cmdBindPipeline(cb[2], VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    cmdBindDescriptorSets(cb[2], VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout,
                         0, 1, &set, 0, NULL);
    cmdDispatch(cb[2], (elements + LOCAL_SIZE - 1) / LOCAL_SIZE, 1, 1);
    cmdCopyBuffer(cb[3], devC, hostC, 1, &cp);
    for (uint32_t i = 0; i < NPH; i++) {
        r = endCommandBuffer(cb[i]);
        if (r != VK_SUCCESS) vkfail("end-command-buffer", r);
    }

    VkFenceCreateInfo fci = { VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, NULL, 0 };
    VkFence fences[NPH] = {0};
    for (uint32_t i = 0; i < NPH; i++) {
        r = createFence(dev, &fci, NULL, &fences[i]);
        if (r != VK_SUCCESS) vkfail("create-fence", r);
    }

    /* Warmup: two full chains; not timed. */
    double sink[MAX_ITERS] = {0};
    for (uint32_t k = 0; k < 2; k++)
        for (uint32_t p = 0; p < NPH; p++) RUN_PHASE(cb[p], fences[p], sink, 0);
    (void)sink; /* warmup result intentionally discarded */

    double samples[NPH][MAX_ITERS];
    for (uint32_t k = 0; k < (uint32_t)iters; k++)
        for (uint32_t p = 0; p < NPH; p++) RUN_PHASE(cb[p], fences[p], samples[p], k);

    uint32_t mismatch = 0;
    for (uint32_t i = 0; i < elements; i++)
        if (C[i] != a_val(i) + b_val(i)) { mismatch = 1; break; }
    uint32_t got = fnv1a((const unsigned char *)C, bytes);
    printf("TRANSFER-CORRECT elements=%u mismatch=%u checksum=0x%08x\n",
           elements, mismatch, got);
    if (mismatch) fail("correctness", "DEVICE_LOCAL result mismatch");

    const char *names[NPH] = { "h2d_a", "h2d_b", "compute", "d2h_c" };
    for (uint32_t p = 0; p < NPH; p++) {
        qsort(samples[p], (size_t)iters, sizeof samples[p][0], cmp_double);
        double med = samples[p][(size_t)iters / 2];
        double traffic = (p == 2) ? 12.0 * (double)elements : 4.0 * (double)elements;
        printf("TRANSFER-PHASE phase=%s median_ns=%.0f effective_gb_s=%.4f "
               "traffic_bytes=%.0f\n", names[p], med, traffic / med, traffic);
    }
    printf("TRANSFER-OK board=10de:1c82@%04x:%02x:%02x.%x driver_id=%u "
           "driver_name=%s binding=%s pr21=NOT-RUN mmio=none\n",
           pci.pciDomain, pci.pciBus, pci.pciDevice, pci.pciFunction,
           (unsigned)drv.driverID, drv.driverName, binding);
    unmapMemory(dev, memHC);
    fflush(stdout);
    return 0;
}
