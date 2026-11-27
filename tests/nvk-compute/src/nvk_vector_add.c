#define _POSIX_C_SOURCE 200809L
#include <vulkan/vulkan.h>

#include <dirent.h>
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PCI_VENDOR 0x10deU
#define PCI_DEVICE 0x1c82U
#define LOCAL_SIZE 64U
#define SMALL_COUNT 257U
#define LARGE_COUNT 1048576U
#define FENCE_TIMEOUT_NS UINT64_C(30000000000)

typedef struct {
    char text[32];
    uint32_t domain, bus, device, function;
} PciAddress;

typedef struct {
    VkBuffer buffer;
    VkDeviceMemory memory;
    void *map;
    bool coherent;
} HostBuffer;

typedef struct {
    VkInstance instance;
    VkPhysicalDevice physical;
    VkDevice device;
    VkQueue queue;
    uint32_t family;
    VkPhysicalDeviceProperties properties;
    VkPhysicalDeviceDriverProperties driver;
    VkPhysicalDeviceMemoryProperties memory;
    VkPhysicalDeviceLimits limits;
    bool queue_idle_safe;
    VkCommandPool command_pool;
    VkPipelineLayout pipeline_layout;
    VkPipeline pipeline;
} Gpu;

static bool
read_hex(const char *path, uint32_t *out)
{
    FILE *file = fopen(path, "r");
    unsigned int value = 0;
    bool ok;
    if (!file)
        return false;
    ok = fscanf(file, "%x", &value) == 1;
    fclose(file);
    if (ok)
        *out = value;
    return ok;
}

static bool
parse_bdf(const char *s, PciAddress *a)
{
    unsigned int d, b, dev, f;
    if (sscanf(s, "%x:%x:%x.%x", &d, &b, &dev, &f) != 4 ||
        d > UINT16_MAX || b > UINT8_MAX || dev > 31U || f > 7U)
        return false;
    a->domain = d; a->bus = b; a->device = dev; a->function = f;
    (void)snprintf(a->text, sizeof(a->text), "%04x:%02x:%02x.%x", d, b, dev, f);
    return true;
}

static bool
find_gp107(PciAddress *target)
{
    DIR *dir = opendir("/sys/bus/pci/devices");
    struct dirent *entry;
    unsigned int matches = 0;
    PciAddress found = {0};
    if (!dir) {
        fprintf(stderr, "sysfs PCI scan failed: %s\n", strerror(errno));
        return false;
    }
    while ((entry = readdir(dir)) != NULL) {
        char vp[512], dp[512];
        uint32_t vendor = 0, device = 0;
        PciAddress candidate = {0};
        if (entry->d_name[0] == '.')
            continue;
        if (snprintf(vp, sizeof(vp), "/sys/bus/pci/devices/%s/vendor", entry->d_name) >= (int)sizeof(vp) ||
            snprintf(dp, sizeof(dp), "/sys/bus/pci/devices/%s/device", entry->d_name) >= (int)sizeof(dp))
            continue;
        if (!read_hex(vp, &vendor) || !read_hex(dp, &device) ||
            vendor != PCI_VENDOR || device != PCI_DEVICE || !parse_bdf(entry->d_name, &candidate))
            continue;
        found = candidate;
        matches++;
    }
    closedir(dir);
    if (matches != 1U) {
        fprintf(stderr, "GP107-BDF-ASSERT-FAIL expected one %04x:%04x, found %u\n",
                PCI_VENDOR, PCI_DEVICE, matches);
        return false;
    }
    *target = found;
    return true;
}

static bool
has_extension(VkPhysicalDevice p, const char *name)
{
    uint32_t n = 0;
    VkExtensionProperties *list;
    bool found = false;
    if (vkEnumerateDeviceExtensionProperties(p, NULL, &n, NULL) != VK_SUCCESS || n == 0U)
        return false;
    list = calloc(n, sizeof(*list));
    if (!list)
        return false;
    if (vkEnumerateDeviceExtensionProperties(p, NULL, &n, list) == VK_SUCCESS) {
        for (uint32_t i = 0; i < n; i++) {
            if (strcmp(list[i].extensionName, name) == 0)
                found = true;
        }
    }
    free(list);
    return found;
}

