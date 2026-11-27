#define _POSIX_C_SOURCE 200809L
#include <vulkan/vulkan.h>

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GP107_VENDOR_ID 0x10deU
#define GP107_DEVICE_ID 0x1c82U
#define MAX_VECTOR_COUNT 1048576U
#define LOCAL_SIZE 64U
#define GP107_FIFO_NONSTALL_REVIEW_CLEARED 0
#define EXIT_NO_GP107_ENUMERATION 10
#define EXIT_GP107_IDENTITY_MISMATCH 11
#define EXIT_GP107_DRIVER_MISMATCH 12
#define EXIT_GP107_AMBIGUOUS 13
#define EXIT_GP107_BDF_UNVERIFIABLE 14

struct pci_bdf {
    unsigned int domain;
    unsigned int bus;
    unsigned int device;
    unsigned int function;
};

struct host_buffer {
    VkBuffer buffer;
    VkDeviceMemory memory;
    VkDeviceSize allocation_size;
    void *mapped;
    bool coherent;
};

#define VK_CHECK(call)                                                        \
    do {                                                                      \
        VkResult vk_result__ = (call);                                        \
        if (vk_result__ != VK_SUCCESS) {                                      \
            fprintf(stderr, "%s failed: VkResult=%d\n", #call, vk_result__);  \
            goto cleanup;                                                     \
        }                                                                     \
    } while (0)

static bool
parse_bdf(const char *text, struct pci_bdf *bdf)
{
    int consumed = 0;
    unsigned int domain = 0, bus = 0, device = 0, function = 0;

    if (sscanf(text, "%x:%x:%x.%x%n", &domain, &bus, &device, &function,
               &consumed) != 4 || text[consumed] != '\0')
        return false;

    if (domain > 0xffffU || bus > 0xffU || device > 0x1fU ||
        function > 0x7U)
        return false;

    bdf->domain = domain;
    bdf->bus = bus;
    bdf->device = device;
    bdf->function = function;
    return true;
}

static bool
contains_case_insensitive(const char *haystack, const char *needle)
{
    size_t needle_length = strlen(needle);

    if (needle_length == 0)
        return true;

    for (const char *p = haystack; *p != '\0'; p++) {
        size_t i = 0;

        while (i < needle_length && p[i] != '\0' &&
               tolower((unsigned char)p[i]) ==
                   tolower((unsigned char)needle[i]))
            i++;

        if (i == needle_length)
            return true;
    }

    return false;
}

static bool
device_extension_supported(VkPhysicalDevice physical_device,
                           const char *extension_name)
{
    uint32_t count = 0;
    VkExtensionProperties *properties = NULL;
    bool found = false;

    if (vkEnumerateDeviceExtensionProperties(physical_device, NULL, &count,
                                              NULL) != VK_SUCCESS ||
        count == 0)
        return false;

    properties = calloc(count, sizeof(*properties));
    if (properties == NULL)
        return false;

    if (vkEnumerateDeviceExtensionProperties(physical_device, NULL, &count,
                                              properties) == VK_SUCCESS) {
        for (uint32_t i = 0; i < count; i++) {
            if (strcmp(properties[i].extensionName, extension_name) == 0) {
                found = true;
                break;
            }
        }
    }

    free(properties);
    return found;
}

static bool
same_bdf(const VkPhysicalDevicePCIBusInfoPropertiesEXT *pci,
         const struct pci_bdf *expected)
{
    return pci->pciDomain == expected->domain &&
           pci->pciBus == expected->bus &&
           pci->pciDevice == expected->device &&
           pci->pciFunction == expected->function;
}

static int
find_gp107(VkInstance instance, const struct pci_bdf *expected,
           VkPhysicalDevice *selected,
           VkPhysicalDeviceProperties *selected_properties,
           VkPhysicalDeviceDriverProperties *selected_driver,
           VkPhysicalDevicePCIBusInfoPropertiesEXT *selected_pci)
{
    uint32_t count = 0;
    VkPhysicalDevice *devices = NULL;
    int pci_id_matches = 0;
    int bdf_matches = 0;
    int matches = 0;
    bool driver_mismatch = false;
    bool pci_info_unavailable = false;

    VkResult result = vkEnumeratePhysicalDevices(instance, &count, NULL);
    if (result != VK_SUCCESS) {
        fprintf(stderr, "vkEnumeratePhysicalDevices failed: %d\n", result);
        return -1;
    }
    if (count == 0) {
        fprintf(stderr, "NO_GP107_ENUMERATED: no Vulkan physical devices.\n");
        return EXIT_NO_GP107_ENUMERATION;
    }

    devices = calloc(count, sizeof(*devices));
    if (devices == NULL) {
        fprintf(stderr, "Out of memory enumerating Vulkan devices.\n");
        return -1;
    }

    result = vkEnumeratePhysicalDevices(instance, &count, devices);
    if (result != VK_SUCCESS) {
        fprintf(stderr, "vkEnumeratePhysicalDevices failed: %d\n", result);
        free(devices);
        return -1;
    }

    for (uint32_t i = 0; i < count; i++) {
        VkPhysicalDeviceProperties basic_properties;
        VkPhysicalDeviceProperties2 properties2 = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2
        };
        VkPhysicalDeviceDriverProperties driver = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES
        };
        VkPhysicalDevicePCIBusInfoPropertiesEXT pci = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PCI_BUS_INFO_PROPERTIES_EXT
        };

        vkGetPhysicalDeviceProperties(devices[i], &basic_properties);
        if (basic_properties.vendorID != GP107_VENDOR_ID ||
            basic_properties.deviceID != GP107_DEVICE_ID)
            continue;

        pci_id_matches++;

        if (!device_extension_supported(devices[i],
                                        VK_EXT_PCI_BUS_INFO_EXTENSION_NAME)) {
            pci_info_unavailable = true;
            continue;
        }

        pci.pNext = NULL;
        driver.pNext = &pci;
        properties2.pNext = &driver;
        vkGetPhysicalDeviceProperties2(devices[i], &properties2);

        if (!same_bdf(&pci, expected))
            continue;

        bdf_matches++;

        if (!contains_case_insensitive(driver.driverName, "nvk") &&
            !contains_case_insensitive(driver.driverName, "nouveau")) {
            driver_mismatch = true;
            fprintf(stderr,
                    "GP107 PCI target matched, but Vulkan driver is not NVK/Nouveau: %s\n",
                    driver.driverName);
            continue;
        }

        matches++;
        *selected = devices[i];
        *selected_properties = properties2.properties;
        *selected_driver = driver;
        *selected_pci = pci;
    }

    free(devices);

    if (matches == 1)
        return 0;
    if (matches > 1)
        return EXIT_GP107_AMBIGUOUS;
    if (pci_id_matches == 0) {
        fprintf(stderr, "NO_GP107_ENUMERATED: Vulkan did not expose PCI 10de:1c82.\n");
        return EXIT_NO_GP107_ENUMERATION;
    }
    if (bdf_matches == 0) {
        if (pci_info_unavailable) {
            fprintf(stderr,
                    "GP107 PCI ID enumerated, but VK_EXT_pci_bus_info is "
                    "unavailable; exact BDF cannot be proven.\n");
            return EXIT_GP107_BDF_UNVERIFIABLE;
        }
        fprintf(stderr,
                "GP107 vendor/device found, but VK_EXT_pci_bus_info did not "
                "confirm requested BDF.\n");
        return EXIT_GP107_IDENTITY_MISMATCH;
    }
    if (driver_mismatch)
        return EXIT_GP107_DRIVER_MISMATCH;

    return EXIT_GP107_AMBIGUOUS;
}

