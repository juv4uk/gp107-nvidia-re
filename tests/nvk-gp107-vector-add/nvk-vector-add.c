#define _POSIX_C_SOURCE 200809L
#include <vulkan/vulkan.h>

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TARGET_VENDOR_ID 0x10deu
#define TARGET_DEVICE_ID 0x1c82u
#define LOCAL_SIZE_X 64u

#define REQUIRE(cond, code, ...) do { \
    if (!(cond)) { \
        fprintf(stderr, __VA_ARGS__); \
        fputc('\n', stderr); \
        return (code); \
    } \
} while (0)

#define VK_TRY(expr, stage) do { \
    VkResult _result = (expr); \
    if (_result != VK_SUCCESS) { \
        fprintf(stderr, "%s failed: VkResult=%d\n", (stage), (int)_result); \
        return 2; \
    } \
} while (0)

typedef struct {
    unsigned int domain;
    unsigned int bus;
    unsigned int device;
    unsigned int function;
} PciBdf;

typedef struct {
    VkBuffer buffer;
    VkDeviceMemory memory;
    void *mapped;
    VkDeviceSize size;
    bool coherent;
} HostBuffer;

static bool parse_bdf(const char *text, PciBdf *out)
{
    char trailing = '\0';
    int fields = sscanf(text, "%x:%x:%x.%x%c",
                        &out->domain, &out->bus, &out->device,
                        &out->function, &trailing);
    return fields == 4 && out->domain <= 0xffffu &&
           out->bus <= 0xffu && out->device <= 0x1fu &&
           out->function <= 7u;
}

static bool bdf_equal(const PciBdf *a, const PciBdf *b)
{
    return a->domain == b->domain && a->bus == b->bus &&
           a->device == b->device && a->function == b->function;
}

static bool has_device_extension(VkPhysicalDevice physical, const char *name)
{
    uint32_t count = 0;
    if (vkEnumerateDeviceExtensionProperties(physical, NULL, &count, NULL) != VK_SUCCESS)
        return false;

    VkExtensionProperties *extensions = calloc(count, sizeof(*extensions));
    if (!extensions)
        return false;

    VkResult result = vkEnumerateDeviceExtensionProperties(
        physical, NULL, &count, extensions);
    bool found = false;
    if (result == VK_SUCCESS) {
        for (uint32_t i = 0; i < count; ++i) {
            if (strcmp(extensions[i].extensionName, name) == 0) {
                found = true;
                break;
            }
        }
    }
    free(extensions);
    return found;
}

static int choose_memory_type(const VkPhysicalDeviceMemoryProperties *memory,
                              uint32_t bits,
                              uint32_t *index,
                              bool *coherent)
{
    int fallback = -1;
    for (uint32_t i = 0; i < memory->memoryTypeCount; ++i) {
        VkMemoryPropertyFlags flags = memory->memoryTypes[i].propertyFlags;
        if ((bits & (1u << i)) == 0 ||
            (flags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) == 0)
            continue;

        if ((flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) != 0) {
            *index = i;
            *coherent = true;
            return 0;
        }
        if (fallback < 0)
            fallback = (int)i;
    }

    if (fallback >= 0) {
        *index = (uint32_t)fallback;
        *coherent = false;
        return 0;
    }
    return -1;
}

static VkResult create_host_buffer(VkDevice device,
                                   const VkPhysicalDeviceMemoryProperties *memory,
                                   VkDeviceSize size,
                                   HostBuffer *out)
{
    memset(out, 0, sizeof(*out));
    out->size = size;

    VkBufferCreateInfo buffer_info = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE
    };
    VkResult result = vkCreateBuffer(device, &buffer_info, NULL, &out->buffer);
    if (result != VK_SUCCESS)
        return result;

    VkMemoryRequirements requirements;
    vkGetBufferMemoryRequirements(device, out->buffer, &requirements);

    uint32_t memory_index = 0;
    if (choose_memory_type(memory, requirements.memoryTypeBits,
                           &memory_index, &out->coherent) != 0)
        return VK_ERROR_FEATURE_NOT_PRESENT;

    VkMemoryAllocateInfo allocation = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size,
        .memoryTypeIndex = memory_index
    };
    result = vkAllocateMemory(device, &allocation, NULL, &out->memory);
    if (result != VK_SUCCESS)
        return result;

    result = vkBindBufferMemory(device, out->buffer, out->memory, 0);
    if (result != VK_SUCCESS)
        return result;

    return vkMapMemory(device, out->memory, 0, VK_WHOLE_SIZE, 0, &out->mapped);
}

