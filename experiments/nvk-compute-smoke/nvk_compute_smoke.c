/* Clean-room NVK vector-add compute smoke test.
 * Strict filter: BDF sysfs identity + vendorID 0x10de + deviceID 0x1c82 +
 * driverID VK_DRIVER_ID_MESA_NVK.  No CPU fallback, no proprietary ICD.
 * No vendor headers/code; Vulkan ABI declarations are in vk_min.h.
 */
#define _POSIX_C_SOURCE 200809L
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <libgen.h>
#include "vk_min.h"
#ifdef SMOKE_NOOP_SHADER
#include "shader_noop.spv.h"
#else
#include "shader.spv.h"
#endif

#define ELEMENTS 1024u
#define LOCAL_SIZE_RAW 64u

static void fail(const char *step, const char *detail) {
    fprintf(stderr, "NVK-COMPUTE-FAIL step=%s detail=%s\n", step, detail ? detail : "-");
    exit(2);
}
static void vkfail(const char *step, VkResult r) {
    fprintf(stderr, "NVK-COMPUTE-FAIL step=%s vkResult=%d\n", step, (int)r);
    exit(2);
}
static uint32_t a_val(uint32_t i) { return i * 3u + 1u; }
static uint32_t b_val(uint32_t i) { return i * 5u + 7u; }
static uint32_t fnv1a(const void *data, size_t len) {
    const unsigned char *p = data;
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < len; i++) { h ^= p[i]; h *= 16777619u; }
    return h;
}

static void check_bdf(void) {
    const char *bdf = getenv("SMOKE_BDF");
    if (!bdf) bdf = "0000:01:00.0";
    char path[256], buf[128] = {0};
    snprintf(path, sizeof path, "/sys/bus/pci/devices/%s/vendor", bdf);
    FILE *f = fopen(path, "r");
    if (!f) fail("bdf-vendor", "sysfs unreadable");
    if (!fgets(buf, sizeof buf, f)) fail("bdf-vendor", "empty");
    fclose(f);
    if (strncmp(buf, "0x10de", 6) != 0) fail("bdf-vendor", buf);

    memset(buf, 0, sizeof buf);
    snprintf(path, sizeof path, "/sys/bus/pci/devices/%s/device", bdf);
    f = fopen(path, "r");
    if (!f) fail("bdf-device", "sysfs unreadable");
    if (!fgets(buf, sizeof buf, f)) fail("bdf-device", "empty");
    fclose(f);
    if (strncmp(buf, "0x1c82", 6) != 0) fail("bdf-device", buf);

    snprintf(path, sizeof path, "/sys/bus/pci/devices/%s/driver", bdf);
    char link[256] = {0};
    ssize_t n = readlink(path, link, sizeof link - 1);
    if (n <= 0) fail("bdf-driver", "not bound");
    link[n] = 0;
    if (strcmp(basename(link), "nouveau") != 0) fail("bdf-driver", link);
    printf("BDF-ASSERT-OK bdf=%s vendor=0x10de device=0x1c82 driver=nouveau\n", bdf);
}