static int
find_host_memory_type(const VkPhysicalDeviceMemoryProperties *memory,
                      uint32_t allowed_types, uint32_t *type_index,
                      bool *coherent)
{
    int best_score = -1;
    uint32_t best_type = UINT32_MAX;
    bool best_coherent = false;

    for (uint32_t i = 0; i < memory->memoryTypeCount; i++) {
        VkMemoryPropertyFlags flags = memory->memoryTypes[i].propertyFlags;
        int score = 0;

        if ((allowed_types & (1U << i)) == 0 ||
            (flags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) == 0)
            continue;

        if (flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)
            score += 4;
        if (flags & VK_MEMORY_PROPERTY_HOST_CACHED_BIT)
            score += 2;
        if (flags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
            score += 1;

        if (score > best_score) {
            best_score = score;
            best_type = i;
            best_coherent =
                (flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) != 0;
        }
    }

    if (best_type == UINT32_MAX)
        return -1;

    *type_index = best_type;
    *coherent = best_coherent;
    return 0;
}

static void
destroy_host_buffer(VkDevice device, struct host_buffer *buffer)
{
    if (buffer->mapped != NULL && buffer->memory != VK_NULL_HANDLE)
        vkUnmapMemory(device, buffer->memory);
    if (buffer->buffer != VK_NULL_HANDLE)
        vkDestroyBuffer(device, buffer->buffer, NULL);
    if (buffer->memory != VK_NULL_HANDLE)
        vkFreeMemory(device, buffer->memory, NULL);

    memset(buffer, 0, sizeof(*buffer));
}

static int
create_host_buffer(VkDevice device,
                   const VkPhysicalDeviceMemoryProperties *memory_properties,
                   VkDeviceSize size, struct host_buffer *buffer)
{
    VkBufferCreateInfo buffer_info = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE
    };
    VkMemoryRequirements requirements;
    VkMemoryAllocateInfo allocation_info = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
    };
    uint32_t memory_type = UINT32_MAX;
    VkResult result;

    memset(buffer, 0, sizeof(*buffer));

    result = vkCreateBuffer(device, &buffer_info, NULL, &buffer->buffer);
    if (result != VK_SUCCESS) {
        fprintf(stderr, "vkCreateBuffer failed: %d\n", result);
        return -1;
    }

    vkGetBufferMemoryRequirements(device, buffer->buffer, &requirements);

    if (find_host_memory_type(memory_properties,
                              requirements.memoryTypeBits, &memory_type,
                              &buffer->coherent) != 0) {
        fprintf(stderr,
                "No HOST_VISIBLE Vulkan memory type for storage buffer.\n");
        destroy_host_buffer(device, buffer);
        return -1;
    }

    allocation_info.allocationSize = requirements.size;
    allocation_info.memoryTypeIndex = memory_type;

    result = vkAllocateMemory(device, &allocation_info, NULL, &buffer->memory);
    if (result != VK_SUCCESS) {
        fprintf(stderr, "vkAllocateMemory failed: %d\n", result);
        destroy_host_buffer(device, buffer);
        return -1;
    }

    result = vkBindBufferMemory(device, buffer->buffer, buffer->memory, 0);
    if (result != VK_SUCCESS) {
        fprintf(stderr, "vkBindBufferMemory failed: %d\n", result);
        destroy_host_buffer(device, buffer);
        return -1;
    }

    buffer->allocation_size = requirements.size;
    result = vkMapMemory(device, buffer->memory, 0, VK_WHOLE_SIZE, 0,
                         &buffer->mapped);
    if (result != VK_SUCCESS) {
        fprintf(stderr, "vkMapMemory failed: %d\n", result);
        destroy_host_buffer(device, buffer);
        return -1;
    }

    return 0;
}