static VkResult sync_host_memory(VkDevice device, HostBuffer *buffer, bool invalidate)
{
    if (buffer->coherent)
        return VK_SUCCESS;

    VkMappedMemoryRange range = {
        .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
        .memory = buffer->memory,
        .offset = 0,
        .size = VK_WHOLE_SIZE
    };
    return invalidate
        ? vkInvalidateMappedMemoryRanges(device, 1, &range)
        : vkFlushMappedMemoryRanges(device, 1, &range);
}

static void destroy_host_buffer(VkDevice device, HostBuffer *buffer)
{
    if (buffer->mapped)
        vkUnmapMemory(device, buffer->memory);
    if (buffer->buffer)
        vkDestroyBuffer(device, buffer->buffer, NULL);
    if (buffer->memory)
        vkFreeMemory(device, buffer->memory, NULL);
    memset(buffer, 0, sizeof(*buffer));
}

static uint32_t read_spirv(const char *path, uint32_t **words)
{
    FILE *file = fopen(path, "rb");
    if (!file) {
        fprintf(stderr, "SPIRV_OPEN_FAILED path=%s\n", path);
        return 0;
    }

    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return 0;
    }
    long length = ftell(file);
    if (length < 20 || (length % 4) != 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        fprintf(stderr, "SPIRV_SIZE_INVALID\n");
        return 0;
    }

    uint32_t *data = malloc((size_t)length);
    if (!data) {
        fclose(file);
        return 0;
    }
    size_t got = fread(data, 1, (size_t)length, file);
    fclose(file);
    if (got != (size_t)length || data[0] != 0x07230203u) {
        free(data);
        fprintf(stderr, "SPIRV_CONTENT_INVALID\n");
        return 0;
    }

    *words = data;
    return (uint32_t)((size_t)length / sizeof(uint32_t));
}

