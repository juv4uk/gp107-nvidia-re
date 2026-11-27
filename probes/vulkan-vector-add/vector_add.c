/*
 * Clean-room Vulkan compute witness probe.
 *
 * No NVIDIA headers, no vendor source, no libvulkan wrapper library.
 * It asserts a PCI BDF through sysfs and through VK_EXT_pci_bus_info,
 * dispatches one trivial uint vector-add shader, waits on a fence,
 * reads back the destination buffer and checks every element on CPU.
 *
 * Exit codes: 0 = CHECK-OK (only on a real matching GPU), 2 = usage/config,
 * 3 = unsupported interface, 4 = Vulkan error, 5 = checksum mismatch.
 */

#include <vulkan/vulkan.h>

#include <errno.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define EXPECTED_VENDOR 0x10deu
#define EXPECTED_DEVICE 0x1c82u

static void fail(const char *step, int rc, const char *fmt, ...)
{
    va_list ap;
    fprintf(stderr, "VECTOR-ADD-FAIL step=%s rc=%d ", step, rc);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(rc);
}

static void vk_check(VkResult res, const char *step)
{
    if (res != VK_SUCCESS)
        fail(step, 4, "vkResult=%d", (int)res);
}

static bool has_extension(const char *const *names, uint32_t count, const char *want)
{
    for (uint32_t i = 0; i < count; i++)
        if (strcmp(names[i], want) == 0)
            return true;
    return false;
}

static uint32_t *read_spirv(const char *path, size_t *word_count)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        fail("read-spirv", 2, "path=%s errno=%d", path, errno);
    if (fseek(f, 0, SEEK_END) != 0)
        fail("read-spirv-seek", 2, "path=%s", path);
    long bytes = ftell(f);
    if (bytes <= 0 || (bytes % 4) != 0 || bytes > (16L * 1024 * 1024))
        fail("read-spirv-size", 2, "path=%s bytes=%ld", path, bytes);
    rewind(f);
    uint32_t *words = malloc((size_t)bytes);
    if (!words)
        fail("read-spirv-alloc", 2, "bytes=%ld", bytes);
    if (fread(words, 1, (size_t)bytes, f) != (size_t)bytes)
        fail("read-spirv-read", 2, "path=%s", path);
    fclose(f);
    *word_count = (size_t)bytes / 4;
    return words;
}

static uint32_t read_sysfs_hex(const char *path)
{
    FILE *f = fopen(path, "r");
    if (!f)
        fail("sysfs-open", 3, "path=%s errno=%d", path, errno);
    unsigned value = 0;
    if (fscanf(f, "%x", &value) != 1)
        fail("sysfs-parse", 3, "path=%s", path);
    fclose(f);
    return (uint32_t)value;
}

static void parse_bdf(const char *text, uint32_t *domain, uint32_t *bus,
                      uint32_t *device, uint32_t *function)
{
    unsigned d, b, dev, fn;
    if (sscanf(text, "%4x:%2x:%2x.%1x", &d, &b, &dev, &fn) != 4)
        fail("bdf-parse", 2, "bdf=%s expected=dddd:bb:dd.f", text);
    *domain = d;
    *bus = b;
    *device = dev;
    *function = fn;
}

static int find_memory_type(const VkPhysicalDeviceMemoryProperties *props,
                            uint32_t required, uint32_t *index)
{
    for (uint32_t i = 0; i < props->memoryTypeCount; i++)
        if ((props->memoryTypes[i].propertyFlags & required) == required) {
            *index = i;
            return 1;
        }
    return 0;
}

static void create_buffer(VkDevice device,
                          const VkPhysicalDeviceMemoryProperties *mem_props,
                          VkDeviceSize size, VkBufferUsageFlags usage,
                          VkBuffer *buffer, VkDeviceMemory *memory)
{
    VkBufferCreateInfo bci = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
    };
    vk_check(vkCreateBuffer(device, &bci, NULL, buffer), "vkCreateBuffer");

    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(device, *buffer, &req);
    uint32_t type = 0;
    if (!find_memory_type(mem_props,
                          VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                          VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &type))
        fail("memory-type", 3, "no host-visible coherent type");

    VkMemoryAllocateInfo mai = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = req.size,
        .memoryTypeIndex = type,
    };
    vk_check(vkAllocateMemory(device, &mai, NULL, memory), "vkAllocateMemory");
    vk_check(vkBindBufferMemory(device, *buffer, *memory, 0), "vkBindBufferMemory");
}