static bool
select_device(Gpu *g, const PciAddress *target)
{
    uint32_t n = 0;
    VkPhysicalDevice *list = NULL, selected = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties selected_props = {0};
    VkPhysicalDeviceDriverProperties selected_driver = {0};
    unsigned int matches = 0;
    if (vkEnumeratePhysicalDevices(g->instance, &n, NULL) != VK_SUCCESS || n == 0U)
        return false;
    list = calloc(n, sizeof(*list));
    if (!list)
        return false;
    if (vkEnumeratePhysicalDevices(g->instance, &n, list) != VK_SUCCESS) {
        free(list);
        return false;
    }
    for (uint32_t i = 0; i < n; i++) {
        VkPhysicalDeviceProperties props;
        VkPhysicalDevicePCIBusInfoPropertiesEXT pci = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PCI_BUS_INFO_PROPERTIES_EXT
        };
        VkPhysicalDeviceDriverProperties driver = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES,
            .pNext = &pci
        };
        VkPhysicalDeviceProperties2 props2 = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
            .pNext = &driver
        };
        vkGetPhysicalDeviceProperties(list[i], &props);
        if (props.vendorID != PCI_VENDOR || props.deviceID != PCI_DEVICE)
            continue;
        if (props.apiVersion < VK_API_VERSION_1_3 ||
            !has_extension(list[i], VK_EXT_PCI_BUS_INFO_EXTENSION_NAME))
            continue;
        vkGetPhysicalDeviceProperties2(list[i], &props2);
        if (pci.pciDomain != target->domain || pci.pciBus != target->bus ||
            pci.pciDevice != target->device || pci.pciFunction != target->function)
            continue;
        if (driver.driverID != VK_DRIVER_ID_MESA_NVK)
            continue;
        selected = list[i];
        selected_props = props;
        selected_driver = driver;
        selected_driver.pNext = NULL;
        matches++;
    }
    free(list);
    if (matches != 1U || selected == VK_NULL_HANDLE) {
        fprintf(stderr, "GP107-NVK-ASSERT-FAIL exact NVK devices=%u\n", matches);
        return false;
    }
    g->physical = selected;
    g->properties = selected_props;
    g->driver = selected_driver;
    g->limits = selected_props.limits;
    vkGetPhysicalDeviceMemoryProperties(selected, &g->memory);
    printf("NVK-DEVICE-ASSERT-OK bdf=%s pci=%04x:%04x name=\"%s\" api=%u.%u driver=%s info=\"%s\"\n",
           target->text, (unsigned int)selected_props.vendorID, (unsigned int)selected_props.deviceID,
           selected_props.deviceName, VK_VERSION_MAJOR(selected_props.apiVersion),
           VK_VERSION_MINOR(selected_props.apiVersion), selected_driver.driverName,
           selected_driver.driverInfo);
    return true;
}

static bool
create_device(Gpu *g)
{
    uint32_t n = 0;
    VkQueueFamilyProperties *families;
    uint32_t family = UINT32_MAX;
    const float priority = 1.0F;
    const char *ext = VK_EXT_PCI_BUS_INFO_EXTENSION_NAME;
    VkDeviceQueueCreateInfo q = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    VkDeviceCreateInfo info = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
    vkGetPhysicalDeviceQueueFamilyProperties(g->physical, &n, NULL);
    if (n == 0U) return false;
    families = calloc(n, sizeof(*families));
    if (!families) return false;
    vkGetPhysicalDeviceQueueFamilyProperties(g->physical, &n, families);
    for (uint32_t i = 0; i < n; i++) {
        if (families[i].queueCount && (families[i].queueFlags & VK_QUEUE_COMPUTE_BIT)) {
            family = i;
            printf("NVK-QUEUE-FAMILY index=%u flags=0x%x count=%u\n",
                   i, (unsigned int)families[i].queueFlags, families[i].queueCount);
            break;
        }
    }
    free(families);
    if (family == UINT32_MAX) return false;
    g->family = family;
    q.queueFamilyIndex = family;
    q.queueCount = 1;
    q.pQueuePriorities = &priority;
    info.queueCreateInfoCount = 1;
    info.pQueueCreateInfos = &q;
    info.enabledExtensionCount = 1;
    info.ppEnabledExtensionNames = &ext;
    if (vkCreateDevice(g->physical, &info, NULL, &g->device) != VK_SUCCESS)
        return false;
    vkGetDeviceQueue(g->device, family, 0, &g->queue);
    return g->queue != VK_NULL_HANDLE;
}

static void
buffer_destroy(Gpu *g, HostBuffer *b)
{
    if (b->map) vkUnmapMemory(g->device, b->memory);
    if (b->buffer) vkDestroyBuffer(g->device, b->buffer, NULL);
    if (b->memory) vkFreeMemory(g->device, b->memory, NULL);
    memset(b, 0, sizeof(*b));
}

