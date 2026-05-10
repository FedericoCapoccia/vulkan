const std = @import("std");

const vk = @import("vulkan");
const profile = @import("../profile.zig");

pub const PhysicalDevice = struct {
    handle: vk.PhysicalDevice,
    queue_families: QueueFamilies,
};

pub const QueueFamilies = struct {
    graphics: u32,
    // compute: u32,
    // transfer: u32,
};

pub fn select(
    instance: *const vk.InstanceProxy,
    surface: vk.SurfaceKHR,
    extensions: []const [*:0]const u8,
    allocator: std.mem.Allocator,
) !PhysicalDevice {
    const devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(devices);
    if (devices.len == 0) return error.NoVulkan14PhysicalDevice;

    var selected: ?PhysicalDevice = null;
    var selected_props: vk.PhysicalDeviceProperties = undefined;
    for (devices) |device| {
        var props = vk.PhysicalDeviceProperties2{ .properties = undefined };
        instance.getPhysicalDeviceProperties2(device, &props);

        if (props.properties.api_version < vk.API_VERSION_1_3.toU32()) continue;

        if (!try profile.physicalDeviceSupported(instance.handle, device)) continue;

        if (!try hasExtensions(instance, device, extensions, allocator)) continue;
        const queue_families = (try findQueueFamilies(instance, device, surface, allocator)) orelse continue;

        const candidate = PhysicalDevice{
            .handle = device,
            .queue_families = queue_families,
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
    logSelectedDevice(selected_props, physical_device.queue_families);
    profile.logSelectedProfile();

    const available_extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(physical_device.handle, null, allocator);
    defer allocator.free(available_extensions);
    try checkExtensions(extensions, available_extensions);

    return physical_device;
}

fn logSelectedDevice(props: vk.PhysicalDeviceProperties, queue_families: QueueFamilies) void {
    const device_name = std.mem.sliceTo(&props.device_name, 0);
    const api_version: vk.Version = @bitCast(props.api_version);

    std.log.info("Selected physical device", .{});
    std.log.info("\tName: {s}", .{device_name});
    std.log.info("\tType: {s}", .{@tagName(props.device_type)});
    std.log.info("\tVulkan API: {}.{}.{}", .{ api_version.major, api_version.minor, api_version.patch });
    std.log.info("\tGraphics queue family: {}", .{queue_families.graphics});
}

fn hasExtensions(
    instance: *const vk.InstanceProxy,
    device: vk.PhysicalDevice,
    required: []const [*:0]const u8,
    allocator: std.mem.Allocator,
) !bool {
    const available = try instance.enumerateDeviceExtensionPropertiesAlloc(device, null, allocator);
    defer allocator.free(available);

    for (required) |required_z| {
        const required_name = std.mem.span(required_z);
        var found = false;

        for (available) |extension| {
            const available_name = std.mem.sliceTo(&extension.extension_name, 0);
            if (std.mem.eql(u8, required_name, available_name)) {
                found = true;
                break;
            }
        }

        if (!found) return false;
    }

    return true;
}

fn checkExtensions(required: []const [*:0]const u8, available: []const vk.ExtensionProperties) !void {
    std.log.info("Enabled device extensions", .{});

    var all_found = true;
    for (required) |required_z| {
        const required_name = std.mem.span(required_z);
        var found: ?vk.ExtensionProperties = null;

        for (available) |extension| {
            const available_name = std.mem.sliceTo(&extension.extension_name, 0);
            if (std.mem.eql(u8, required_name, available_name)) {
                found = extension;
                break;
            }
        }

        if (found) |extension| {
            std.log.info("\t[OK] {s} v{}", .{ required_name, extension.spec_version });
        } else {
            all_found = false;
            std.log.err("\t[MISSING] {s} v0", .{required_name});
        }
    }

    if (!all_found) return error.MissingRequiredDeviceExtension;
}

fn findQueueFamilies(
    instance: *const vk.InstanceProxy,
    device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    allocator: std.mem.Allocator,
) !?QueueFamilies {
    // TODO: Open a vulkan-zig issue: getPhysicalDeviceQueueFamilyProperties2Alloc
    // allocates an uninitialized []QueueFamilyProperties2 and passes it to Vulkan.
    // The driver reads s_type/p_next before writing queue_family_properties, so each
    // element must be initialized first. Without this, RADV crashed in
    // libvulkan_radeon.so with a general protection exception.
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
