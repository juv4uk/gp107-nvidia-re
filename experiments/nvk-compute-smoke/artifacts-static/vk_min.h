/* Minimal Vulkan ABI declarations for a clean-room NVK compute smoke test.
 * Values verified against Khronos Vulkan-Headers vulkan_core.h
 * SHA-256 a6948c33bbc0422092ad5d96fe9ea9d4109214fa00f26715b23ed1971f4e7216.
 * No vendor headers, no vendor code.  x86_64 LP64: non-dispatchable handles
 * are pointers (VK_USE_64_BIT_PTR_DEFINES=1). */
#ifndef VK_MIN_H
#define VK_MIN_H
#include <stdint.h>
#include <stddef.h>

#define VKAPI_PTR
typedef uint32_t VkBool32;
typedef uint64_t VkDeviceSize;
typedef uint32_t VkFlags;
typedef uint32_t VkStructureType;
typedef uint32_t VkDriverId;
typedef int32_t VkResult;
typedef uint32_t VkMemoryMapFlags;
typedef uint32_t VkPhysicalDeviceType;
typedef uint32_t VkQueueFlags;
typedef uint32_t VkBufferCreateFlags;
typedef uint32_t VkBufferUsageFlags;
typedef uint32_t VkSharingMode;
typedef uint32_t VkMemoryPropertyFlags;
typedef uint32_t VkMemoryHeapFlags;
typedef uint32_t VkDescriptorType;
typedef uint32_t VkDescriptorSetLayoutCreateFlags;
typedef uint32_t VkDescriptorPoolCreateFlags;
typedef uint32_t VkPipelineLayoutCreateFlags;
typedef uint32_t VkShaderModuleCreateFlags;
typedef uint32_t VkPipelineShaderStageCreateFlags;
typedef uint32_t VkShaderStageFlagBits;
typedef uint32_t VkPipelineCreateFlags;
typedef uint32_t VkCommandPoolCreateFlags;
typedef uint32_t VkCommandBufferLevel;
typedef uint32_t VkCommandBufferUsageFlags;
typedef uint32_t VkPipelineBindPoint;
typedef uint32_t VkFenceCreateFlags;
typedef uint32_t VkInstanceCreateFlags;
typedef uint32_t VkDeviceQueueCreateFlags;
typedef uint32_t VkDeviceCreateFlags;
typedef uint32_t VkDeviceQueueCreateFlags;
typedef uint32_t VkPipelineStageFlags;
typedef uint32_t VkDeviceCreateFlags2_unused;

#define VK_NULL_HANDLE ((void*)0)
#define VK_FALSE 0
#define VK_TRUE 1
#define VK_SUCCESS 0
#define VK_TIMEOUT 2

#define VK_STRUCTURE_TYPE_APPLICATION_INFO 0
#define VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO 1
#define VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO 2
#define VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO 3
#define VK_STRUCTURE_TYPE_SUBMIT_INFO 4
#define VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO 5
#define VK_STRUCTURE_TYPE_FENCE_CREATE_INFO 8
#define VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO 12
#define VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO 16
#define VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO 18
#define VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO 29
#define VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO 30
#define VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO 32
#define VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO 33
#define VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO 34
#define VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET 35
#define VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO 39
#define VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO 40
#define VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO 42
#define VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2 1000059001
#define VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES 1000196000

#define VK_DRIVER_ID_MESA_NVK 24
#define VK_DRIVER_ID_NVIDIA_PROPRIETARY 4
#define VK_DRIVER_ID_MESA_LLVMPIPE 13

#define VK_BUFFER_USAGE_STORAGE_BUFFER_BIT 0x00000020U
#define VK_SHARING_MODE_EXCLUSIVE 0
#define VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT 0x00000002U
#define VK_MEMORY_PROPERTY_HOST_COHERENT_BIT 0x00000004U
#define VK_DESCRIPTOR_TYPE_STORAGE_BUFFER 7
#define VK_SHADER_STAGE_COMPUTE_BIT 0x00000020U
#define VK_PIPELINE_BIND_POINT_COMPUTE 1
#define VK_QUEUE_COMPUTE_BIT 0x00000002U
#define VK_API_VERSION_1_3 0x00403000U
#define VK_MAX_MEMORY_TYPES 32U
#define VK_MAX_MEMORY_HEAPS 16U
#define VK_MAX_DRIVER_NAME_SIZE 256U
#define VK_MAX_DRIVER_INFO_SIZE 256U

