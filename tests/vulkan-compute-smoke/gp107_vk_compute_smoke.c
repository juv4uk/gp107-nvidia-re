#define _GNU_SOURCE
#include <vulkan/vulkan.h>

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GP107_VENDOR_ID 0x10deu
#define GP107_DEVICE_ID 0x1c82u
#define ITEM_COUNT 4096u
#define LOCAL_SIZE 64u
#define NOT_AVAILABLE 77

static int
parse_bdf(const char *text, uint32_t *domain, uint32_t *bus,
          uint32_t *device, uint32_t *function)
{
    unsigned int d, b, dev, fn;
    int consumed = 0;

    if (!text || sscanf(text, "%x:%x:%x.%x%n", &d, &b, &dev, &fn,
                        &consumed) != 4 || text[consumed] != '\0')
        return 0;

    if (d > 0xffffu || b > 0xffu || dev > 0x1fu || fn > 7u)
        return 0;

    *domain = d;
    *bus = b;
    *device = dev;
    *function = fn;
    return 1;
}

static int
contains_nvk_name(const char *text)
{
    char lower[VK_MAX_DRIVER_NAME_SIZE];
    size_t i;

    if (!text || !text[0])
        return 0;

    for (i = 0; i + 1 < sizeof(lower) && text[i]; i++)
        lower[i] = (char)tolower((unsigned char)text[i]);
    lower[i] = '\0';

    return strstr(lower, "nvk") != NULL ||
           strstr(lower, "nouveau") != NULL;
}

static int
has_device_extension(VkPhysicalDevice physical, const char *extension_name)
{
    VkExtensionProperties *extensions = NULL;
    uint32_t count = 0;
    uint32_t i;
    VkResult result;
    int found = 0;

    result = vkEnumerateDeviceExtensionProperties(physical, NULL, &count,
                                                   NULL);
    if (result != VK_SUCCESS)
        return -1;

    if (!count)
        return 0;

    extensions = calloc(count, sizeof(*extensions));
    if (!extensions)
        return -1;

    result = vkEnumerateDeviceExtensionProperties(physical, NULL, &count,
                                                   extensions);
    if (result != VK_SUCCESS) {
        free(extensions);
        return -1;
    }

    for (i = 0; i < count; i++) {
        if (strcmp(extensions[i].extensionName, extension_name) == 0) {
            found = 1;
            break;
        }
    }

    free(extensions);
    return found;
}

static int
load_spirv(const char *path, uint32_t **words_out, size_t *size_out)
{
    FILE *file;
    long length;
    uint32_t *words;

    file = fopen(path, "rb");
    if (!file) {
        fprintf(stderr, "GP107-VK-COMPUTE-FAIL step=open-spv errno=%d\n",
                errno);
        return 0;
    }

    if (fseek(file, 0, SEEK_END) != 0 ||
        (length = ftell(file)) <= 0 ||
        fseek(file, 0, SEEK_SET) != 0) {
        fprintf(stderr, "GP107-VK-COMPUTE-FAIL step=read-spv reason=bad-size\n");
        fclose(file);
        return 0;
    }

    if ((length % 4) != 0 || (unsigned long)length > SIZE_MAX) {
        fprintf(stderr, "GP107-VK-COMPUTE-FAIL step=read-spv reason=unaligned-size\n");
        fclose(file);
        return 0;
    }

    words = malloc((size_t)length);
    if (!words) {
        fprintf(stderr, "GP107-VK-COMPUTE-FAIL step=read-spv reason=out-of-memory\n");
        fclose(file);
        return 0;
    }

    if (fread(words, 1, (size_t)length, file) != (size_t)length) {
        fprintf(stderr, "GP107-VK-COMPUTE-FAIL step=read-spv reason=short-read\n");
        free(words);
        fclose(file);
        return 0;
    }

    fclose(file);

    if (words[0] != 0x07230203u) {
        fprintf(stderr, "GP107-VK-COMPUTE-FAIL step=read-spv reason=bad-magic\n");
        free(words);
        return 0;
    }

    *words_out = words;
    *size_out = (size_t)length;
    return 1;
}