static VkResult
flush_host_buffer(VkDevice device, const struct host_buffer *buffer)
{
    VkMappedMemoryRange range = {
        .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
        .memory = buffer->memory,
        .offset = 0,
        .size = VK_WHOLE_SIZE
    };

    if (buffer->coherent)
        return VK_SUCCESS;

    return vkFlushMappedMemoryRanges(device, 1, &range);
}

static VkResult
invalidate_host_buffer(VkDevice device, const struct host_buffer *buffer)
{
    VkMappedMemoryRange range = {
        .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
        .memory = buffer->memory,
        .offset = 0,
        .size = VK_WHOLE_SIZE
    };

    if (buffer->coherent)
        return VK_SUCCESS;

    return vkInvalidateMappedMemoryRanges(device, 1, &range);
}

static uint32_t *
load_spirv(const char *path, size_t *byte_count)
{
    FILE *file = fopen(path, "rb");
    uint32_t *code = NULL;
    long length;

    if (file == NULL) {
        fprintf(stderr, "Cannot open SPIR-V file %s: %s\n", path,
                strerror(errno));
        return NULL;
    }

    if (fseek(file, 0, SEEK_END) != 0 ||
        (length = ftell(file)) <= 0 ||
        fseek(file, 0, SEEK_SET) != 0) {
        fprintf(stderr, "Cannot determine SPIR-V file size: %s\n", path);
        fclose(file);
        return NULL;
    }

    if ((length % (long)sizeof(uint32_t)) != 0) {
        fprintf(stderr, "SPIR-V byte size is not a multiple of 4: %s\n", path);
        fclose(file);
        return NULL;
    }

    code = malloc((size_t)length);
    if (code == NULL) {
        fprintf(stderr, "Out of memory loading SPIR-V.\n");
        fclose(file);
        return NULL;
    }

    if (fread(code, 1, (size_t)length, file) != (size_t)length) {
        fprintf(stderr, "Short read from SPIR-V file: %s\n", path);
        free(code);
        fclose(file);
        return NULL;
    }

    fclose(file);

    if (code[0] != 0x07230203U) {
        fprintf(stderr, "Invalid SPIR-V magic: %s\n", path);
        free(code);
        return NULL;
    }

    *byte_count = (size_t)length;
    return code;
}

