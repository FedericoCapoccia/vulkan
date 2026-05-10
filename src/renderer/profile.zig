const std = @import("std");

const vk = @import("vulkan");
const vp = @import("vulkan-profiles");

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
    const queue_priority = [_]f32{1.0};
    const queue_cinfo = [_]vp.VkDeviceQueueCreateInfo{.{
        .sType = vp.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    }};

    const device_cinfo = vp.VkDeviceCreateInfo{
        .sType = vp.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
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

pub fn logSelectedProfile() void {
    std.log.info("Vulkan profile: {s} v{}", .{
        vp.VP_LUNARG_MINIMUM_REQUIREMENTS_1_3_NAME,
        vp.VP_LUNARG_MINIMUM_REQUIREMENTS_1_3_SPEC_VERSION,
    });
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
    if (result != vp.VK_SUCCESS) return error.VulkanProfileFailed;
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