#define VK_DEFINE_HANDLE(o) typedef struct o##_T *o
VK_DEFINE_HANDLE(VkInstance);
VK_DEFINE_HANDLE(VkPhysicalDevice);
VK_DEFINE_HANDLE(VkDevice);
VK_DEFINE_HANDLE(VkQueue);
VK_DEFINE_HANDLE(VkCommandBuffer);
VK_DEFINE_HANDLE(VkSemaphore);
VK_DEFINE_HANDLE(VkFence);
VK_DEFINE_HANDLE(VkDeviceMemory);
VK_DEFINE_HANDLE(VkBuffer);
VK_DEFINE_HANDLE(VkImage);
VK_DEFINE_HANDLE(VkQueryPool);
VK_DEFINE_HANDLE(VkImageView);
VK_DEFINE_HANDLE(VkSampler);
VK_DEFINE_HANDLE(VkBufferView);
VK_DEFINE_HANDLE(VkDescriptorSetLayout);
VK_DEFINE_HANDLE(VkDescriptorPool);
VK_DEFINE_HANDLE(VkDescriptorSet);
VK_DEFINE_HANDLE(VkPipelineLayout);
VK_DEFINE_HANDLE(VkShaderModule);
VK_DEFINE_HANDLE(VkPipeline);
VK_DEFINE_HANDLE(VkPipelineCache);
VK_DEFINE_HANDLE(VkCommandPool);
VK_DEFINE_HANDLE(VkRenderPass);
VK_DEFINE_HANDLE(VkFramebuffer);

typedef struct VkAllocationCallbacks VkAllocationCallbacks;
typedef struct VkCopyDescriptorSet VkCopyDescriptorSet;
typedef struct VkDescriptorImageInfo VkDescriptorImageInfo;
typedef struct VkPushConstantRange VkPushConstantRange;
typedef struct VkCommandBufferInheritanceInfo VkCommandBufferInheritanceInfo;
typedef struct VkSpecializationInfo VkSpecializationInfo;
typedef struct VkPhysicalDeviceFeatures VkPhysicalDeviceFeatures;

typedef struct VkApplicationInfo {
    VkStructureType sType; const void* pNext;
    const char* pApplicationName; uint32_t applicationVersion;
    const char* pEngineName; uint32_t engineVersion; uint32_t apiVersion;
} VkApplicationInfo;

typedef struct VkInstanceCreateInfo {
    VkStructureType sType; const void* pNext; VkInstanceCreateFlags flags;
    const VkApplicationInfo* pApplicationInfo;
    uint32_t enabledLayerCount; const char* const* ppEnabledLayerNames;
    uint32_t enabledExtensionCount; const char* const* ppEnabledExtensionNames;
} VkInstanceCreateInfo;

typedef struct VkDeviceQueueCreateInfo {
    VkStructureType sType; const void* pNext; VkDeviceQueueCreateFlags flags;
    uint32_t queueFamilyIndex; uint32_t queueCount; const float* pQueuePriorities;
} VkDeviceQueueCreateInfo;

typedef struct VkDeviceCreateInfo {
    VkStructureType sType; const void* pNext; VkDeviceCreateFlags flags;
    uint32_t queueCreateInfoCount; const VkDeviceQueueCreateInfo* pQueueCreateInfos;
    uint32_t enabledLayerCount; const char* const* ppEnabledLayerNames;
    uint32_t enabledExtensionCount; const char* const* ppEnabledExtensionNames;
    const VkPhysicalDeviceFeatures* pEnabledFeatures;
} VkDeviceCreateInfo;

typedef struct VkExtent3D { uint32_t width, height, depth; } VkExtent3D;
typedef struct VkQueueFamilyProperties {
    VkQueueFlags queueFlags; uint32_t queueCount; uint32_t timestampValidBits;
    VkExtent3D minImageTransferGranularity;
} VkQueueFamilyProperties;

/* Prefix of VkPhysicalDeviceProperties with an intentionally large tail:
 * we read only apiVersion..deviceName. */
typedef struct VkPhysicalDevicePropertiesMin {
    uint32_t apiVersion, driverVersion, vendorID, deviceID;
    VkPhysicalDeviceType deviceType;
    char deviceName[256];
    unsigned char tail[4096];
} VkPhysicalDevicePropertiesMin;

typedef struct VkPhysicalDeviceProperties2Min {
    VkStructureType sType; void* pNext;
    VkPhysicalDevicePropertiesMin properties;
} VkPhysicalDeviceProperties2Min;

