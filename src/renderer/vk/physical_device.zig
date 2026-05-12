const std = @import("std");

const vk = @import("vulkan");
const profile = @import("profile.zig");

pub const PhysicalDevice = struct {
    handle: vk.PhysicalDevice,
    queue_families: QueueFamilies,
    profile: profile.EngineProfile,
};

pub const QueueFamilies = struct {
    graphics: u32,
    // compute: u32,
    // transfer: u32,
};

pub fn select(
    instance: vk.InstanceProxy,
    surface: vk.SurfaceKHR,
    requirements: *const profile.EngineRequirements,
    allocator: std.mem.Allocator,
) !PhysicalDevice {
    const devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(devices);
    if (devices.len == 0) return error.NoPhysicalDevice;

    var selected: ?PhysicalDevice = null;
    var selected_props: vk.PhysicalDeviceProperties = undefined;
    for (devices) |device| {
        var props = vk.PhysicalDeviceProperties2{ .properties = undefined };
        instance.getPhysicalDeviceProperties2(device, &props);

        if (props.properties.api_version < vk.API_VERSION_1_3.toU32()) continue;
        const queue_families = (try findQueueFamilies(instance, device, surface, allocator)) orelse continue;
        if (!try hasSwapchainSupport(instance, device, surface, allocator)) continue;

        const pf = try profile.supportedProfile(instance, device, requirements, allocator) orelse continue;

        const candidate = PhysicalDevice{
            .handle = device,
            .queue_families = queue_families,
            .profile = pf,
        };

        if (props.properties.device_type == .discrete_gpu) {
            selected = candidate;
            selected_props = props.properties;
            break;
        }

        if (selected == null) {
            selected = candidate;
            selected_props = props.properties;
        }
    }

    const physical_device = selected orelse return error.NoSuitablePhysicalDevice;
    logSelectedDevice(selected_props, physical_device.queue_families, physical_device.profile);

    return physical_device;
}

fn logSelectedDevice(props: vk.PhysicalDeviceProperties, queue_families: QueueFamilies, engine_profile: profile.EngineProfile) void {
    const device_name = std.mem.sliceTo(&props.device_name, 0);
    const api_version: vk.Version = @bitCast(props.api_version);

    std.log.info("Selected physical device", .{});
    std.log.info("\tName: {s}", .{device_name});
    std.log.info("\tType: {s}", .{@tagName(props.device_type)});
    std.log.info("\tVulkan API: {}.{}.{}", .{ api_version.major, api_version.minor, api_version.patch });
    std.log.info("\tGraphics queue family: {}", .{queue_families.graphics});
    std.log.info("\tEngine profile: {s}", .{@tagName(engine_profile)});
}

fn findQueueFamilies(
    instance: vk.InstanceProxy,
    device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    allocator: std.mem.Allocator,
) !?QueueFamilies {
    // TODO: Open a vulkan-zig issue: getPhysicalDeviceQueueFamilyProperties2Alloc
    // allocates an uninitialized []QueueFamilyProperties2 and passes it to Vulkan.
    // The driver reads s_type/p_next before writing queue_family_properties, so each
    // element must be initialized first. Without this, RADV crashed in
    // libvulkan_radeon.so with a general protection exception. If validation layers are enabled this is logged
    // error: Vulkan [VALIDATION]: {
    //          "Severity" : "Error",
    //          "VUID" : "VUID-VkQueueFamilyProperties2-sType-sType",
    //          "Objects" : [
    //            {"type" : "VkPhysicalDevice", "handle" : "0x26a42400", "name" : ""}
    //          ],
    //          "MessageID" : "0x3feff2ec",
    //          "Function" : "vkGetPhysicalDeviceQueueFamilyProperties2",
    //          "Location" : "pQueueFamilyProperties[0].sType",
    //          "MainMessage" : "must be VK_STRUCTURE_TYPE_QUEUE_FAMILY_PROPERTIES_2",
    //          "DebugRegion" : "",
    //          "SpecText" : "sType must be VK_STRUCTURE_TYPE_QUEUE_FAMILY_PROPERTIES_2",
    //          "SpecUrl" : "https://docs.vulkan.org/spec/latest/chapters/devsandqueues.html#VUID-VkQueueFamilyProperties2-sType-sType"
    //        }
    // const queue_families = try instance.getPhysicalDeviceQueueFamilyProperties2Alloc(device, allocator);
    var count: u32 = 0;
    instance.getPhysicalDeviceQueueFamilyProperties2(device, &count, null);
    const queue_families = try allocator.alloc(vk.QueueFamilyProperties2, count);
    defer allocator.free(queue_families);
    for (queue_families) |*queue_family| {
        queue_family.* = .{ .queue_family_properties = undefined };
    }
    instance.getPhysicalDeviceQueueFamilyProperties2(
        device,
        &count,
        queue_families.ptr,
    );

    for (queue_families, 0..) |queue_family, index| {
        const props = queue_family.queue_family_properties;
        if (props.queue_count == 0 or !props.queue_flags.graphics_bit) continue;

        const queue_family_index: u32 = @intCast(index);
        const present_supported = try instance.getPhysicalDeviceSurfaceSupportKHR(
            device,
            queue_family_index,
            surface,
        );

        if (present_supported == .true) {
            return .{ .graphics = queue_family_index };
        }
    }

    return null;
}

fn hasSwapchainSupport(
    instance: vk.InstanceProxy,
    device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    allocator: std.mem.Allocator,
) !bool {
    const formats = try instance.getPhysicalDeviceSurfaceFormatsAllocKHR(device, surface, allocator);
    defer allocator.free(formats);
    if (formats.len == 0) return false;

    const present_modes = try instance.getPhysicalDeviceSurfacePresentModesAllocKHR(device, surface, allocator);
    defer allocator.free(present_modes);
    return present_modes.len != 0;
}
