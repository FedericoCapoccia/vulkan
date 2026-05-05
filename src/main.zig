const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

const PhysicalDevice = @import("vk/physical_device.zig").PhysicalDevice;
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

    const physical_device = try PhysicalDevice.select(
        &instance,
        surface,
        required_device_ext[0..],
        init.gpa,
    );
    {
        const props = instance.getPhysicalDeviceProperties(physical_device.handle);
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

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