#define LOAD(dst, name, inst) do {                                     \
    (dst) = (PFN_##name)gipa((inst), #name);                           \
    if (!(dst)) fail("dlsym", #name);                                  \
} while (0)

static VkResult create_buffer_and_memory(
        PFN_vkCreateBuffer createBuffer,
        PFN_vkGetBufferMemoryRequirements getReqs,
        PFN_vkAllocateMemory allocateMemory,
        PFN_vkBindBufferMemory bindMemory,
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
    r = bindMemory(dev, *buf, *mem, 0);
    if (r != VK_SUCCESS) return r;
    return mapMemory(dev, *mem, 0, size, 0, ptr);
}

int main(void) {
    check_bdf();
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
    PFN_vkQueueSubmit queueSubmit;
    PFN_vkWaitForFences waitForFences;
    PFN_vkGetFenceStatus getFenceStatus;

    LOAD(createInstance, vkCreateInstance, NULL);
    VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO, NULL,
        "wsm-nvk-smoke", 1, "clean-room", 1, VK_API_VERSION_1_3 };
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

    VkPhysicalDevice gpu = NULL;
    VkPhysicalDeviceProperties2Min props2 = {0};
    VkPhysicalDeviceDriverProperties driver = {0};
    props2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
    props2.pNext = &driver;
    driver.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES;
    for (uint32_t i = 0; i < ndev; i++) {
        VkPhysicalDeviceProperties2Min p = {0};
        VkPhysicalDeviceDriverProperties d = {0};
        p.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
        p.pNext = &d;
        d.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES;
        getProps2(devices[i], &p);
        if (p.properties.vendorID == 0x10de && p.properties.deviceID == 0x1c82) {
            gpu = devices[i]; props2 = p; driver = d; break;
        }
    }
    if (!gpu) fail("device-filter", "no 10de:1c82 physical device");
    printf("DEVICE-FILTER-OK vendor=0x%04x device=0x%04x name=%s\n",
           props2.properties.vendorID, props2.properties.deviceID,
           props2.properties.deviceName);
    if (driver.driverID != VK_DRIVER_ID_MESA_NVK)
        fail("driver-filter", driver.driverName);
    printf("DRIVER-FILTER-OK id=%u name=%s info=%s\n",
           (unsigned)driver.driverID, driver.driverName, driver.driverInfo);

    uint32_t nq = 0;
    getQueueFamilies(gpu, &nq, NULL);
    VkQueueFamilyProperties *qs = calloc(nq, sizeof *qs);
    if (!qs) fail("calloc", "queue families");
    getQueueFamilies(gpu, &nq, qs);
    uint32_t qfam = 0xffffffffu;
    for (uint32_t i = 0; i < nq; i++)
        if (qs[i].queueFlags & VK_QUEUE_COMPUTE_BIT) { qfam = i; break; }
    if (qfam == 0xffffffffu) fail("queue-family", "no compute queue");
    float prio = 1.0f;
    VkDeviceQueueCreateInfo dqci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        NULL, 0, qfam, 1, &prio };
    VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, NULL, 0,
        1, &dqci, 0, NULL, 0, NULL, NULL };
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

    VkDeviceSize bytes = (VkDeviceSize)ELEMENTS * sizeof(uint32_t);
    VkBuffer bufs[3] = {0}; VkDeviceMemory mems[3] = {0}; void *ptrs[3] = {0};
    for (int i = 0; i < 3; i++) {
        r = create_buffer_and_memory(createBuffer, getReqs, allocateMemory,
                bindMemory, mapMemory, dev, memType, bytes,
                &bufs[i], &mems[i], &ptrs[i]);
        if (r != VK_SUCCESS) vkfail("buffer-memory-map", r);
    }
    uint32_t *A = ptrs[0], *B = ptrs[1], *C_init = ptrs[2];
    for (uint32_t i = 0; i < ELEMENTS; i++) {
        A[i] = a_val(i);
        B[i] = b_val(i);
        /* Poison C so a no-op or stale-buffer shader cannot pass by accident. */
        C_init[i] = 0xDEADBEEFu;
    }
    printf("BUFFERS-OK elements=%u bytes=%llu memType=%u c-init=0xdeadbeef\n",
           ELEMENTS, (unsigned long long)bytes, memType);

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

    VkDescriptorBufferInfo dbi[3];
    for (int i = 0; i < 3; i++) { dbi[i].buffer = bufs[i]; dbi[i].offset = 0; dbi[i].range = bytes; }
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

    VkCommandPoolCreateInfo cpci2 = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        NULL, 0, qfam };
    VkCommandPool cmdPool = NULL;
    r = createCommandPool(dev, &cpci2, NULL, &cmdPool);
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
    uint32_t groups = (ELEMENTS + LOCAL_SIZE_RAW - 1) / LOCAL_SIZE_RAW;
    cmdDispatch(cmd, groups, 1, 1);
    printf("DISPATCH-RECORDED groups=%ux1x1 local=%u\n", groups, LOCAL_SIZE_RAW);
    r = endCommandBuffer(cmd);
    if (r != VK_SUCCESS) vkfail("end-command-buffer", r);

    VkFenceCreateInfo fci = { VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, NULL, 0 };
    VkFence fence = NULL;
    r = createFence(dev, &fci, NULL, &fence);
    if (r != VK_SUCCESS) vkfail("create-fence", r);
    VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO, NULL,
        0, NULL, NULL, 1, &cmd, 0, NULL };
    r = queueSubmit(queue, 1, &si, fence);
    if (r != VK_SUCCESS) vkfail("queue-submit", r);
    r = waitForFences(dev, 1, &fence, VK_TRUE, 10000000000ULL);
    if (r != VK_SUCCESS) vkfail("wait-fences", r);
    if (getFenceStatus(dev, fence) != VK_SUCCESS) fail("fence-status", "not signaled");
    printf("FENCE-OK status=SIGNALED\n");

    uint32_t *C = ptrs[2];
    uint32_t got = fnv1a(C, bytes);
    uint32_t *ref = calloc(ELEMENTS, sizeof *ref);
    if (!ref) fail("calloc", "reference");
    for (uint32_t i = 0; i < ELEMENTS; i++) ref[i] = a_val(i) + b_val(i);
    uint32_t expected = fnv1a(ref, bytes);
    uint32_t mismatch = 0;
    for (uint32_t i = 0; i < ELEMENTS; i++) if (C[i] != ref[i]) { mismatch++; break; }
    printf("CHECKSUM got=0x%08x expected=0x%08x match=%s mismatches=%u\n",
           got, expected, got == expected ? "yes" : "no", mismatch);
    if (got != expected || mismatch) fail("checksum", "GPU result differs from CPU reference");

    printf("NVK-COMPUTE-SMOKE-OK bdf=0000:01:00.0 vendor=0x10de device=0x1c82 "
           "driver=%s(%u) elements=%u dispatch=%ux1x1 fence=SIGNALED "
           "checksum=0x%08x match=yes pr21=NOT-RUN mmio=none\n",
           driver.driverName, (unsigned)driver.driverID, ELEMENTS, groups, got);

    for (int i = 0; i < 3; i++) unmapMemory(dev, mems[i]);
    return 0;
}