typedef struct VkConformanceVersion {
    uint8_t major, minor, subminor, patch;
} VkConformanceVersion;

typedef struct VkPhysicalDeviceDriverProperties {
    VkStructureType sType; void* pNext; VkDriverId driverID;
    char driverName[VK_MAX_DRIVER_NAME_SIZE];
    char driverInfo[VK_MAX_DRIVER_INFO_SIZE];
    VkConformanceVersion conformanceVersion;
} VkPhysicalDeviceDriverProperties;

typedef struct VkMemoryType { VkMemoryPropertyFlags propertyFlags; uint32_t heapIndex; } VkMemoryType;
typedef struct VkMemoryHeap { VkDeviceSize size; VkMemoryHeapFlags flags; } VkMemoryHeap;
typedef struct VkPhysicalDeviceMemoryProperties {
    uint32_t memoryTypeCount; VkMemoryType memoryTypes[VK_MAX_MEMORY_TYPES];
    uint32_t memoryHeapCount; VkMemoryHeap memoryHeaps[VK_MAX_MEMORY_HEAPS];
} VkPhysicalDeviceMemoryProperties;

typedef struct VkBufferCreateInfo {
    VkStructureType sType; const void* pNext; VkBufferCreateFlags flags;
    VkDeviceSize size; VkBufferUsageFlags usage; VkSharingMode sharingMode;
    uint32_t queueFamilyIndexCount; const uint32_t* pQueueFamilyIndices;
} VkBufferCreateInfo;

typedef struct VkMemoryRequirements {
    VkDeviceSize size, alignment; uint32_t memoryTypeBits;
} VkMemoryRequirements;

typedef struct VkMemoryAllocateInfo {
    VkStructureType sType; const void* pNext; VkDeviceSize allocationSize;
    uint32_t memoryTypeIndex;
} VkMemoryAllocateInfo;

typedef struct VkDescriptorSetLayoutBinding {
    uint32_t binding; VkDescriptorType descriptorType; uint32_t descriptorCount;
    uint32_t stageFlags; const VkSampler* pImmutableSamplers;
} VkDescriptorSetLayoutBinding;

typedef struct VkDescriptorSetLayoutCreateInfo {
    VkStructureType sType; const void* pNext;
    VkDescriptorSetLayoutCreateFlags flags; uint32_t bindingCount;
    const VkDescriptorSetLayoutBinding* pBindings;
} VkDescriptorSetLayoutCreateInfo;

typedef struct VkDescriptorPoolSize { VkDescriptorType type; uint32_t descriptorCount; } VkDescriptorPoolSize;

typedef struct VkDescriptorPoolCreateInfo {
    VkStructureType sType; const void* pNext; VkDescriptorPoolCreateFlags flags;
    uint32_t maxSets; uint32_t poolSizeCount; const VkDescriptorPoolSize* pPoolSizes;
} VkDescriptorPoolCreateInfo;

typedef struct VkDescriptorSetAllocateInfo {
    VkStructureType sType; const void* pNext; VkDescriptorPool descriptorPool;
    uint32_t descriptorSetCount; const VkDescriptorSetLayout* pSetLayouts;
} VkDescriptorSetAllocateInfo;

typedef struct VkDescriptorBufferInfo { VkBuffer buffer; VkDeviceSize offset, range; } VkDescriptorBufferInfo;

typedef struct VkWriteDescriptorSet {
    VkStructureType sType; const void* pNext; VkDescriptorSet dstSet;
    uint32_t dstBinding, dstArrayElement, descriptorCount;
    VkDescriptorType descriptorType;
    const VkDescriptorImageInfo* pImageInfo;
    const VkDescriptorBufferInfo* pBufferInfo;
    const VkBufferView* pTexelBufferView;
} VkWriteDescriptorSet;

typedef struct VkPipelineLayoutCreateInfo {
    VkStructureType sType; const void* pNext; VkPipelineLayoutCreateFlags flags;
    uint32_t setLayoutCount; const VkDescriptorSetLayout* pSetLayouts;
    uint32_t pushConstantRangeCount; const VkPushConstantRange* pPushConstantRanges;
} VkPipelineLayoutCreateInfo;

typedef struct VkShaderModuleCreateInfo {
    VkStructureType sType; const void* pNext; VkShaderModuleCreateFlags flags;
    size_t codeSize; const uint32_t* pCode;
} VkShaderModuleCreateInfo;

