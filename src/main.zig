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

    const physical_device = try selectPhysicalDevice(&instance, init.gpa);
    _ = physical_device;

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}

fn selectPhysicalDevice(instance: *const vk.InstanceProxy, allocator: std.mem.Allocator) !vk.PhysicalDevice {
    const available = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(available);

    std.log.info("Available Physical Devices:", .{});
    for (available) |device| {
        const props = instance.getPhysicalDeviceProperties(device);
        std.log.info("\t{s}", .{props.device_name});
        if (props.device_type == .discrete_gpu) {
            return device;
        }
    }
    return available[0];
}
