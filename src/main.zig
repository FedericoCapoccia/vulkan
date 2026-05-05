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

    const required_layers = [_][*:0]const u8{
        "VK_LAYER_KHRONOS_validation",
    };

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

    const instance = try Instance.create(required_layers[0..], required_ext, init.gpa);
    defer instance.destroy();

    const msg = try instance.createDebugUtilsMessenger();
    defer instance.wrapper.destroyDebugUtilsMessengerEXT(instance.handle, msg, null);

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