typedef struct VkPipelineShaderStageCreateInfo {
    VkStructureType sType; const void* pNext; VkPipelineShaderStageCreateFlags flags;
    VkShaderStageFlagBits stage; VkShaderModule module; const char* pName;
    const VkSpecializationInfo* pSpecializationInfo;
} VkPipelineShaderStageCreateInfo;

typedef struct VkComputePipelineCreateInfo {
    VkStructureType sType; const void* pNext; VkPipelineCreateFlags flags;
    VkPipelineShaderStageCreateInfo stage; VkPipelineLayout layout;
    VkPipeline basePipelineHandle; int32_t basePipelineIndex;
} VkComputePipelineCreateInfo;

typedef struct VkCommandPoolCreateInfo {
    VkStructureType sType; const void* pNext; VkCommandPoolCreateFlags flags;
    uint32_t queueFamilyIndex;
} VkCommandPoolCreateInfo;

typedef struct VkCommandBufferAllocateInfo {
    VkStructureType sType; const void* pNext; VkCommandPool commandPool;
    VkCommandBufferLevel level; uint32_t commandBufferCount;
} VkCommandBufferAllocateInfo;

typedef struct VkCommandBufferBeginInfo {
    VkStructureType sType; const void* pNext; VkCommandBufferUsageFlags flags;
    const VkCommandBufferInheritanceInfo* pInheritanceInfo;
} VkCommandBufferBeginInfo;

typedef struct VkSubmitInfo {
    VkStructureType sType; const void* pNext;
    uint32_t waitSemaphoreCount; const VkSemaphore* pWaitSemaphores;
    const VkPipelineStageFlags* pWaitDstStageMask;
    uint32_t commandBufferCount; const VkCommandBuffer* pCommandBuffers;
    uint32_t signalSemaphoreCount; const VkSemaphore* pSignalSemaphores;
} VkSubmitInfo;

typedef struct VkFenceCreateInfo {
    VkStructureType sType; const void* pNext; VkFenceCreateFlags flags;
} VkFenceCreateInfo;