static bool
buffer_create(Gpu *g, VkDeviceSize size, HostBuffer *b)
{
    VkBufferCreateInfo bi = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size, .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
    VkMemoryRequirements req;
    VkMemoryAllocateInfo ai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    int chosen = -1, score_best = -1;
    if (vkCreateBuffer(g->device, &bi, NULL, &b->buffer) != VK_SUCCESS) return false;
    vkGetBufferMemoryRequirements(g->device, b->buffer, &req);
    for (uint32_t i = 0; i < g->memory.memoryTypeCount; i++) {
        VkMemoryPropertyFlags flags = g->memory.memoryTypes[i].propertyFlags;
        int score = ((flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) ? 10 : 0) +
                    ((flags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) ? 1 : 0);
        if ((req.memoryTypeBits & (1U << i)) && (flags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) && score > score_best) {
            chosen = (int)i; score_best = score;
        }
    }
    if (chosen < 0) return false;
    ai.allocationSize = req.size;
    ai.memoryTypeIndex = (uint32_t)chosen;
    if (vkAllocateMemory(g->device, &ai, NULL, &b->memory) != VK_SUCCESS) return false;
    b->coherent = (g->memory.memoryTypes[chosen].propertyFlags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) != 0;
    if (vkBindBufferMemory(g->device, b->buffer, b->memory, 0) != VK_SUCCESS) return false;
    return vkMapMemory(g->device, b->memory, 0, VK_WHOLE_SIZE, 0, &b->map) == VK_SUCCESS;
}

static bool
flush_or_invalidate(Gpu *g, HostBuffer *b, bool invalidate)
{
    VkMappedMemoryRange range = { .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
        .memory = b->memory, .offset = 0, .size = VK_WHOLE_SIZE };
    if (b->coherent) return true;
    return (invalidate ? vkInvalidateMappedMemoryRanges(g->device, 1, &range) :
                          vkFlushMappedMemoryRanges(g->device, 1, &range)) == VK_SUCCESS;
}

static bool
run_case(Gpu *g, VkPipeline pipeline, VkPipelineLayout layout, VkDescriptorSet descriptor,
         VkCommandPool pool, HostBuffer *a, HostBuffer *b, HostBuffer *c, VkFence fence, uint32_t count)
{
    VkDescriptorBufferInfo buffers[3] = {
        {a->buffer, 0, (VkDeviceSize)LARGE_COUNT * sizeof(uint32_t)},
        {b->buffer, 0, (VkDeviceSize)LARGE_COUNT * sizeof(uint32_t)},
        {c->buffer, 0, (VkDeviceSize)LARGE_COUNT * sizeof(uint32_t)} };
    VkWriteDescriptorSet writes[3] = {0};
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    VkCommandBufferAllocateInfo cai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
    VkCommandBufferBeginInfo cbi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
    VkBufferMemoryBarrier input[2] = {0};
    VkBufferMemoryBarrier output = { .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, .dstAccessMask = VK_ACCESS_HOST_READ_BIT,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .buffer = c->buffer, .offset = 0, .size = (VkDeviceSize)count * sizeof(uint32_t) };
    VkSubmitInfo submit = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1, .pCommandBuffers = &cmd };
    VkResult result;
    uint64_t checksum = 0;
    uint64_t expected = ((uint64_t)count * (3U * ((uint64_t)count - 1U) + 2U)) / 2U;
    bool ok = false;
    for (uint32_t i = 0; i < 3; i++) {
        writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[i].dstSet = descriptor; writes[i].dstBinding = i;
        writes[i].descriptorCount = 1; writes[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        writes[i].pBufferInfo = &buffers[i];
    }
    vkUpdateDescriptorSets(g->device, 3, writes, 0, NULL);
    if (vkAllocateCommandBuffers(g->device, &cai, &cmd) != VK_SUCCESS) goto done;
    if (vkBeginCommandBuffer(cmd, &cbi) != VK_SUCCESS) goto done;
    input[0] = (VkBufferMemoryBarrier){ .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_HOST_WRITE_BIT, .dstAccessMask = VK_ACCESS_SHADER_READ_BIT,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .buffer = a->buffer, .offset = 0, .size = (VkDeviceSize)count * sizeof(uint32_t) };
    input[1] = input[0]; input[1].buffer = b->buffer;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_HOST_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                         0, 0, NULL, 2, input, 0, NULL);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &descriptor, 0, NULL);
    vkCmdPushConstants(cmd, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(count), &count);
    vkCmdDispatch(cmd, (count + LOCAL_SIZE - 1U) / LOCAL_SIZE, 1, 1);
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT,
                         0, 0, NULL, 1, &output, 0, NULL);
    if (vkEndCommandBuffer(cmd) != VK_SUCCESS) goto done;
    if (vkResetFences(g->device, 1, &fence) != VK_SUCCESS) goto done;
    result = vkQueueSubmit(g->queue, 1, &submit, fence);
    if (result != VK_SUCCESS) goto done;
    g->queue_idle_safe = false;
    result = vkWaitForFences(g->device, 1, &fence, VK_TRUE, FENCE_TIMEOUT_NS);
    if (result != VK_SUCCESS) {
        fprintf(stderr, "NVK-FENCE-TIMEOUT-OR-ERROR result=%d; leaving Vulkan objects to process teardown\n", (int)result);
        goto done;
    }
    g->queue_idle_safe = true;
    if (!flush_or_invalidate(g, c, true)) goto done;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t got = ((uint32_t *)c->map)[i];
        uint32_t want = 3U * i + 1U;
        if (got != want) { fprintf(stderr, "VECTOR-ADD-MISMATCH i=%u want=%u got=%u\n", i, want, got); goto done; }
        checksum += got;
    }
    if (checksum != expected) { fprintf(stderr, "VECTOR-ADD-CHECKSUM-FAIL\n"); goto done; }
    printf("NVK-COMPUTE-PASS count=%u groups=%u checksum=%" PRIu64 "\n",
           count, (count + LOCAL_SIZE - 1U) / LOCAL_SIZE, checksum);
    ok = true;