static void
print_usage(const char *program)
{
    printf("Usage: %s --bdf DOMAIN:BUS:DEVICE.FUNCTION "
           "(--enumerate-only | --experimental-enumeration-only | --dispatch --spirv FILE)\n",
           program);
    printf("Requires PCI 10de:1c82, VK_EXT_pci_bus_info, and an NVK/Nouveau driver.\n");
    printf("Dispatch stays disabled in source until the GP107 FIFO issue #18 gate is cleared.\n");
}

int
main(int argc, char **argv)
{
    const char *bdf_text = NULL;
    const char *spirv_path = NULL;
    bool enumerate_only = false;
    bool experimental_enumeration_only = false;
    bool dispatch = false;
    struct pci_bdf expected_bdf;
    VkInstance instance = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    VkCommandPool command_pool = VK_NULL_HANDLE;
    VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    VkShaderModule shader_module = VK_NULL_HANDLE;
    VkDescriptorSetLayout descriptor_layout = VK_NULL_HANDLE;
    VkDescriptorPool descriptor_pool = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;
    VkPhysicalDevice physical_device = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties physical_properties;
    VkPhysicalDeviceDriverProperties driver_properties;
    VkPhysicalDevicePCIBusInfoPropertiesEXT pci_properties;
    VkPhysicalDeviceMemoryProperties memory_properties;
    VkCommandBuffer command_buffer = VK_NULL_HANDLE;
    struct host_buffer input_a = {0}, input_b = {0}, output = {0};
    uint32_t *spirv = NULL;
    size_t spirv_size = 0;
    uint32_t queue_family_index = UINT32_MAX;
    uint32_t queue_family_count = 0;
    VkQueueFlags selected_queue_flags = 0;
    VkQueueFamilyProperties *queue_families = NULL;
    uint32_t api_version = VK_API_VERSION_1_0;
    int status = EXIT_FAILURE;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return EXIT_SUCCESS;
        } else if (strcmp(argv[i], "--bdf") == 0 && i + 1 < argc) {
            bdf_text = argv[++i];
        } else if (strcmp(argv[i], "--spirv") == 0 && i + 1 < argc) {
            spirv_path = argv[++i];
        } else if (strcmp(argv[i], "--enumerate-only") == 0) {
            enumerate_only = true;
        } else if (strcmp(argv[i], "--experimental-enumeration-only") == 0) {
            enumerate_only = true;
            experimental_enumeration_only = true;
        } else if (strcmp(argv[i], "--dispatch") == 0) {
            dispatch = true;
        } else {
            print_usage(argv[0]);
            return EXIT_FAILURE;
        }
    }

    if (bdf_text == NULL || !parse_bdf(bdf_text, &expected_bdf) ||
        (enumerate_only && dispatch) || (!enumerate_only && !dispatch) ||
        (dispatch && spirv_path == NULL)) {
        print_usage(argv[0]);
        fprintf(stderr, "Select exactly one mode; a SPIR-V path is required for dispatch.\n");
        return EXIT_FAILURE;
    }

    {
        const char *override = getenv("NVK_I_WANT_A_BROKEN_VULKAN_DRIVER");
        bool override_enabled = override != NULL && strcmp(override, "0") != 0;
        if (override_enabled != experimental_enumeration_only) {
            fprintf(stderr,
                    "The experimental enumeration mode and "
                    "NVK_I_WANT_A_BROKEN_VULKAN_DRIVER must be used together.\n");
            return EXIT_FAILURE;
        }
    }

    if (vkEnumerateInstanceVersion(&api_version) != VK_SUCCESS ||
        api_version < VK_API_VERSION_1_2) {
        fprintf(stderr, "Vulkan loader 1.2 or newer is required.\n");
        return EXIT_FAILURE;
    }

    {
        VkApplicationInfo app = {
            .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "GP107 NVK vector-add witness",
            .applicationVersion = 1,
            .pEngineName = "gp107-nvidia-re",
            .engineVersion = 1,
            .apiVersion = VK_API_VERSION_1_2
        };
        VkInstanceCreateInfo create_info = {
            .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &app
        };

        VK_CHECK(vkCreateInstance(&create_info, NULL, &instance));
    }

    {
        int find_result = find_gp107(instance, &expected_bdf, &physical_device,
                                     &physical_properties, &driver_properties,
                                     &pci_properties);
        if (find_result != 0) {
            status = find_result;
            goto cleanup;
        }
    }

    if (physical_properties.apiVersion < VK_API_VERSION_1_2) {
        fprintf(stderr, "GP107 NVK device does not expose Vulkan 1.2 or newer.\n");
        goto cleanup;
    }

    printf("DEVICE: %s\n", physical_properties.deviceName);
    printf("PCI: %04x:%02x:%02x.%x vendor=%04x device=%04x\n",
           pci_properties.pciDomain, pci_properties.pciBus,
           pci_properties.pciDevice, pci_properties.pciFunction,
           physical_properties.vendorID, physical_properties.deviceID);
    printf("DRIVER: %s | %s\n", driver_properties.driverName,
           driver_properties.driverInfo);
    printf("VULKAN_API: %u.%u.%u\n",
           VK_VERSION_MAJOR(physical_properties.apiVersion),
           VK_VERSION_MINOR(physical_properties.apiVersion),
           VK_VERSION_PATCH(physical_properties.apiVersion));
    printf("BDF-ASSERTION: PASS (10de:1c82 at %04x:%02x:%02x.%x)\n",
           pci_properties.pciDomain, pci_properties.pciBus,
           pci_properties.pciDevice, pci_properties.pciFunction);

    if (experimental_enumeration_only) {
        printf("EXPERIMENTAL_ENUMERATION_ONLY: PASS\n");
        status = EXIT_SUCCESS;
        goto cleanup;
    }
    if (enumerate_only) {
        printf("ENUMERATION-ONLY: PASS\n");
        status = EXIT_SUCCESS;
        goto cleanup;
    }

    if (!GP107_FIFO_NONSTALL_REVIEW_CLEARED) {
        fprintf(stderr,
                "GPU-DISPATCH-BLOCKED: resolve issue #18 and record the GP107 "
                "GR/compute TOP runlist witness before enabling dispatch.\n");
        status = 78;
        goto cleanup;
    }

    spirv = load_spirv(spirv_path, &spirv_size);
    if (spirv == NULL)
        goto cleanup;

    vkGetPhysicalDeviceMemoryProperties(physical_device, &memory_properties);
    vkGetPhysicalDeviceQueueFamilyProperties(physical_device,
                                              &queue_family_count, NULL);
    if (queue_family_count == 0) {
        fprintf(stderr, "GP107 exposes no Vulkan queue families.\n");
        goto cleanup;
    }

    queue_families = calloc(queue_family_count, sizeof(*queue_families));
    if (queue_families == NULL) {
        fprintf(stderr, "Out of memory enumerating queue families.\n");
        goto cleanup;
    }

    vkGetPhysicalDeviceQueueFamilyProperties(physical_device,
                                              &queue_family_count,
                                              queue_families);
    for (uint32_t i = 0; i < queue_family_count; i++) {
        printf("QUEUE_FAMILY: index=%u count=%u flags=0x%x\\n",
               i, queue_families[i].queueCount,
               queue_families[i].queueFlags);
        if (queue_family_index == UINT32_MAX &&
            queue_families[i].queueCount > 0 &&
            (queue_families[i].queueFlags & VK_QUEUE_COMPUTE_BIT)) {
            queue_family_index = i;
            selected_queue_flags = queue_families[i].queueFlags;
        }
    }
    free(queue_families);
    queue_families = NULL;

    if (queue_family_index == UINT32_MAX) {
        fprintf(stderr, "GP107 NVK exposes no compute queue family.\n");
        goto cleanup;
    }

    printf("COMPUTE_QUEUE: family=%u flags=0x%x\n", queue_family_index,
           selected_queue_flags);

    {
        const float priority = 1.0f;
        VkDeviceQueueCreateInfo queue_info = {
            .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = queue_family_index,
            .queueCount = 1,
            .pQueuePriorities = &priority
        };
        VkDeviceCreateInfo device_info = {
            .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = &queue_info
        };

        VK_CHECK(vkCreateDevice(physical_device, &device_info, NULL, &device));
    }
    vkGetDeviceQueue(device, queue_family_index, 0, &queue);

    {
        VkDescriptorSetLayoutBinding bindings[3] = {
            {
                .binding = 0,
                .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount = 1,
                .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT
            },
            {
                .binding = 1,
                .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount = 1,
                .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT
            },
            {
                .binding = 2,
                .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount = 1,
                .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT
            }
        };
        VkDescriptorSetLayoutCreateInfo layout_info = {
            .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = 3,
            .pBindings = bindings
        };

        VK_CHECK(vkCreateDescriptorSetLayout(device, &layout_info, NULL,
                                              &descriptor_layout));
    }

    {
        VkPushConstantRange push_range = {
            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
            .offset = 0,
            .size = sizeof(uint32_t)
        };
        VkPipelineLayoutCreateInfo layout_info = {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 1,
            .pSetLayouts = &descriptor_layout,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &push_range
        };

        VK_CHECK(vkCreatePipelineLayout(device, &layout_info, NULL,
                                         &pipeline_layout));
    }

    {
        VkShaderModuleCreateInfo shader_info = {
            .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = spirv_size,
            .pCode = spirv
        };
        VK_CHECK(vkCreateShaderModule(device, &shader_info, NULL,
                                      &shader_module));
    }

    {
        VkPipelineShaderStageCreateInfo stage = {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_COMPUTE_BIT,
            .module = shader_module,
            .pName = "main"
        };
        VkComputePipelineCreateInfo pipeline_info = {
            .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
            .stage = stage,
            .layout = pipeline_layout
        };

        VK_CHECK(vkCreateComputePipelines(device, VK_NULL_HANDLE, 1,
                                           &pipeline_info, NULL, &pipeline));
    }

    {
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
        VK_CHECK(vkCreateDescriptorPool(device, &pool_info, NULL,
                                         &descriptor_pool));
    }

    {
        VkDescriptorSetAllocateInfo set_info = {
            .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = descriptor_pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &descriptor_layout
        };
        VkDescriptorSet descriptor_set = VK_NULL_HANDLE;
        VkDescriptorBufferInfo buffer_infos[3];
        VkWriteDescriptorSet writes[3];

        VkDeviceSize buffer_size =
            (VkDeviceSize)MAX_VECTOR_COUNT * sizeof(uint32_t);

        if (create_host_buffer(device, &memory_properties, buffer_size,
                               &input_a) != 0 ||
            create_host_buffer(device, &memory_properties, buffer_size,
                               &input_b) != 0 ||
            create_host_buffer(device, &memory_properties, buffer_size,
                               &output) != 0)
            goto cleanup;

        uint32_t *a = input_a.mapped;
        uint32_t *b = input_b.mapped;
        uint32_t *c = output.mapped;

        VK_CHECK(vkAllocateDescriptorSets(device, &set_info, &descriptor_set));

        buffer_infos[0] = (VkDescriptorBufferInfo) {
            .buffer = input_a.buffer, .offset = 0, .range = buffer_size
        };
        buffer_infos[1] = (VkDescriptorBufferInfo) {
            .buffer = input_b.buffer, .offset = 0, .range = buffer_size
        };
        buffer_infos[2] = (VkDescriptorBufferInfo) {
            .buffer = output.buffer, .offset = 0, .range = buffer_size
        };

        memset(writes, 0, sizeof(writes));
        for (uint32_t i = 0; i < 3; i++) {
            writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[i].dstSet = descriptor_set;
            writes[i].dstBinding = i;
            writes[i].descriptorCount = 1;
            writes[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            writes[i].pBufferInfo = &buffer_infos[i];
        }
        vkUpdateDescriptorSets(device, 3, writes, 0, NULL);

        {
            VkCommandPoolCreateInfo pool_info = {
                .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                .flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT |
                         VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
                .queueFamilyIndex = queue_family_index
            };
            VK_CHECK(vkCreateCommandPool(device, &pool_info, NULL,
                                          &command_pool));
        }

        {
            VkCommandBufferAllocateInfo command_info = {
                .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                .commandPool = command_pool,
                .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                .commandBufferCount = 1
            };
            VK_CHECK(vkAllocateCommandBuffers(device, &command_info,
                                               &command_buffer));
        }

        {
            const uint32_t test_counts[] = {257U, 1048576U};

            for (size_t test_index = 0;
                 test_index < sizeof(test_counts) / sizeof(test_counts[0]);
                 test_index++) {
                uint32_t count = test_counts[test_index];
                uint32_t groups = (count + LOCAL_SIZE - 1U) / LOCAL_SIZE;
                VkCommandBufferBeginInfo begin_info = {
                    .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                    .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
                };
                VkFenceCreateInfo fence_info = {
                    .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
                };
                VkSubmitInfo submit_info = {
                    .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                    .commandBufferCount = 1,
                    .pCommandBuffers = &command_buffer
                };
                VkBufferMemoryBarrier barrier;
                uint64_t checksum = 0;
                uint64_t expected_checksum = 0;

                if (test_index > 0)
                    VK_CHECK(vkResetCommandBuffer(command_buffer, 0));

                for (uint32_t i = 0; i < count; i++) {
                    a[i] = (i * 17U + 3U) % 10007U;
                    b[i] = (i * 29U + 7U) % 10009U;
                    c[i] = 0;
                }
                VK_CHECK(flush_host_buffer(device, &input_a));
                VK_CHECK(flush_host_buffer(device, &input_b));
                VK_CHECK(vkBeginCommandBuffer(command_buffer, &begin_info));

                vkCmdBindPipeline(command_buffer, VK_PIPELINE_BIND_POINT_COMPUTE,
                                  pipeline);
                vkCmdBindDescriptorSets(command_buffer,
                                        VK_PIPELINE_BIND_POINT_COMPUTE,
                                        pipeline_layout, 0, 1, &descriptor_set,
                                        0, NULL);
                vkCmdPushConstants(command_buffer, pipeline_layout,
                                   VK_SHADER_STAGE_COMPUTE_BIT, 0,
                                   sizeof(count), &count);
                vkCmdDispatch(command_buffer, groups, 1, 1);

                memset(&barrier, 0, sizeof(barrier));
                barrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
                barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
                barrier.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
                barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
                barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
                barrier.buffer = output.buffer;
                barrier.offset = 0;
                barrier.size = (VkDeviceSize)count * sizeof(uint32_t);
                vkCmdPipelineBarrier(command_buffer,
                                     VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                                     VK_PIPELINE_STAGE_HOST_BIT,
                                     0, 0, NULL, 1, &barrier, 0, NULL);

                VK_CHECK(vkEndCommandBuffer(command_buffer));
                VK_CHECK(vkCreateFence(device, &fence_info, NULL, &fence));
                VK_CHECK(vkQueueSubmit(queue, 1, &submit_info, fence));
                VK_CHECK(vkWaitForFences(device, 1, &fence, VK_TRUE,
                                         UINT64_C(60000000000)));
                vkDestroyFence(device, fence, NULL);
                fence = VK_NULL_HANDLE;

                VK_CHECK(invalidate_host_buffer(device, &output));

                for (uint32_t i = 0; i < count; i++) {
                    uint32_t expected = a[i] + b[i];

                    if (c[i] != expected) {
                        fprintf(stderr,
                                "MISMATCH count=%u index=%u expected=%u actual=%u\n",
                                count, i, expected, c[i]);
                        goto cleanup;
                    }
                    checksum += c[i];
                    expected_checksum += expected;
                }

                if (checksum != expected_checksum) {
                    fprintf(stderr,
                            "CPU checksum mismatch count=%u expected=%" PRIu64
                            " actual=%" PRIu64 "\n",
                            count, expected_checksum, checksum);
                    goto cleanup;
                }

                printf("COMPUTE_CASE: PASS elements=%u groups=%u "
                       "fence=signaled cpu_checksum=%" PRIu64 "\n",
                       count, groups, checksum);
            }
        }

        printf("GPU-COMPUTE: PASS cases=2\n");
    }

    status = EXIT_SUCCESS;

cleanup:
    if (device != VK_NULL_HANDLE) {
        if (fence != VK_NULL_HANDLE)
            vkDestroyFence(device, fence, NULL);
        if (command_pool != VK_NULL_HANDLE)
            vkDestroyCommandPool(device, command_pool, NULL);
        if (descriptor_pool != VK_NULL_HANDLE)
            vkDestroyDescriptorPool(device, descriptor_pool, NULL);
        if (pipeline != VK_NULL_HANDLE)
            vkDestroyPipeline(device, pipeline, NULL);
        if (shader_module != VK_NULL_HANDLE)
            vkDestroyShaderModule(device, shader_module, NULL);
        if (pipeline_layout != VK_NULL_HANDLE)
            vkDestroyPipelineLayout(device, pipeline_layout, NULL);
        if (descriptor_layout != VK_NULL_HANDLE)
            vkDestroyDescriptorSetLayout(device, descriptor_layout, NULL);

        destroy_host_buffer(device, &output);
        destroy_host_buffer(device, &input_b);
        destroy_host_buffer(device, &input_a);
        vkDestroyDevice(device, NULL);
    }

    if (instance != VK_NULL_HANDLE)
        vkDestroyInstance(instance, NULL);

    free(queue_families);
    free(spirv);
    return status;
}