typedef void (*PFN_vkVoidFunction)(void);
typedef PFN_vkVoidFunction (*PFN_vkGetInstanceProcAddr)(VkInstance, const char*);
typedef VkResult (*PFN_vkCreateInstance)(const VkInstanceCreateInfo*, const VkAllocationCallbacks*, VkInstance*);
typedef void (*PFN_vkDestroyInstance)(VkInstance, const VkAllocationCallbacks*);
typedef VkResult (*PFN_vkEnumeratePhysicalDevices)(VkInstance, uint32_t*, VkPhysicalDevice*);
typedef void (*PFN_vkGetPhysicalDeviceProperties2)(VkPhysicalDevice, void*);
typedef void (*PFN_vkGetPhysicalDeviceMemoryProperties)(VkPhysicalDevice, VkPhysicalDeviceMemoryProperties*);
typedef void (*PFN_vkGetPhysicalDeviceQueueFamilyProperties)(VkPhysicalDevice, uint32_t*, VkQueueFamilyProperties*);
typedef VkResult (*PFN_vkCreateDevice)(VkPhysicalDevice, const VkDeviceCreateInfo*, const VkAllocationCallbacks*, VkDevice*);
typedef void (*PFN_vkGetDeviceQueue)(VkDevice, uint32_t, uint32_t, VkQueue*);
typedef void (*PFN_vkDestroyDevice)(VkDevice, const VkAllocationCallbacks*);
typedef VkResult (*PFN_vkCreateBuffer)(VkDevice, const VkBufferCreateInfo*, const VkAllocationCallbacks*, VkBuffer*);
typedef void (*PFN_vkGetBufferMemoryRequirements)(VkDevice, VkBuffer, VkMemoryRequirements*);
typedef VkResult (*PFN_vkAllocateMemory)(VkDevice, const VkMemoryAllocateInfo*, const VkAllocationCallbacks*, VkDeviceMemory*);
typedef VkResult (*PFN_vkBindBufferMemory)(VkDevice, VkBuffer, VkDeviceMemory, VkDeviceSize);
typedef VkResult (*PFN_vkMapMemory)(VkDevice, VkDeviceMemory, VkDeviceSize, VkDeviceSize, VkMemoryMapFlags, void**);
typedef void (*PFN_vkUnmapMemory)(VkDevice, VkDeviceMemory);
typedef void (*PFN_vkDestroyBuffer)(VkDevice, VkBuffer, const VkAllocationCallbacks*);
typedef void (*PFN_vkFreeMemory)(VkDevice, VkDeviceMemory, const VkAllocationCallbacks*);
typedef VkResult (*PFN_vkCreateDescriptorSetLayout)(VkDevice, const VkDescriptorSetLayoutCreateInfo*, const VkAllocationCallbacks*, VkDescriptorSetLayout*);
typedef void (*PFN_vkDestroyDescriptorSetLayout)(VkDevice, VkDescriptorSetLayout, const VkAllocationCallbacks*);
typedef VkResult (*PFN_vkCreatePipelineLayout)(VkDevice, const VkPipelineLayoutCreateInfo*, const VkAllocationCallbacks*, VkPipelineLayout*);
typedef void (*PFN_vkDestroyPipelineLayout)(VkDevice, VkPipelineLayout, const VkAllocationCallbacks*);
typedef VkResult (*PFN_vkCreateShaderModule)(VkDevice, const VkShaderModuleCreateInfo*, const VkAllocationCallbacks*, VkShaderModule*);
typedef void (*PFN_vkDestroyShaderModule)(VkDevice, VkShaderModule, const VkAllocationCallbacks*);
typedef VkResult (*PFN_vkCreateComputePipelines)(VkDevice, VkPipelineCache, uint32_t, const VkComputePipelineCreateInfo*, const VkAllocationCallbacks*, VkPipeline*);
typedef void (*PFN_vkDestroyPipeline)(VkDevice, VkPipeline, const VkAllocationCallbacks*);
typedef VkResult (*PFN_vkCreateDescriptorPool)(VkDevice, const VkDescriptorPoolCreateInfo*, const VkAllocationCallbacks*, VkDescriptorPool*);
typedef void (*PFN_vkDestroyDescriptorPool)(VkDevice, VkDescriptorPool, const VkAllocationCallbacks*);
typedef VkResult (*PFN_vkAllocateDescriptorSets)(VkDevice, const VkDescriptorSetAllocateInfo*, VkDescriptorSet*);
typedef void (*PFN_vkUpdateDescriptorSets)(VkDevice, uint32_t, const VkWriteDescriptorSet*, uint32_t, const VkCopyDescriptorSet*);
typedef VkResult (*PFN_vkCreateCommandPool)(VkDevice, const VkCommandPoolCreateInfo*, const VkAllocationCallbacks*, VkCommandPool*);
typedef void (*PFN_vkDestroyCommandPool)(VkDevice, VkCommandPool, const VkAllocationCallbacks*);
typedef VkResult (*PFN_vkAllocateCommandBuffers)(VkDevice, const VkCommandBufferAllocateInfo*, VkCommandBuffer*);
typedef void (*PFN_vkFreeCommandBuffers)(VkDevice, VkCommandPool, uint32_t, const VkCommandBuffer*);
typedef VkResult (*PFN_vkBeginCommandBuffer)(VkCommandBuffer, const VkCommandBufferBeginInfo*);
typedef void (*PFN_vkCmdBindPipeline)(VkCommandBuffer, VkPipelineBindPoint, VkPipeline);
typedef void (*PFN_vkCmdBindDescriptorSets)(VkCommandBuffer, VkPipelineBindPoint, VkPipelineLayout, uint32_t, uint32_t, const VkDescriptorSet*, uint32_t, const uint32_t*);
typedef void (*PFN_vkCmdDispatch)(VkCommandBuffer, uint32_t, uint32_t, uint32_t);
typedef VkResult (*PFN_vkEndCommandBuffer)(VkCommandBuffer);
typedef VkResult (*PFN_vkCreateFence)(VkDevice, const VkFenceCreateInfo*, const VkAllocationCallbacks*, VkFence*);
typedef void (*PFN_vkDestroyFence)(VkDevice, VkFence, const VkAllocationCallbacks*);
typedef VkResult (*PFN_vkResetFences)(VkDevice, uint32_t, const VkFence*);
typedef VkResult (*PFN_vkQueueSubmit)(VkQueue, uint32_t, const VkSubmitInfo*, VkFence);
typedef VkResult (*PFN_vkWaitForFences)(VkDevice, uint32_t, const VkFence*, VkBool32, uint64_t);
typedef VkResult (*PFN_vkGetFenceStatus)(VkDevice, VkFence);

#endif