done:
    if (cmd) vkFreeCommandBuffers(g->device, pool, 1, &cmd);
    return ok;
}

int
main(int argc, char **argv)
{
    Gpu g = {0}; PciAddress target = {0};
    const char *shader_path = argc > 1 ? argv[1] : "vector_add.spv";
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "gp107-nvk-vector-add", .apiVersion = VK_API_VERSION_1_2 };
    VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
    VkCommandPoolCreateInfo cp = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, .queueFamilyIndex = 0 };
    VkShaderModule shader = VK_NULL_HANDLE;
    VkPipelineShaderStageCreateInfo stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = VK_SHADER_STAGE_COMPUTE_BIT, .pName = "main" };
    VkDescriptorSetLayoutBinding bindings[3] = {0};
    VkDescriptorSetLayoutCreateInfo dlci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 3, .pBindings = bindings };
    VkPushConstantRange push = { .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT, .size = sizeof(uint32_t) };
    VkPipelineLayoutCreateInfo plci = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1, .pushConstantRangeCount = 1, .pPushConstantRanges = &push };
    VkComputePipelineCreateInfo pci = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .basePipelineIndex = -1 };
    VkDescriptorPoolSize ps = { .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 3 };
    VkDescriptorPoolCreateInfo dpci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps };
    VkDescriptorSetLayout dsl = VK_NULL_HANDLE;
    VkDescriptorPool pool = VK_NULL_HANDLE;
    VkDescriptorSetAllocateInfo dsai = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorSetCount = 1, .pSetLayouts = &dsl };
    VkDescriptorSet descriptor = VK_NULL_HANDLE;
    VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
    VkFence fence = VK_NULL_HANDLE;
    HostBuffer a = {0}, b = {0}, c = {0};
    VkResult vr; bool ok = false;
    g.queue_idle_safe = true;
    if (argc > 2 || !find_gp107(&target)) goto done;
    vr = vkCreateInstance(&ici, NULL, &g.instance); if (vr != VK_SUCCESS) goto done;
    if (!select_device(&g, &target) || !create_device(&g)) goto done;
    cp.queueFamilyIndex = g.family;
    if (vkCreateCommandPool(g.device, &cp, NULL, &g.command_pool) != VK_SUCCESS) goto done;
    for (uint32_t i = 0; i < 3; i++) { bindings[i].binding = i; bindings[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        bindings[i].descriptorCount = 1; bindings[i].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT; }
    if (vkCreateDescriptorSetLayout(g.device, &dlci, NULL, &dsl) != VK_SUCCESS) goto done;
    plci.pSetLayouts = &dsl;
    if (vkCreatePipelineLayout(g.device, &plci, NULL, &g.pipeline_layout) != VK_SUCCESS) goto done;
    { FILE *fp = fopen(shader_path, "rb"); long len; uint32_t *code;
      if (!fp || fseek(fp, 0, SEEK_END) || (len = ftell(fp)) <= 0 || (len % 4) || fseek(fp, 0, SEEK_SET)) { if (fp) fclose(fp); goto done; }
      code = malloc((size_t)len); if (!code) { fclose(fp); goto done; }
      if (fread(code, 1, (size_t)len, fp) != (size_t)len) { free(code); fclose(fp); goto done; }
      fclose(fp); if (code[0] != 0x07230203U) { free(code); goto done; }
      { VkShaderModuleCreateInfo smci = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = (size_t)len, .pCode = code };
        vr = vkCreateShaderModule(g.device, &smci, NULL, &shader); }
      free(code); if (vr != VK_SUCCESS) goto done; }
    stage.module = shader; pci.stage = stage; pci.layout = g.pipeline_layout;
    if (vkCreateComputePipelines(g.device, VK_NULL_HANDLE, 1, &pci, NULL, &g.pipeline) != VK_SUCCESS) goto done;
    if (g.limits.maxComputeWorkGroupSize[0] < LOCAL_SIZE ||
        g.limits.maxComputeWorkGroupInvocations < LOCAL_SIZE ||
        ((LARGE_COUNT + LOCAL_SIZE - 1U) / LOCAL_SIZE) > g.limits.maxComputeWorkGroupCount[0] ||
        g.limits.maxPushConstantsSize < sizeof(uint32_t) ||
        g.limits.maxStorageBufferRange < (VkDeviceSize)LARGE_COUNT * 4U ||
        g.limits.maxPerStageDescriptorStorageBuffers < 3U ||
        g.limits.maxDescriptorSetStorageBuffers < 3U) {
        fprintf(stderr, "NVK device limits do not support the vector-add test profile\n");
        goto done;
    }
    if (!buffer_create(&g, (VkDeviceSize)LARGE_COUNT * 4U, &a) ||
        !buffer_create(&g, (VkDeviceSize)LARGE_COUNT * 4U, &b) ||
        !buffer_create(&g, (VkDeviceSize)LARGE_COUNT * 4U, &c)) goto done;
    for (uint32_t i = 0; i < LARGE_COUNT; i++) { ((uint32_t *)a.map)[i] = i; ((uint32_t *)b.map)[i] = 2U * i + 1U; }
    if (!flush_or_invalidate(&g, &a, false) || !flush_or_invalidate(&g, &b, false)) goto done;
    if (vkCreateDescriptorPool(g.device, &dpci, NULL, &pool) != VK_SUCCESS) goto done;
    dsai.descriptorPool = pool; dsai.pSetLayouts = &dsl;
    if (vkAllocateDescriptorSets(g.device, &dsai, &descriptor) != VK_SUCCESS) goto done;
    if (vkCreateFence(g.device, &fci, NULL, &fence) != VK_SUCCESS) goto done;
    if (!run_case(&g, g.pipeline, g.pipeline_layout, descriptor, g.command_pool, &a, &b, &c, fence, SMALL_COUNT) ||
        !run_case(&g, g.pipeline, g.pipeline_layout, descriptor, g.command_pool, &a, &b, &c, fence, LARGE_COUNT)) goto done;
    printf("NVK-COMPUTE-ALL-PASS bdf=%s pci=%04x:%04x driver=%s\n", target.text, g.properties.vendorID, g.properties.deviceID, g.driver.driverName);
    ok = true;
