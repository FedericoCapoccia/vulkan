const std = @import("std");

const vk = @import("vulkan");

pub const PhysicalDevice = struct {
    handle: vk.PhysicalDevice,
    queue_families: QueueFamilies,
};

pub const QueueFamilies = struct {
    graphics: u32,
    // compute: u32,
    // transfer: u32,
};

pub const DeviceRequirements = struct {
    extensions: []const [*:0]const u8,
    features: DeviceFeatures,
};

pub const DeviceFeatures = struct {
    dynamic_rendering: bool = true,
    synchronization_2: bool = true,
};

pub fn select(
    instance: *const vk.InstanceProxy,
    surface: vk.SurfaceKHR,
    requirements: *const DeviceRequirements,
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

        var features_1_4 = vk.PhysicalDeviceVulkan14Features{};
        var features_1_3 = vk.PhysicalDeviceVulkan13Features{
            .p_next = &features_1_4,
        };
        var features_1_2 = vk.PhysicalDeviceVulkan12Features{
            .p_next = &features_1_3,
        };
        var features_1_1 = vk.PhysicalDeviceVulkan11Features{
            .p_next = &features_1_2,
        };
        var features = vk.PhysicalDeviceFeatures2{
            .features = undefined,
            .p_next = &features_1_1,
        };

        instance.getPhysicalDeviceFeatures2(device, &features);

        if (!hasFeatures(requirements.features, features_1_3)) continue;

        if (!try hasExtensions(instance, device, requirements.extensions, allocator)) continue;
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
    try checkFeatures(requirements.features, physical_device.handle, instance);

    const available_extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(physical_device.handle, null, allocator);
    defer allocator.free(available_extensions);
    try checkExtensions(requirements.extensions, available_extensions);

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

fn hasFeatures(required: DeviceFeatures, available: vk.PhysicalDeviceVulkan13Features) bool {
    if (required.dynamic_rendering and available.dynamic_rendering == .false) return false;
    if (required.synchronization_2 and available.synchronization_2 == .false) return false;

    return true;
}

fn checkFeatures(
    required: DeviceFeatures,
    device: vk.PhysicalDevice,
    instance: *const vk.InstanceProxy,
) !void {
    var features_1_3 = vk.PhysicalDeviceVulkan13Features{};
    var features = vk.PhysicalDeviceFeatures2{
        .features = undefined,
        .p_next = &features_1_3,
    };
    instance.getPhysicalDeviceFeatures2(device, &features);

    std.log.info("Enabled device features", .{});

    if (required.dynamic_rendering) {
        if (features_1_3.dynamic_rendering == .true) {
            std.log.info("\t[OK] dynamic_rendering", .{});
        } else {
            std.log.err("\t[MISSING] dynamic_rendering", .{});
            return error.MissingRequiredDeviceFeature;
        }
    }

    if (required.synchronization_2) {
        if (features_1_3.synchronization_2 == .true) {
            std.log.info("\t[OK] synchronization_2", .{});
        } else {
            std.log.err("\t[MISSING] synchronization_2", .{});
            return error.MissingRequiredDeviceFeature;
        }
    }
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
    var count: u32 = undefined;
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
