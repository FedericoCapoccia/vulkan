const std = @import("std");

const glfw = @import("zglfw");

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
    const required_ext = try glfw.getRequiredInstanceExtensions();

    const instance = try Instance.create(required_layers[0..], required_ext, init.gpa);
    defer instance.destroy();

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