done:
    if (g.device && !g.queue_idle_safe) {
        fprintf(stderr, "NVK-CLEANUP-SKIPPED pending queue work; process teardown will release driver objects\n");
        return EXIT_FAILURE;
    }
    if (g.device) (void)vkDeviceWaitIdle(g.device);
    if (fence) vkDestroyFence(g.device, fence, NULL);
    if (pool) vkDestroyDescriptorPool(g.device, pool, NULL);
    if (c.map || c.buffer || c.memory) buffer_destroy(&g, &c);
    if (b.map || b.buffer || b.memory) buffer_destroy(&g, &b);
    if (a.map || a.buffer || a.memory) buffer_destroy(&g, &a);
    if (shader) vkDestroyShaderModule(g.device, shader, NULL);
    if (g.pipeline) vkDestroyPipeline(g.device, g.pipeline, NULL);
    if (g.pipeline_layout) vkDestroyPipelineLayout(g.device, g.pipeline_layout, NULL);
    if (dsl) vkDestroyDescriptorSetLayout(g.device, dsl, NULL);
    if (g.command_pool) vkDestroyCommandPool(g.device, g.command_pool, NULL);
    if (g.device) vkDestroyDevice(g.device, NULL);
    if (g.instance) vkDestroyInstance(g.instance, NULL);
    return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
