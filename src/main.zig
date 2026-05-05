const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

const Instance = @import("vk/instance.zig").Instance;

pub fn main(init: std.process.Init) !void {
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, false);

    const window = try glfw.createWindow(800, 600, "Vulkan", null, null);
    defer window.destroy();

    const required_layers = [_][*:0]const u8{};
    const glfw_ext = try glfw.getRequiredInstanceExtensions();
    const extensions = [_][*:0]const u8{
        "VK_EXT_debug_utils", // TODO: enable this only on debug mode or feature flag
    };
    const required_ext = try std.mem.concat(
        init.gpa,
        [*:0]const u8,
        &.{ glfw_ext, extensions[0..] },
    );
    defer init.gpa.free(required_ext);

    const vk_instance = try Instance.create(required_layers[0..], required_ext, init.gpa);
    const instance = vk_instance.proxy();
    defer instance.destroyInstance(null);

    const msg = try vk_instance.createDebugUtilsMessenger();
    defer instance.destroyDebugUtilsMessengerEXT(msg, null);

    var surface: vk.SurfaceKHR = undefined;
    try glfw.createWindowSurface(vk_instance.handle, window, null, &surface);
    defer instance.destroySurfaceKHR(surface, null);

    const required_device_ext = [_][*:0]const u8{
        "VK_KHR_swapchain",
    };

    const physical_device = try selectPhysicalDevice(
        &instance,
        surface,
        required_device_ext[0..],
        init.gpa,
    );
    _ = physical_device;

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}

const PhysicalDevice = struct {
    handle: vk.PhysicalDevice,
    graphics_queue_family_index: u32,
    present_queue_family_index: u32,
};

fn selectPhysicalDevice(
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

        if (available[0] == device and selected != null) {
            first_device = selected;
        }

        if (props.device_type == .discrete_gpu) {
            if (selected) |physical_device| {
                logSelectedPhysicalDevice(props, physical_device);
                return physical_device;
            }
        }
    }

    if (!has_vulkan_1_4) return error.NoVulkan14PhysicalDevice;
    const physical_device = first_device orelse return error.NoSuitablePhysicalDevice;
    const props = instance.getPhysicalDeviceProperties(physical_device.handle);
    logSelectedPhysicalDevice(props, physical_device);
    return physical_device;
}

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

fn logSelectedPhysicalDevice(props: vk.PhysicalDeviceProperties, physical_device: PhysicalDevice) void {
    const device_name = std.mem.sliceTo(&props.device_name, 0);
    const api_version: vk.Version = @bitCast(props.api_version);

    std.log.info("Selected Physical Device:", .{});
    std.log.info("\tName: {s}", .{device_name});
    std.log.info("\tType: {s}", .{@tagName(props.device_type)});
    std.log.info("\tVulkan API: {}.{}.{}", .{ api_version.major, api_version.minor, api_version.patch });
    std.log.info("\tVendor ID: 0x{x}", .{props.vendor_id});
    std.log.info("\tDevice ID: 0x{x}", .{props.device_id});
    std.log.info("\tGraphics queue family: {}", .{physical_device.graphics_queue_family_index});
    std.log.info("\tPresent queue family: {}", .{physical_device.present_queue_family_index});
}
