const std = @import("std");

const vk = @import("vulkan");
const vp = @import("vulkan-profiles");

pub fn createInstance(
    extensions: []const [*:0]const u8,
    p_next: ?*const anyopaque,
) !vk.Instance {
    var supported: vp.VkBool32 = vp.VK_FALSE;
    var selected_profile = profile();
    try check(vp.vpGetInstanceProfileSupport(null, &selected_profile, &supported));
    if (supported != vp.VK_TRUE) return error.VulkanProfileUnsupported;

    std.log.info("Vulkan profile: {s} v{}", .{
        selected_profile.profileName,
        selected_profile.specVersion,
    });

    const app_info = vp.VkApplicationInfo{
        .sType = vp.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Vulkan",
        .applicationVersion = vp.VK_MAKE_VERSION(0, 1, 0),
        .pEngineName = "No Engine",
        .engineVersion = vp.VK_MAKE_VERSION(0, 1, 0),
        .apiVersion = vp.VP_LUNARG_MINIMUM_REQUIREMENTS_1_3_MIN_API_VERSION,
    };

    const cinfo = vp.VkInstanceCreateInfo{
        .sType = vp.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = p_next,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(extensions.len),
        .ppEnabledExtensionNames = if (extensions.len == 0) null else @ptrCast(extensions.ptr),
    };

    const profile_cinfo = vp.VpInstanceCreateInfo{
        .pCreateInfo = &cinfo,
        .enabledFullProfileCount = 1,
        .pEnabledFullProfiles = &selected_profile,
    };

    var instance: vp.VkInstance = null;
    try check(vp.vpCreateInstance(&profile_cinfo, null, &instance));

    return fromCInstance(instance);
}

pub fn physicalDeviceSupported(instance: vk.Instance, pdev: vk.PhysicalDevice) !bool {
    var supported: vp.VkBool32 = vp.VK_FALSE;
    var selected_profile = profile();
    try check(vp.vpGetPhysicalDeviceProfileSupport(
        toCInstance(instance),
        toCPhysicalDevice(pdev),
        &selected_profile,
        &supported,
    ));

    return supported == vp.VK_TRUE;
}

pub fn createDevice(
    pdev: vk.PhysicalDevice,
    queue_family: u32,
    extensions: []const [*:0]const u8,
) !vk.Device {
    var vulkan_11_features = vp.VkPhysicalDeviceVulkan11Features{
        .sType = vp.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
        .shaderDrawParameters = vp.VK_TRUE,
    };

    const queue_priority = [_]f32{1.0};
    const queue_cinfo = [_]vp.VkDeviceQueueCreateInfo{.{
        .sType = vp.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    }};

    const device_cinfo = vp.VkDeviceCreateInfo{
        .sType = vp.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &vulkan_11_features,
        .queueCreateInfoCount = queue_cinfo.len,
        .pQueueCreateInfos = &queue_cinfo,
        .enabledExtensionCount = @intCast(extensions.len),
        .ppEnabledExtensionNames = if (extensions.len == 0) null else @ptrCast(extensions.ptr),
    };

    var selected_profile = profile();
    const profile_cinfo = vp.VpDeviceCreateInfo{
        .pCreateInfo = &device_cinfo,
        .enabledFullProfileCount = 1,
        .pEnabledFullProfiles = &selected_profile,
    };

    var device: vp.VkDevice = null;
    try check(vp.vpCreateDevice(
        toCPhysicalDevice(pdev),
        &profile_cinfo,
        null,
        &device,
    ));

    return fromCDevice(device);
}

fn profile() vp.VpProfileProperties {
    var props = vp.VpProfileProperties{
        .specVersion = vp.VP_LUNARG_MINIMUM_REQUIREMENTS_1_3_SPEC_VERSION,
    };
    const name = std.mem.sliceTo(vp.VP_LUNARG_MINIMUM_REQUIREMENTS_1_3_NAME, 0);
    std.mem.copyForwards(u8, props.profileName[0..name.len], name);
    return props;
}

fn check(result: vp.VkResult) !void {
    switch (result) {
        vp.VK_SUCCESS => {},
        vp.VK_ERROR_OUT_OF_HOST_MEMORY => return error.OutOfHostMemory,
        vp.VK_ERROR_OUT_OF_DEVICE_MEMORY => return error.OutOfDeviceMemory,
        vp.VK_ERROR_INITIALIZATION_FAILED => return error.VulkanProfileInitializationFailed,
        vp.VK_ERROR_EXTENSION_NOT_PRESENT => return error.VulkanProfileExtensionNotPresent,
        vp.VK_ERROR_FEATURE_NOT_PRESENT => return error.VulkanProfileFeatureNotPresent,
        vp.VK_ERROR_INCOMPATIBLE_DRIVER => return error.VulkanProfileIncompatibleDriver,
        else => {
            std.log.err("Vulkan Profiles call failed with VkResult {}", .{result});
            return error.VulkanProfileFailed;
        },
    }
}

fn fromCInstance(handle: vp.VkInstance) vk.Instance {
    return @enumFromInt(@intFromPtr(handle));
}

fn toCInstance(handle: vk.Instance) vp.VkInstance {
    return @ptrFromInt(@intFromEnum(handle));
}

fn toCPhysicalDevice(handle: vk.PhysicalDevice) vp.VkPhysicalDevice {
    return @ptrFromInt(@intFromEnum(handle));
}

fn fromCDevice(handle: vp.VkDevice) vk.Device {
    return @enumFromInt(@intFromPtr(handle));
}
