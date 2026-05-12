const std = @import("std");

const glfw = @import("zglfw");
const vkr = @import("renderer.zig");

pub fn main(init: std.process.Init) !void {
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.client_api, .no_api);

    const window = try glfw.createWindow(800, 600, "Vulkan", null, null);
    defer window.destroy();

    const vk_context = try vkr.VulkanContext.init(.{
        .window = window,
        .log_messages = true,
        .allocator = init.gpa,
    });
    defer vk_context.destroy();

    var renderer = blk: {
        const exe_dir = try std.process.executableDirPathAlloc(init.io, init.gpa);
        defer init.gpa.free(exe_dir);

        const shaders_path = try std.Io.Dir.path.join(init.gpa, &.{ exe_dir, "resources", "shaders" });
        defer init.gpa.free(shaders_path);

        break :blk try vkr.Renderer.init(.{
            .ctx = &vk_context,
            .window = window,
            .shaders_dir_path = shaders_path,
            .io = init.io,
            .allocator = init.gpa,
        });
    };
    defer renderer.destroy();

    window.setUserPointer(&renderer);
    const res_cb = window.setFramebufferSizeCallback(framebufferResizeCallback);
    _ = res_cb;

    while (!window.shouldClose()) {
        glfw.pollEvents();
        try renderer.drawFrame(window);
    }
}

fn framebufferResizeCallback(window: *glfw.Window, _: i32, _: i32) callconv(.c) void {
    if (window.getUserPointer(vkr.Renderer)) |renderer| {
        renderer.requestResize();
    } else {
        std.log.err("Failed to convert GLFW user pointer to Renderer object", .{});
    }
}