static int
choose_memory_type(const VkPhysicalDeviceMemoryProperties *memory_properties,
                   uint32_t allowed_bits, uint32_t *type_index,
                   int *host_coherent)
{
    int best_score = -1;
    uint32_t i;

    for (i = 0; i < memory_properties->memoryTypeCount; i++) {
        VkMemoryPropertyFlags flags;
        int score = 0;

        if (!(allowed_bits & (1u << i)))
            continue;

        flags = memory_properties->memoryTypes[i].propertyFlags;
        if (!(flags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT))
            continue;

        if (flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)
            score += 4;
        if (flags & VK_MEMORY_PROPERTY_HOST_CACHED_BIT)
            score += 2;

        if (score > best_score) {
            best_score = score;
            *type_index = i;
            *host_coherent =
                (flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) != 0;
        }
    }

    return best_score >= 0;
}

int
main(int argc, char **argv)
{
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    VkBuffer buffer = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkDescriptorSetLayout descriptor_layout = VK_NULL_HANDLE;
    VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
    VkDescriptorPool descriptor_pool = VK_NULL_HANDLE;
    VkShaderModule shader_module = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    VkCommandPool command_pool = VK_NULL_HANDLE;
    VkCommandBuffer command_buffer = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;
    void *mapped = NULL;
    uint32_t *spirv = NULL;
    size_t spirv_size = 0;
    VkPhysicalDeviceProperties physical_properties;
    VkPhysicalDeviceDriverProperties driver_properties;
    VkPhysicalDeviceMemoryProperties memory_properties;
    VkQueueFamilyProperties *queue_families = NULL;
    uint32_t queue_family = UINT32_MAX;
    uint32_t queue_family_count = 0;
    uint32_t memory_type_index = 0;
    int host_coherent = 0;
    VkDeviceSize data_bytes = (VkDeviceSize)ITEM_COUNT * sizeof(uint32_t);
    VkDeviceSize alignment;
    VkDeviceSize stride;
    VkDeviceSize buffer_size;
    uint32_t group_count = (ITEM_COUNT + LOCAL_SIZE - 1u) / LOCAL_SIZE;
    uint32_t i;
    uint64_t checksum = 0;
    int exit_code = 1;
    VkResult vr;
    const char *expected_bdf;
    const char *spirv_path;

    if (argc != 2) {
        fprintf(stderr,
                "usage: GP107_EXPECTED_BDF=dddd:bb:dd.f %s vector_add.comp.spv\n",
                argv[0]);
        return 64;
    }

    expected_bdf = getenv("GP107_EXPECTED_BDF");
    spirv_path = argv[1];

    if (!expected_bdf || !expected_bdf[0]) {
        fprintf(stderr,
                "GP107-VK-COMPUTE-NOT-AVAILABLE reason=missing-GP107_EXPECTED_BDF\n");
        return NOT_AVAILABLE;
    }

    if (!load_spirv(spirv_path, &spirv, &spirv_size))
        return 1;

    {
        VkApplicationInfo app = {
            .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "gp107-vulkan-compute-smoke",
            .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "none",
            .engineVersion = VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = VK_API_VERSION_1_2
        };
        VkInstanceCreateInfo create = {
            .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &app
        };

        vr = vkCreateInstance(&create, NULL, &instance);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-NOT-AVAILABLE step=create-instance vkResult=%d\n",
                    (int)vr);
            exit_code = NOT_AVAILABLE;
            goto cleanup;
        }
    }

    {
        VkPhysicalDevice *physical_devices = NULL;
        uint32_t physical_count = 0;
        uint32_t found_count = 0;
        uint32_t expected_domain, expected_bus, expected_device, expected_fn;

        if (!parse_bdf(expected_bdf, &expected_domain, &expected_bus,
                       &expected_device, &expected_fn)) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=parse-bdf value=%s\n",
                    expected_bdf);
            goto cleanup;
        }

        vr = vkEnumeratePhysicalDevices(instance, &physical_count, NULL);
        if (vr != VK_SUCCESS || physical_count == 0) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-NOT-AVAILABLE reason=no-vulkan-physical-devices vkResult=%d\n",
                    (int)vr);
            exit_code = NOT_AVAILABLE;
            goto cleanup;
        }

        physical_devices = calloc(physical_count, sizeof(*physical_devices));
        if (!physical_devices) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=enumerate-devices reason=out-of-memory\n");
            goto cleanup;
        }

        vr = vkEnumeratePhysicalDevices(instance, &physical_count,
                                        physical_devices);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=enumerate-devices vkResult=%d\n",
                    (int)vr);
            free(physical_devices);
            goto cleanup;
        }

        for (i = 0; i < physical_count; i++) {
            VkPhysicalDeviceProperties properties;
            VkPhysicalDevicePCIBusInfoPropertiesEXT pci = {
                .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PCI_BUS_INFO_PROPERTIES_EXT
            };
            VkPhysicalDeviceDriverProperties driver = {
                .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES
            };
            VkPhysicalDeviceProperties2 properties2 = {
                .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2
            };
            int extension_present;

            vkGetPhysicalDeviceProperties(physical_devices[i], &properties);
            if (properties.vendorID != GP107_VENDOR_ID ||
                properties.deviceID != GP107_DEVICE_ID)
                continue;

            extension_present = has_device_extension(
                physical_devices[i], VK_EXT_PCI_BUS_INFO_EXTENSION_NAME);
            if (extension_present < 0) {
                fprintf(stderr,
                        "GP107-VK-COMPUTE-FAIL step=enumerate-extensions reason=query-failed\n");
                free(physical_devices);
                goto cleanup;
            }
            if (!extension_present) {
                fprintf(stderr,
                        "GP107-VK-COMPUTE-NOT-AVAILABLE reason=missing-VK_EXT_pci_bus_info\n");
                free(physical_devices);
                exit_code = NOT_AVAILABLE;
                goto cleanup;
            }

            pci.pNext = &driver;
            properties2.pNext = &pci;
            vkGetPhysicalDeviceProperties2(physical_devices[i], &properties2);

            if (pci.pciDomain == expected_domain &&
                pci.pciBus == expected_bus &&
                pci.pciDevice == expected_device &&
                pci.pciFunction == expected_fn) {
                found_count++;
                physical = physical_devices[i];
                physical_properties = properties2.properties;
                driver_properties = driver;
            }
        }

        free(physical_devices);

        if (found_count != 1 || physical == VK_NULL_HANDLE) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-NOT-AVAILABLE reason=pci-match-count-%u expected=1 bdf=%s\n",
                    found_count, expected_bdf);
            exit_code = NOT_AVAILABLE;
            goto cleanup;
        }
    }

    if (!contains_nvk_name(driver_properties.driverName)) {
        fprintf(stderr,
                "GP107-VK-COMPUTE-FAIL reason=not-nvk driverName=%s driverInfo=%s\n",
                driver_properties.driverName, driver_properties.driverInfo);
        goto cleanup;
    }

    if (physical_properties.apiVersion < VK_API_VERSION_1_3) {
        fprintf(stderr,
                "GP107-VK-COMPUTE-NOT-AVAILABLE reason=api-version-below-1.3 api=%u.%u.%u\n",
                VK_VERSION_MAJOR(physical_properties.apiVersion),
                VK_VERSION_MINOR(physical_properties.apiVersion),
                VK_VERSION_PATCH(physical_properties.apiVersion));
        exit_code = NOT_AVAILABLE;
        goto cleanup;
    }

    printf("GP107-VK-COMPUTE-DEVICE bdf=%s vendor=0x%04x device=0x%04x name=\"%s\" driver=\"%s\" driverId=%u info=\"%s\" api=%u.%u.%u\n",
           expected_bdf, physical_properties.vendorID,
           physical_properties.deviceID, physical_properties.deviceName,
           driver_properties.driverName, (unsigned int)driver_properties.driverID,
           driver_properties.driverInfo,
           VK_VERSION_MAJOR(physical_properties.apiVersion),
           VK_VERSION_MINOR(physical_properties.apiVersion),
           VK_VERSION_PATCH(physical_properties.apiVersion));

    vkGetPhysicalDeviceQueueFamilyProperties(physical, &queue_family_count,
                                             NULL);
    if (!queue_family_count) {
        fprintf(stderr,
                "GP107-VK-COMPUTE-NOT-AVAILABLE reason=no-queue-families\n");
        exit_code = NOT_AVAILABLE;
        goto cleanup;
    }

    queue_families = calloc(queue_family_count, sizeof(*queue_families));
    if (!queue_families) {
        fprintf(stderr,
                "GP107-VK-COMPUTE-FAIL step=queue-families reason=out-of-memory\n");
        goto cleanup;
    }

    vkGetPhysicalDeviceQueueFamilyProperties(physical, &queue_family_count,
                                             queue_families);
    for (i = 0; i < queue_family_count; i++) {
        if (queue_families[i].queueCount > 0 &&
            (queue_families[i].queueFlags & VK_QUEUE_COMPUTE_BIT)) {
            queue_family = i;
            break;
        }
    }

    if (queue_family == UINT32_MAX) {
        fprintf(stderr,
                "GP107-VK-COMPUTE-NOT-AVAILABLE reason=no-compute-queue\n");
        exit_code = NOT_AVAILABLE;
        goto cleanup;
    }

    printf("GP107-VK-COMPUTE-QUEUE family=%u flags=0x%x queueCount=%u\n",
           queue_family, queue_families[queue_family].queueFlags,
           queue_families[queue_family].queueCount);

    if (group_count > physical_properties.limits.maxComputeWorkGroupCount[0] ||
        LOCAL_SIZE > physical_properties.limits.maxComputeWorkGroupSize[0] ||
        LOCAL_SIZE > physical_properties.limits.maxComputeWorkGroupInvocations ||
        data_bytes > physical_properties.limits.maxStorageBufferRange) {
        fprintf(stderr,
                "GP107-VK-COMPUTE-NOT-AVAILABLE reason=compute-limits\n");
        exit_code = NOT_AVAILABLE;
        goto cleanup;
    }

    {
        float priority = 1.0f;
        VkDeviceQueueCreateInfo queue_info = {
            .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = queue_family,
            .queueCount = 1,
            .pQueuePriorities = &priority
        };
        const char *extensions[] = { VK_EXT_PCI_BUS_INFO_EXTENSION_NAME };
        VkDeviceCreateInfo create = {
            .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = &queue_info,
            .enabledExtensionCount = 1,
            .ppEnabledExtensionNames = extensions
        };

        vr = vkCreateDevice(physical, &create, NULL, &device);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=create-device vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    vkGetDeviceQueue(device, queue_family, 0, &queue);

    alignment = physical_properties.limits.minStorageBufferOffsetAlignment;
    if (alignment < sizeof(uint32_t))
        alignment = sizeof(uint32_t);
    stride = data_bytes;
    if (stride % alignment)
        stride += alignment - (stride % alignment);
    if (stride > UINT64_MAX / 3u || stride > (VkDeviceSize)SIZE_MAX / 3u) {
        fprintf(stderr,
                "GP107-VK-COMPUTE-FAIL step=buffer-size reason=overflow\n");
        goto cleanup;
    }
    buffer_size = stride * 3u;

    {
        VkBufferCreateInfo create = {
            .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = buffer_size,
            .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
            .sharingMode = VK_SHARING_MODE_EXCLUSIVE
        };
        vr = vkCreateBuffer(device, &create, NULL, &buffer);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=create-buffer vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkMemoryRequirements requirements;
        VkMemoryAllocateInfo allocate = {
            .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        };

        vkGetBufferMemoryRequirements(device, buffer, &requirements);
        vkGetPhysicalDeviceMemoryProperties(physical, &memory_properties);

        if (!choose_memory_type(&memory_properties,
                                requirements.memoryTypeBits,
                                &memory_type_index, &host_coherent)) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-NOT-AVAILABLE reason=no-host-visible-storage-memory\n");
            exit_code = NOT_AVAILABLE;
            goto cleanup;
        }

        allocate.allocationSize = requirements.size;
        allocate.memoryTypeIndex = memory_type_index;
        vr = vkAllocateMemory(device, &allocate, NULL, &memory);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=allocate-memory vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }

        vr = vkBindBufferMemory(device, buffer, memory, 0);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=bind-buffer-memory vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    vr = vkMapMemory(device, memory, 0, VK_WHOLE_SIZE, 0, &mapped);
    if (vr != VK_SUCCESS) {
        fprintf(stderr,
                "GP107-VK-COMPUTE-FAIL step=map-memory vkResult=%d\n",
                (int)vr);
        goto cleanup;
    }

    {
        uint32_t *a = (uint32_t *)mapped;
        uint32_t *b = (uint32_t *)((unsigned char *)mapped + stride);
        uint32_t *c = (uint32_t *)((unsigned char *)mapped + stride * 2u);

        memset(mapped, 0, (size_t)buffer_size);
        for (i = 0; i < ITEM_COUNT; i++) {
            a[i] = i * 3u;
            b[i] = i + 7u;
            c[i] = 0u;
        }
    }

    if (!host_coherent) {
        VkMappedMemoryRange range = {
            .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
            .memory = memory,
            .offset = 0,
            .size = VK_WHOLE_SIZE
        };
        vr = vkFlushMappedMemoryRanges(device, 1, &range);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=flush-memory vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkDescriptorSetLayoutBinding bindings[3];
        VkDescriptorSetLayoutCreateInfo create = {
            .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = 3,
            .pBindings = bindings
        };

        memset(bindings, 0, sizeof(bindings));
        for (i = 0; i < 3; i++) {
            bindings[i].binding = i;
            bindings[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            bindings[i].descriptorCount = 1;
            bindings[i].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
        }

        vr = vkCreateDescriptorSetLayout(device, &create, NULL,
                                         &descriptor_layout);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=create-descriptor-layout vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkPushConstantRange push = {
            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
            .offset = 0,
            .size = sizeof(uint32_t)
        };
        VkPipelineLayoutCreateInfo create = {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 1,
            .pSetLayouts = &descriptor_layout,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &push
        };

        vr = vkCreatePipelineLayout(device, &create, NULL, &pipeline_layout);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=create-pipeline-layout vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkShaderModuleCreateInfo create = {
            .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = spirv_size,
            .pCode = spirv
        };
        vr = vkCreateShaderModule(device, &create, NULL, &shader_module);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=create-shader-module vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkPipelineShaderStageCreateInfo stage = {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_COMPUTE_BIT,
            .module = shader_module,
            .pName = "main"
        };
        VkComputePipelineCreateInfo create = {
            .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
            .stage = stage,
            .layout = pipeline_layout
        };

        vr = vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &create,
                                      NULL, &pipeline);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=create-compute-pipeline vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkDescriptorPoolSize size = {
            .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 3
        };
        VkDescriptorPoolCreateInfo create = {
            .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .maxSets = 1,
            .poolSizeCount = 1,
            .pPoolSizes = &size
        };

        vr = vkCreateDescriptorPool(device, &create, NULL, &descriptor_pool);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=create-descriptor-pool vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkDescriptorSetAllocateInfo allocate = {
            .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = descriptor_pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &descriptor_layout
        };

        vr = vkAllocateDescriptorSets(device, &allocate, &descriptor_set);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=allocate-descriptor-set vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkDescriptorBufferInfo infos[3];
        VkWriteDescriptorSet writes[3];

        memset(infos, 0, sizeof(infos));
        memset(writes, 0, sizeof(writes));

        for (i = 0; i < 3; i++) {
            infos[i].buffer = buffer;
            infos[i].offset = stride * i;
            infos[i].range = data_bytes;

            writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            writes[i].dstSet = descriptor_set;
            writes[i].dstBinding = i;
            writes[i].descriptorCount = 1;
            writes[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            writes[i].pBufferInfo = &infos[i];
        }

        vkUpdateDescriptorSets(device, 3, writes, 0, NULL);
    }

    {
        VkCommandPoolCreateInfo create = {
            .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .queueFamilyIndex = queue_family
        };
        vr = vkCreateCommandPool(device, &create, NULL, &command_pool);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=create-command-pool vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkCommandBufferAllocateInfo allocate = {
            .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1
        };
        vr = vkAllocateCommandBuffers(device, &allocate, &command_buffer);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=allocate-command-buffer vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkCommandBufferBeginInfo begin = {
            .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
        };
        VkBufferMemoryBarrier host_to_compute = {
            .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
            .srcAccessMask = VK_ACCESS_HOST_WRITE_BIT,
            .dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .buffer = buffer,
            .offset = 0,
            .size = VK_WHOLE_SIZE
        };
        VkBufferMemoryBarrier compute_to_host = {
            .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
            .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT,
            .dstAccessMask = VK_ACCESS_HOST_READ_BIT,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .buffer = buffer,
            .offset = 0,
            .size = VK_WHOLE_SIZE
        };
        uint32_t count = ITEM_COUNT;

        vr = vkBeginCommandBuffer(command_buffer, &begin);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=begin-command-buffer vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }

        vkCmdPipelineBarrier(command_buffer, VK_PIPELINE_STAGE_HOST_BIT,
                             VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0,
                             0, NULL, 1, &host_to_compute, 0, NULL);
        vkCmdBindPipeline(command_buffer, VK_PIPELINE_BIND_POINT_COMPUTE,
                          pipeline);
        vkCmdBindDescriptorSets(command_buffer,
                                VK_PIPELINE_BIND_POINT_COMPUTE,
                                pipeline_layout, 0, 1, &descriptor_set,
                                0, NULL);
        vkCmdPushConstants(command_buffer, pipeline_layout,
                           VK_SHADER_STAGE_COMPUTE_BIT, 0,
                           sizeof(count), &count);
        vkCmdDispatch(command_buffer, group_count, 1, 1);
        vkCmdPipelineBarrier(command_buffer,
                             VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                             VK_PIPELINE_STAGE_HOST_BIT, 0,
                             0, NULL, 1, &compute_to_host, 0, NULL);

        vr = vkEndCommandBuffer(command_buffer);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=end-command-buffer vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkFenceCreateInfo create = {
            .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
        };
        vr = vkCreateFence(device, &create, NULL, &fence);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=create-fence vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        VkSubmitInfo submit = {
            .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer
        };
        vr = vkQueueSubmit(queue, 1, &submit, fence);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=queue-submit vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    vr = vkWaitForFences(device, 1, &fence, VK_TRUE, 30000000000ull);
    if (vr != VK_SUCCESS) {
        fprintf(stderr,
                "GP107-VK-COMPUTE-FAIL step=wait-fence vkResult=%d\n",
                (int)vr);
        goto cleanup;
    }

    if (!host_coherent) {
        VkMappedMemoryRange range = {
            .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
            .memory = memory,
            .offset = 0,
            .size = VK_WHOLE_SIZE
        };
        vr = vkInvalidateMappedMemoryRanges(device, 1, &range);
        if (vr != VK_SUCCESS) {
            fprintf(stderr,
                    "GP107-VK-COMPUTE-FAIL step=invalidate-memory vkResult=%d\n",
                    (int)vr);
            goto cleanup;
        }
    }

    {
        uint32_t *a = (uint32_t *)mapped;
        uint32_t *b = (uint32_t *)((unsigned char *)mapped + stride);
        uint32_t *c = (uint32_t *)((unsigned char *)mapped + stride * 2u);

        for (i = 0; i < ITEM_COUNT; i++) {
            uint32_t expected = a[i] + b[i];

            if (c[i] != expected) {
                fprintf(stderr,
                        "GP107-VK-COMPUTE-FAIL step=verify index=%u expected=%u actual=%u\n",
                        i, expected, c[i]);
                goto cleanup;
            }
            checksum += c[i];
        }
    }

    printf("GP107-VK-COMPUTE-PASS bdf=%s api=%u.%u.%u queueFamily=%u queueFlags=0x%x items=%u groups=%u checksum=%" PRIu64 " coherent=%s\n",
           expected_bdf,
           VK_VERSION_MAJOR(physical_properties.apiVersion),
           VK_VERSION_MINOR(physical_properties.apiVersion),
           VK_VERSION_PATCH(physical_properties.apiVersion),
           queue_family, queue_families[queue_family].queueFlags,
           ITEM_COUNT, group_count, checksum,
           host_coherent ? "yes" : "no");
    exit_code = 0;

cleanup:
    if (device != VK_NULL_HANDLE)
        (void)vkDeviceWaitIdle(device);

    if (fence != VK_NULL_HANDLE)
        vkDestroyFence(device, fence, NULL);
    if (command_pool != VK_NULL_HANDLE)
        vkDestroyCommandPool(device, command_pool, NULL);
    if (pipeline != VK_NULL_HANDLE)
        vkDestroyPipeline(device, pipeline, NULL);
    if (shader_module != VK_NULL_HANDLE)
        vkDestroyShaderModule(device, shader_module, NULL);
    if (descriptor_pool != VK_NULL_HANDLE)
        vkDestroyDescriptorPool(device, descriptor_pool, NULL);
    if (pipeline_layout != VK_NULL_HANDLE)
        vkDestroyPipelineLayout(device, pipeline_layout, NULL);
    if (descriptor_layout != VK_NULL_HANDLE)
        vkDestroyDescriptorSetLayout(device, descriptor_layout, NULL);
    if (mapped && device != VK_NULL_HANDLE && memory != VK_NULL_HANDLE)
        vkUnmapMemory(device, memory);
    if (buffer != VK_NULL_HANDLE)
        vkDestroyBuffer(device, buffer, NULL);
    if (memory != VK_NULL_HANDLE)
        vkFreeMemory(device, memory, NULL);
    if (device != VK_NULL_HANDLE)
        vkDestroyDevice(device, NULL);
    if (instance != VK_NULL_HANDLE)
        vkDestroyInstance(instance, NULL);

    free(queue_families);
    free(spirv);
    return exit_code;
}
