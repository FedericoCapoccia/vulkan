const std = @import("std");

const vk = @import("vulkan");

pub const PhysicalDevice = struct {
    handle: vk.PhysicalDevice,
    graphics_queue_family_index: u32,
    present_queue_family_index: u32,

    pub fn select(
        instance: *const vk.InstanceProxy,
        surface: vk.SurfaceKHR,
        required_ext: []const [*:0]const u8,
        allocator: std.mem.Allocator,
    ) !PhysicalDevice {
        const available = try instance.enumeratePhysicalDevicesAlloc(allocator);
        defer allocator.free(available);
        if (available.len == 0) return error.NoVulkan14PhysicalDevice;

        std.log.info("Available Physical Devices:", .{});
        var first_device: ?PhysicalDevice = null;
        var has_vulkan_1_4 = false;

        for (available) |device| {
            const props = instance.getPhysicalDeviceProperties(device);
            const supports_vulkan_1_4 = props.api_version >= vk.API_VERSION_1_4.toU32();
            has_vulkan_1_4 = has_vulkan_1_4 or supports_vulkan_1_4;

            const device_name = std.mem.sliceTo(&props.device_name, 0);
            std.log.info("\t{s}", .{device_name});

            const has_required_extensions = if (supports_vulkan_1_4)
                try checkDeviceExtensions(instance, device, required_ext, allocator)
            else
                false;

            const selected = if (supports_vulkan_1_4 and has_required_extensions)
                try getQueueFamilies(instance, device, surface, allocator)
            else
                null;

            if (first_device == null and selected != null) {
                first_device = selected;
            }

            if (props.device_type == .discrete_gpu) {
                if (selected) |physical_device| {
                    return physical_device;
                }
            }
        }

        if (!has_vulkan_1_4) return error.NoVulkan14PhysicalDevice;
        const physical_device = first_device orelse return error.NoSuitablePhysicalDevice;
        return physical_device;
    }
};

fn checkDeviceExtensions(
    instance: *const vk.InstanceProxy,
    device: vk.PhysicalDevice,
    required_ext: []const [*:0]const u8,
    allocator: std.mem.Allocator,
) !bool {
    const available_ext = try instance.enumerateDeviceExtensionPropertiesAlloc(device, null, allocator);
    defer allocator.free(available_ext);

    std.log.info("\tAvailable device extensions:", .{});
    for (available_ext) |ext| {
        const name = std.mem.sliceTo(&ext.extension_name, 0);
        var symbol: []const u8 = "➖";
        for (required_ext) |required_ext_z| {
            if (std.mem.eql(u8, std.mem.span(required_ext_z), name)) {
                symbol = "✅";
                break;
            }
        }

        std.log.info("\t\t{s} {s} v{}", .{ symbol, name, ext.spec_version });
    }

    for (required_ext) |required_ext_z| {
        const required_ext_name = std.mem.span(required_ext_z);
        var found = false;
        for (available_ext) |ext| {
            const name = std.mem.sliceTo(&ext.extension_name, 0);
            if (std.mem.eql(u8, required_ext_name, name)) {
                found = true;
                break;
            }
        }

        if (!found) {
            std.log.warn("\tMissing required Vulkan device extension: {s}", .{required_ext_name});
            return false;
        }
    }

    return true;
}

fn getQueueFamilies(
    instance: *const vk.InstanceProxy,
    device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    allocator: std.mem.Allocator,
) !?PhysicalDevice {
    const q_props = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(device, allocator);
    defer allocator.free(q_props);

    var graphics_queue_family_index: ?u32 = null;
    var present_queue_family_index: ?u32 = null;

    for (q_props, 0..) |queue_family, index| {
        if (queue_family.queue_count == 0) continue;

        const queue_family_index: u32 = @intCast(index);
        if (graphics_queue_family_index == null and queue_family.queue_flags.graphics_bit) {
            graphics_queue_family_index = queue_family_index;
        }

        const present_supported = try instance.getPhysicalDeviceSurfaceSupportKHR(
            device,
            queue_family_index,
            surface,
        );

        if (present_queue_family_index == null and present_supported == .true) {
            present_queue_family_index = queue_family_index;
        }
    }

    return .{
        .handle = device,
        .graphics_queue_family_index = graphics_queue_family_index orelse return null,
        .present_queue_family_index = present_queue_family_index orelse return null,
    };
}