int main(int argc, char **argv)
{
    const char *bdf_text = NULL;
    const char *spirv_path = NULL;
    uint32_t elements = 4096;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--bdf") == 0 && i + 1 < argc) {
            bdf_text = argv[++i];
        } else if (strcmp(argv[i], "--spirv") == 0 && i + 1 < argc) {
            spirv_path = argv[++i];
        } else if (strcmp(argv[i], "--elements") == 0 && i + 1 < argc) {
            char *end = NULL;
            unsigned long n = strtoul(argv[++i], &end, 10);
            if (end == argv[i] || *end != '\0' || n == 0 || n > (1UL << 24))
                fail("elements-parse", 2, "elements=%s", argv[i]);
            elements = (uint32_t)n;
        } else {
            fail("usage", 2, "usage: %s --bdf dddd:bb:dd.f --spirv FILE [--elements N]", argv[0]);
        }
    }
    if (!bdf_text || !spirv_path)
        fail("usage", 2, "--bdf and --spirv are required");

    uint32_t domain, bus, devnum, function;
    parse_bdf(bdf_text, &domain, &bus, &devnum, &function);

    char path[256];
    snprintf(path, sizeof(path), "/sys/bus/pci/devices/%s/vendor", bdf_text);
    if (read_sysfs_hex(path) != EXPECTED_VENDOR)
        fail("bdf-vendor", 3, "bdf=%s expected=10de", bdf_text);
    snprintf(path, sizeof(path), "/sys/bus/pci/devices/%s/device", bdf_text);
    if (read_sysfs_hex(path) != EXPECTED_DEVICE)
        fail("bdf-device", 3, "bdf=%s expected=1c82", bdf_text);
    printf("BDF-SYSFS-OK bdf=%s vendor=%04x device=%04x\n",
           bdf_text, EXPECTED_VENDOR, EXPECTED_DEVICE);

    size_t code_words = 0;
    uint32_t *code = read_spirv(spirv_path, &code_words);

    uint32_t ext_count = 0;
    vk_check(vkEnumerateInstanceExtensionProperties(NULL, &ext_count, NULL),
             "vkEnumerateInstanceExtensionProperties-count");
    VkExtensionProperties *exts = calloc(ext_count ? ext_count : 1, sizeof(*exts));
    if (!exts)
        fail("alloc-instance-exts", 2, "count=%" PRIu32, ext_count);
    vk_check(vkEnumerateInstanceExtensionProperties(NULL, &ext_count, exts),
             "vkEnumerateInstanceExtensionProperties-list");
    const char **names = malloc(ext_count * sizeof(*names));
    if (!names)
        fail("alloc-instance-names", 2, "count=%" PRIu32, ext_count);
    for (uint32_t i = 0; i < ext_count; i++)
        names[i] = exts[i].extensionName;
    bool have_props2 = has_extension(names, ext_count,
                                      VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);
    free(names);
    free(exts);
    if (!have_props2)
        fail("instance-extension", 3, "missing=%s",
             VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);

    VkApplicationInfo app = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "gp107-vector-add",
        .applicationVersion = 1,
        .pEngineName = "gp107-clean-room",
        .engineVersion = 1,
        .apiVersion = VK_API_VERSION_1_0,
    };
    const char *enabled_instance_exts[] = {
        VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME,
    };
    VkInstanceCreateInfo ici = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = enabled_instance_exts,
    };
    VkInstance instance = VK_NULL_HANDLE;
    vk_check(vkCreateInstance(&ici, NULL, &instance), "vkCreateInstance");

    PFN_vkGetPhysicalDeviceProperties2KHR get_props2 =
        (PFN_vkGetPhysicalDeviceProperties2KHR)
        vkGetInstanceProcAddr(instance, "vkGetPhysicalDeviceProperties2KHR");
    if (!get_props2)
        fail("instance-proc", 3, "missing=vkGetPhysicalDeviceProperties2KHR");

    uint32_t gpu_count = 0;
    vk_check(vkEnumeratePhysicalDevices(instance, &gpu_count, NULL),
             "vkEnumeratePhysicalDevices-count");
    if (gpu_count == 0)
        fail("enumerate-devices", 3, "no Vulkan physical devices");
    VkPhysicalDevice *gpus = calloc(gpu_count, sizeof(*gpus));
    if (!gpus)
        fail("alloc-gpus", 2, "count=%" PRIu32, gpu_count);
    vk_check(vkEnumeratePhysicalDevices(instance, &gpu_count, gpus),
             "vkEnumeratePhysicalDevices-list");

    VkPhysicalDevice selected = VK_NULL_HANDLE;
    uint32_t selected_queue = 0;
    VkPhysicalDeviceMemoryProperties selected_mem = {0};

    for (uint32_t i = 0; i < gpu_count && selected == VK_NULL_HANDLE; i++) {
        uint32_t device_ext_count = 0;
        vk_check(vkEnumerateDeviceExtensionProperties(gpus[i], NULL, &device_ext_count, NULL),
                 "vkEnumerateDeviceExtensionProperties-count");
        VkExtensionProperties *dexts = calloc(device_ext_count ? device_ext_count : 1,
                                              sizeof(*dexts));
        if (!dexts)
            fail("alloc-device-exts", 2, "count=%" PRIu32, device_ext_count);
        vk_check(vkEnumerateDeviceExtensionProperties(gpus[i], NULL, &device_ext_count, dexts),
                 "vkEnumerateDeviceExtensionProperties-list");
        bool have_pci_bus = false;
        for (uint32_t j = 0; j < device_ext_count; j++)
            if (strcmp(dexts[j].extensionName, VK_EXT_PCI_BUS_INFO_EXTENSION_NAME) == 0)
                have_pci_bus = true;
        free(dexts);
        if (!have_pci_bus)
            continue;

        VkPhysicalDeviceIDProperties id_props = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES,
        };
        VkPhysicalDevicePCIBusInfoPropertiesEXT pci_props = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PCI_BUS_INFO_PROPERTIES_EXT,
        };
        id_props.pNext = &pci_props;
        VkPhysicalDeviceProperties2 props2 = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
            .pNext = &id_props,
        };
        get_props2(gpus[i], &props2);

        if (props2.properties.vendorID != EXPECTED_VENDOR ||
            props2.properties.deviceID != EXPECTED_DEVICE)
            continue;
        if (pci_props.pciDomain != domain || pci_props.pciBus != bus ||
            pci_props.pciDevice != devnum || pci_props.pciFunction != function)
            continue;

        uint32_t qf_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(gpus[i], &qf_count, NULL);
        VkQueueFamilyProperties *qfs = calloc(qf_count ? qf_count : 1, sizeof(*qfs));
        if (!qfs)
            fail("alloc-queue-families", 2, "count=%" PRIu32, qf_count);
        vkGetPhysicalDeviceQueueFamilyProperties(gpus[i], &qf_count, qfs);
        for (uint32_t j = 0; j < qf_count; j++) {
            if ((qfs[j].queueFlags & VK_QUEUE_COMPUTE_BIT) != 0) {
                selected = gpus[i];
                selected_queue = j;
                break;
            }
        }
        free(qfs);
        if (selected != VK_NULL_HANDLE) {
            vkGetPhysicalDeviceMemoryProperties(gpus[i], &selected_mem);
            printf("VULKAN-PHYSICAL-OK name=%s vendor=%04x device=%04x "
                   "pci=%04x:%02x:%02x.%x queue_family=%" PRIu32 "\n",
                   props2.properties.deviceName, props2.properties.vendorID,
                   props2.properties.deviceID, pci_props.pciDomain, pci_props.pciBus,
                   pci_props.pciDevice, pci_props.pciFunction, selected_queue);
        }
    }
    free(gpus);
    if (selected == VK_NULL_HANDLE)
        fail("device-selection", 3, "no compute device matching bdf=%s", bdf_text);

    float priority = 1.0f;
    VkDeviceQueueCreateInfo qci = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = selected_queue,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    };
    const char *enabled_device_exts[] = { VK_EXT_PCI_BUS_INFO_EXTENSION_NAME };
    VkDeviceCreateInfo dci = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &qci,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = enabled_device_exts,
    };
    VkDevice device = VK_NULL_HANDLE;
    vk_check(vkCreateDevice(selected, &dci, NULL, &device), "vkCreateDevice");

    VkDescriptorSetLayoutBinding bindings[3] = {
        { .binding = 0, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
          .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT },
        { .binding = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
          .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT },
        { .binding = 2, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
          .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT },
    };
    VkDescriptorSetLayoutCreateInfo dslci = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 3,
        .pBindings = bindings,
    };
    VkDescriptorSetLayout layout = VK_NULL_HANDLE;
    vk_check(vkCreateDescriptorSetLayout(device, &dslci, NULL, &layout),
             "vkCreateDescriptorSetLayout");

    VkShaderModuleCreateInfo smci = {
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code_words * 4,
        .pCode = code,
    };
    VkShaderModule shader = VK_NULL_HANDLE;
    vk_check(vkCreateShaderModule(device, &smci, NULL, &shader), "vkCreateShaderModule");

    VkPipelineLayoutCreateInfo plci = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &layout,
    };
    VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
    vk_check(vkCreatePipelineLayout(device, &plci, NULL, &pipeline_layout),
             "vkCreatePipelineLayout");

    VkPipelineShaderStageCreateInfo stage = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = VK_SHADER_STAGE_COMPUTE_BIT,
        .module = shader,
        .pName = "main",
    };
    VkComputePipelineCreateInfo cpci = {
        .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = stage,
        .layout = pipeline_layout,
    };
    VkPipeline pipeline = VK_NULL_HANDLE;
    vk_check(vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &cpci, NULL, &pipeline),
             "vkCreateComputePipelines");

    VkDescriptorPoolSize pool_size = {
        .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = 3,
    };
    VkDescriptorPoolCreateInfo dpci = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
    };
    VkDescriptorPool pool = VK_NULL_HANDLE;
    vk_check(vkCreateDescriptorPool(device, &dpci, NULL, &pool), "vkCreateDescriptorPool");

    VkDescriptorSetAllocateInfo dsai = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &layout,
    };
    VkDescriptorSet descriptor_set = VK_NULL_HANDLE;
    vk_check(vkAllocateDescriptorSets(device, &dsai, &descriptor_set),
             "vkAllocateDescriptorSets");

    VkDeviceSize bytes = (VkDeviceSize)elements * sizeof(uint32_t);
    VkBuffer buf_a = VK_NULL_HANDLE, buf_b = VK_NULL_HANDLE, buf_c = VK_NULL_HANDLE;
    VkDeviceMemory mem_a = VK_NULL_HANDLE, mem_b = VK_NULL_HANDLE, mem_c = VK_NULL_HANDLE;
    create_buffer(device, &selected_mem, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                  &buf_a, &mem_a);
    create_buffer(device, &selected_mem, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                  &buf_b, &mem_b);
    create_buffer(device, &selected_mem, bytes, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                  &buf_c, &mem_c);

    VkDescriptorBufferInfo info_a = { .buffer = buf_a, .offset = 0, .range = bytes };
    VkDescriptorBufferInfo info_b = { .buffer = buf_b, .offset = 0, .range = bytes };
    VkDescriptorBufferInfo info_c = { .buffer = buf_c, .offset = 0, .range = bytes };
    VkWriteDescriptorSet writes[3] = {
        { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = descriptor_set,
          .dstBinding = 0, .descriptorCount = 1,
          .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &info_a },
        { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = descriptor_set,
          .dstBinding = 1, .descriptorCount = 1,
          .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &info_b },
        { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = descriptor_set,
          .dstBinding = 2, .descriptorCount = 1,
          .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &info_c },
    };
    vkUpdateDescriptorSets(device, 3, writes, 0, NULL);

    uint32_t *host_a = NULL, *host_b = NULL;
    vk_check(vkMapMemory(device, mem_a, 0, bytes, 0, (void **)&host_a), "vkMapMemory-a");
    vk_check(vkMapMemory(device, mem_b, 0, bytes, 0, (void **)&host_b), "vkMapMemory-b");
    for (uint32_t i = 0; i < elements; i++) {
        host_a[i] = i + 1;
        host_b[i] = 2u * (i + 1);
    }
    VkMappedMemoryRange ranges[2] = {
        { .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, .memory = mem_a,
          .size = bytes },
        { .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, .memory = mem_b,
          .size = bytes },
    };
    vk_check(vkFlushMappedMemoryRanges(device, 2, ranges), "vkFlushMappedMemoryRanges");
    vkUnmapMemory(device, mem_a);
    vkUnmapMemory(device, mem_b);

    VkCommandPoolCreateInfo cpci_pool = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = selected_queue,
    };
    VkCommandPool command_pool = VK_NULL_HANDLE;
    vk_check(vkCreateCommandPool(device, &cpci_pool, NULL, &command_pool),
             "vkCreateCommandPool");

    VkCommandBufferAllocateInfo cbai = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    vk_check(vkAllocateCommandBuffers(device, &cbai, &cmd), "vkAllocateCommandBuffers");

    VkCommandBufferBeginInfo begin = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    vk_check(vkBeginCommandBuffer(cmd, &begin), "vkBeginCommandBuffer");
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout,
                            0, 1, &descriptor_set, 0, NULL);
    vkCmdDispatch(cmd, (elements + 63) / 64, 1, 1);
    vk_check(vkEndCommandBuffer(cmd), "vkEndCommandBuffer");

    VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
    VkFence fence = VK_NULL_HANDLE;
    vk_check(vkCreateFence(device, &fci, NULL, &fence), "vkCreateFence");

    VkSubmitInfo submit = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
    };
    VkQueue queue = VK_NULL_HANDLE;
    vkGetDeviceQueue(device, selected_queue, 0, &queue);
    vk_check(vkQueueSubmit(queue, 1, &submit, fence), "vkQueueSubmit");
    vk_check(vkWaitForFences(device, 1, &fence, VK_TRUE, UINT64_MAX), "vkWaitForFences");

    uint32_t *host_c = NULL;
    vk_check(vkMapMemory(device, mem_c, 0, bytes, 0, (void **)&host_c), "vkMapMemory-c");
    uint32_t bad = elements;
    uint32_t actual = 0;
    for (uint32_t i = 0; i < elements; i++) {
        uint32_t expected = 3u * (i + 1);
        if (host_c[i] != expected) {
            bad = i;
            actual = host_c[i];
            break;
        }
    }
    vkUnmapMemory(device, mem_c);

    if (bad != elements)
        fail("vector-add-check", 5, "index=%" PRIu32 " expected=%" PRIu32 " actual=%" PRIu32,
             bad, 3u * (bad + 1), actual);

    printf("VECTOR-ADD-CHECK-OK elements=%" PRIu32 " dispatch_groups=%" PRIu32 "\n",
           elements, (elements + 63) / 64);
    printf("HARNESS-DONE rc=0\n");

    vkDestroyFence(device, fence, NULL);
    vkDestroyCommandPool(device, command_pool, NULL);
    vkDestroyBuffer(device, buf_c, NULL);
    vkFreeMemory(device, mem_c, NULL);
    vkDestroyBuffer(device, buf_b, NULL);
    vkFreeMemory(device, mem_b, NULL);
    vkDestroyBuffer(device, buf_a, NULL);
    vkFreeMemory(device, mem_a, NULL);
    vkDestroyDescriptorPool(device, pool, NULL);
    vkDestroyPipeline(device, pipeline, NULL);
    vkDestroyPipelineLayout(device, pipeline_layout, NULL);
    vkDestroyShaderModule(device, shader, NULL);
    vkDestroyDescriptorSetLayout(device, layout, NULL);
    vkDestroyDevice(device, NULL);
    vkDestroyInstance(instance, NULL);
    free(code);
    return 0;
}
