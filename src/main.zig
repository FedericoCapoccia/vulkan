const std = @import("std");

const glfw = @import("zglfw");
const vkr = @import("renderer.zig");

pub fn main(init: std.process.Init) !void {
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, false);

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

        const shaders_dir = try std.Io.Dir.openDirAbsolute(init.io, shaders_path, .{});
        defer shaders_dir.close(init.io);

        break :blk try vkr.Renderer.init(.{
            .ctx = &vk_context,
            .window = window,
            .shaders_dir = shaders_dir,
            .io = init.io,
            .allocator = init.gpa,
        });
    };
    defer renderer.destroy();

    while (!window.shouldClose()) {
        glfw.pollEvents();
        try renderer.drawFrame();
    }
}