int main(int argc, char **argv)
{
    const char *bdf_text = NULL;
    const char *spirv_path = "vector_add.spv";
    uint32_t element_count = 257u;
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--bdf") == 0 && i + 1 < argc)
            bdf_text = argv[++i];
        else if (strcmp(argv[i], "--spv") == 0 && i + 1 < argc)
            spirv_path = argv[++i];
        else if (strcmp(argv[i], "--elements") == 0 && i + 1 < argc) {
            char *end = NULL;
            unsigned long parsed = strtoul(argv[++i], &end, 10);
            if (!end || end == argv[i] || *end != '\0' ||
                (parsed != 257ul && parsed != 1048576ul)) {
                fprintf(stderr, "element_count_INVALID (use 257 or 1048576)\n");
                return 2;
            }
            element_count = (uint32_t)parsed;
        } else {
            fprintf(stderr,
                    "usage: %s --bdf DDDD:BB:DD.F [--elements 257|1048576] [--spv file.spv]\n",
                    argv[0]);
            return 2;
        }
    }

    PciBdf expected_bdf;
    REQUIRE(bdf_text && parse_bdf(bdf_text, &expected_bdf), 2,
            "BDF_ARGUMENT_INVALID (expected DDDD:BB:DD.F)");

    uint32_t loader_version = VK_API_VERSION_1_0;
    VK_TRY(vkEnumerateInstanceVersion(&loader_version), "vkEnumerateInstanceVersion");
    REQUIRE(loader_version >= VK_API_VERSION_1_1, 2,
            "VULKAN_1_1_LOADER_REQUIRED loader=%u.%u.%u",
            VK_VERSION_MAJOR(loader_version), VK_VERSION_MINOR(loader_version),
            VK_VERSION_PATCH(loader_version));

    VkApplicationInfo application = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "NVK GP107 vector-add smoke test",
        .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "none",
        .engineVersion = VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = VK_API_VERSION_1_1
    };
    VkInstanceCreateInfo instance_info = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &application
    };
    VkInstance instance = VK_NULL_HANDLE;
    VK_TRY(vkCreateInstance(&instance_info, NULL, &instance), "vkCreateInstance");

    uint32_t physical_count = 0;
    VK_TRY(vkEnumeratePhysicalDevices(instance, &physical_count, NULL),
           "vkEnumeratePhysicalDevices(count)");
    REQUIRE(physical_count > 0, 2, "VULKAN_NO_PHYSICAL_DEVICES");

    VkPhysicalDevice *physical_devices =
        calloc(physical_count, sizeof(*physical_devices));
    REQUIRE(physical_devices != NULL, 2, "OUT_OF_MEMORY physical device list");
    VK_TRY(vkEnumeratePhysicalDevices(instance, &physical_count, physical_devices),
           "vkEnumeratePhysicalDevices(list)");

    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties base_properties;
    unsigned int matching_devices = 0;
    for (uint32_t i = 0; i < physical_count; ++i) {
        VkPhysicalDeviceProperties properties;
        vkGetPhysicalDeviceProperties(physical_devices[i], &properties);
        if (properties.vendorID == TARGET_VENDOR_ID &&
            properties.deviceID == TARGET_DEVICE_ID) {
            physical = physical_devices[i];
            base_properties = properties;
            ++matching_devices;
        }
    }
    free(physical_devices);

    if (matching_devices != 1 || physical == VK_NULL_HANDLE) {
        if (matching_devices == 0)
            fprintf(stderr, "GP107_NOT_FOUND pci_id=10de:1c82\\n");
        else
            fprintf(stderr, "GP107_AMBIGUOUS matching_devices=%u\\n",
                    matching_devices);
        return 2;
    }

    REQUIRE(has_device_extension(physical, VK_EXT_PCI_BUS_INFO_EXTENSION_NAME), 2,
            "PCI_IDENTITY_UNAVAILABLE missing=%s", VK_EXT_PCI_BUS_INFO_EXTENSION_NAME);
    REQUIRE(base_properties.apiVersion >= VK_API_VERSION_1_2 ||
            has_device_extension(physical, VK_KHR_DRIVER_PROPERTIES_EXTENSION_NAME), 2,
            "NVK_DRIVER_IDENTITY_UNAVAILABLE missing=%s",
            VK_KHR_DRIVER_PROPERTIES_EXTENSION_NAME);

    VkPhysicalDevicePCIBusInfoPropertiesEXT pci = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PCI_BUS_INFO_PROPERTIES_EXT
    };
    VkPhysicalDeviceDriverProperties driver = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES,
        .pNext = &pci
    };
    VkPhysicalDeviceProperties2 properties2 = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
        .pNext = &driver
    };
    vkGetPhysicalDeviceProperties2(physical, &properties2);

    PciBdf actual_bdf = {
        .domain = pci.pciDomain,
        .bus = pci.pciBus,
        .device = pci.pciDevice,
        .function = pci.pciFunction
    };
    REQUIRE(bdf_equal(&expected_bdf, &actual_bdf), 2,
            "PCI_BDF_MISMATCH expected=%04x:%02x:%02x.%x actual=%04x:%02x:%02x.%x",
            expected_bdf.domain, expected_bdf.bus, expected_bdf.device,
            expected_bdf.function, actual_bdf.domain, actual_bdf.bus,
            actual_bdf.device, actual_bdf.function);

    REQUIRE(driver.driverID == VK_DRIVER_ID_MESA_NVK, 2,
            "NVK_DRIVER_MISMATCH driverID=%d driverName=%s",
            (int)driver.driverID, driver.driverName);

    printf("GP107_IDENTITY_OK pci=10de:1c82 bdf=%04x:%02x:%02x.%x\n",
           actual_bdf.domain, actual_bdf.bus, actual_bdf.device,
           actual_bdf.function);
    printf("NVK_DEVICE name=%s driver=%s info=%s api=%u.%u.%u\n",
           base_properties.deviceName, driver.driverName, driver.driverInfo,
           VK_VERSION_MAJOR(base_properties.apiVersion),
           VK_VERSION_MINOR(base_properties.apiVersion),
           VK_VERSION_PATCH(base_properties.apiVersion));

    uint32_t queue_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(physical, &queue_count, NULL);
    VkQueueFamilyProperties *queue_properties =
        calloc(queue_count, sizeof(*queue_properties));
    REQUIRE(queue_count > 0 && queue_properties != NULL, 2,
            "QUEUE_FAMILY_ENUMERATION_FAILED");
    vkGetPhysicalDeviceQueueFamilyProperties(physical, &queue_count, queue_properties);

    uint32_t compute_family = UINT32_MAX;
    for (uint32_t i = 0; i < queue_count; ++i) {
        if (queue_properties[i].queueCount > 0 &&
            (queue_properties[i].queueFlags & VK_QUEUE_COMPUTE_BIT)) {
            compute_family = i;
            printf("QUEUE_FAMILY index=%u flags=0x%x count=%u compute=yes\n",
                   i, queue_properties[i].queueFlags, queue_properties[i].queueCount);
            break;
        }
    }
    free(queue_properties);
    REQUIRE(compute_family != UINT32_MAX, 2, "COMPUTE_QUEUE_NOT_FOUND");

    float priority = 1.0f;
    VkDeviceQueueCreateInfo queue_info = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = compute_family,
        .queueCount = 1,
        .pQueuePriorities = &priority
    };
    VkDeviceCreateInfo device_info = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queue_info
    };
    VkDevice device = VK_NULL_HANDLE;
    VK_TRY(vkCreateDevice(physical, &device_info, NULL, &device), "vkCreateDevice");
    VkQueue queue = VK_NULL_HANDLE;
    vkGetDeviceQueue(device, compute_family, 0, &queue);

    VkPhysicalDeviceMemoryProperties memory_properties;
    vkGetPhysicalDeviceMemoryProperties(physical, &memory_properties);

    const VkDeviceSize buffer_size = (VkDeviceSize)element_count * sizeof(uint32_t);
    HostBuffer input_a, input_b, output_c;
    VkResult result = create_host_buffer(device, &memory_properties, buffer_size, &input_a);
    REQUIRE(result == VK_SUCCESS, 2, "INPUT_A_BUFFER_FAILED VkResult=%d", (int)result);
    result = create_host_buffer(device, &memory_properties, buffer_size, &input_b);
    REQUIRE(result == VK_SUCCESS, 2, "INPUT_B_BUFFER_FAILED VkResult=%d", (int)result);
    result = create_host_buffer(device, &memory_properties, buffer_size, &output_c);
    REQUIRE(result == VK_SUCCESS, 2, "OUTPUT_BUFFER_FAILED VkResult=%d", (int)result);

    uint32_t *a = input_a.mapped;
    uint32_t *b = input_b.mapped;
    uint32_t *c = output_c.mapped;
    for (uint32_t i = 0; i < element_count; ++i) {
        a[i] = i * 17u + 1u;
        b[i] = i * 13u + 7u;
        c[i] = 0xdeadbeefu;
    }
    VK_TRY(sync_host_memory(device, &input_a, false), "flush input A");
    VK_TRY(sync_host_memory(device, &input_b, false), "flush input B");
    VK_TRY(sync_host_memory(device, &output_c, false), "flush output");

    VkDescriptorSetLayoutBinding bindings[3] = {0};
    for (uint32_t i = 0; i < 3; ++i) {
        bindings[i].binding = i;
        bindings[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        bindings[i].descriptorCount = 1;
        bindings[i].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    }
    VkDescriptorSetLayoutCreateInfo set_layout_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 3,
        .pBindings = bindings
    };
    VkDescriptorSetLayout set_layout = VK_NULL_HANDLE;
    VK_TRY(vkCreateDescriptorSetLayout(device, &set_layout_info, NULL, &set_layout),
           "vkCreateDescriptorSetLayout");

    VkPushConstantRange push_range = {
        .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
        .offset = 0,
        .size = sizeof(uint32_t)
    };
    VkPipelineLayoutCreateInfo pipeline_layout_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &set_layout,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_range
    };
    VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
    VK_TRY(vkCreatePipelineLayout(device, &pipeline_layout_info, NULL, &pipeline_layout),
           "vkCreatePipelineLayout");

    uint32_t *spirv_words = NULL;
    uint32_t spirv_word_count = read_spirv(spirv_path, &spirv_words);
    REQUIRE(spirv_word_count > 0 && spirv_words != NULL, 2,
            "SPIRV_LOAD_FAILED path=%s", spirv_path);
    VkShaderModuleCreateInfo shader_info = {
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = (size_t)spirv_word_count * sizeof(uint32_t),
        .pCode = spirv_words
    };
    VkShaderModule shader = VK_NULL_HANDLE;
    result = vkCreateShaderModule(device, &shader_info, NULL, &shader);
    free(spirv_words);
    REQUIRE(result == VK_SUCCESS, 2, "vkCreateShaderModule VkResult=%d", (int)result);

    VkPipelineShaderStageCreateInfo shader_stage = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = VK_SHADER_STAGE_COMPUTE_BIT,
        .module = shader,
        .pName = "main"
    };
    VkComputePipelineCreateInfo compute_info = {
        .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = shader_stage,
        .layout = pipeline_layout
    };
    VkPipeline pipeline = VK_NULL_HANDLE;
    result = vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &compute_info,
                                      NULL, &pipeline);
    REQUIRE(result == VK_SUCCESS, 2, "vkCreateComputePipelines VkResult=%d", (int)result);

    VkDescriptorPoolSize pool_size = {
        .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = 3
    };
    VkDescriptorPoolCreateInfo pool_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size
    };
    VkDescriptorPool descriptor_pool = VK_NULL_HANDLE;
    VK_TRY(vkCreateDescriptorPool(device, &pool_info, NULL, &descriptor_pool),
           "vkCreateDescriptorPool");

    VkDescriptorSetAllocateInfo set_alloc = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &set_layout
    };
    VkDescriptorSet descriptor_set = VK_NULL_HANDLE;
    VK_TRY(vkAllocateDescriptorSets(device, &set_alloc, &descriptor_set),
           "vkAllocateDescriptorSets");

    VkDescriptorBufferInfo buffer_infos[3] = {
        { .buffer = input_a.buffer, .offset = 0, .range = buffer_size },
        { .buffer = input_b.buffer, .offset = 0, .range = buffer_size },
        { .buffer = output_c.buffer, .offset = 0, .range = buffer_size }
    };
    VkWriteDescriptorSet writes[3] = {0};
    for (uint32_t i = 0; i < 3; ++i) {
        writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        writes[i].dstSet = descriptor_set;
        writes[i].dstBinding = i;
        writes[i].descriptorCount = 1;
        writes[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        writes[i].pBufferInfo = &buffer_infos[i];
    }
    vkUpdateDescriptorSets(device, 3, writes, 0, NULL);

    VkCommandPoolCreateInfo command_pool_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = compute_family
    };
    VkCommandPool command_pool = VK_NULL_HANDLE;
    VK_TRY(vkCreateCommandPool(device, &command_pool_info, NULL, &command_pool),
           "vkCreateCommandPool");

    VkCommandBufferAllocateInfo command_alloc = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1
    };
    VkCommandBuffer command_buffer = VK_NULL_HANDLE;
    VK_TRY(vkAllocateCommandBuffers(device, &command_alloc, &command_buffer),
           "vkAllocateCommandBuffers");

    VkCommandBufferBeginInfo begin_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
    };
    VK_TRY(vkBeginCommandBuffer(command_buffer, &begin_info), "vkBeginCommandBuffer");
    vkCmdBindPipeline(command_buffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(command_buffer, VK_PIPELINE_BIND_POINT_COMPUTE,
                            pipeline_layout, 0, 1, &descriptor_set, 0, NULL);
    vkCmdPushConstants(command_buffer, pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT,
                       0, sizeof(uint32_t), &element_count);
    vkCmdDispatch(command_buffer, (element_count + LOCAL_SIZE_X - 1u) / LOCAL_SIZE_X,
                  1, 1);

    VkBufferMemoryBarrier output_barrier = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT,
        .dstAccessMask = VK_ACCESS_HOST_READ_BIT,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .buffer = output_c.buffer,
        .offset = 0,
        .size = buffer_size
    };
    vkCmdPipelineBarrier(command_buffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                         VK_PIPELINE_STAGE_HOST_BIT, 0, 0, NULL,
                         1, &output_barrier, 0, NULL);
    VK_TRY(vkEndCommandBuffer(command_buffer), "vkEndCommandBuffer");

    VkFenceCreateInfo fence_info = {
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
    };
    VkFence fence = VK_NULL_HANDLE;
    VK_TRY(vkCreateFence(device, &fence_info, NULL, &fence), "vkCreateFence");

    VkSubmitInfo submit_info = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer
    };
    printf("NVK_COMPUTE_SUBMIT groups=%u elements=%u\n",
           (element_count + LOCAL_SIZE_X - 1u) / LOCAL_SIZE_X, element_count);
    VK_TRY(vkQueueSubmit(queue, 1, &submit_info, fence), "vkQueueSubmit");
    VK_TRY(vkWaitForFences(device, 1, &fence, VK_TRUE, 30000000000ull),
           "vkWaitForFences(timeout=30s)");
    VK_TRY(sync_host_memory(device, &output_c, true), "invalidate output");

    uint64_t expected_sum = 0;
    uint64_t observed_sum = 0;
    for (uint32_t i = 0; i < element_count; ++i) {
        uint32_t expected = (i * 17u + 1u) + (i * 13u + 7u);
        expected_sum += expected;
        observed_sum += c[i];
        if (c[i] != expected) {
            fprintf(stderr,
                    "VECTOR_ADD_MISMATCH index=%u expected=%u actual=%u\n",
                    i, expected, c[i]);
            return 3;
        }
    }
    REQUIRE(observed_sum == expected_sum, 3,
            "CPU_CHECKSUM_MISMATCH expected=%" PRIu64 " actual=%" PRIu64,
            expected_sum, observed_sum);

    printf("CPU_CHECKSUM_OK value=%" PRIu64 " elements=%u\n",
           observed_sum, element_count);
    printf("NVK_GP107_VECTOR_ADD_PASS\n");

    vkDestroyFence(device, fence, NULL);
    vkDestroyCommandPool(device, command_pool, NULL);
    vkDestroyDescriptorPool(device, descriptor_pool, NULL);
    vkDestroyPipeline(device, pipeline, NULL);
    vkDestroyShaderModule(device, shader, NULL);
    vkDestroyPipelineLayout(device, pipeline_layout, NULL);
    vkDestroyDescriptorSetLayout(device, set_layout, NULL);
    destroy_host_buffer(device, &output_c);
    destroy_host_buffer(device, &input_b);
    destroy_host_buffer(device, &input_a);
    vkDestroyDevice(device, NULL);
    vkDestroyInstance(instance, NULL);
    return 0;
}
