const std = @import("std");

const glfw = @import("zglfw");
const vkr = @import("renderer.zig");

pub fn main(init: std.process.Init) !void {
    glfw.init() catch |err| {
        std.log.err("Failed to initialize GLFW: {}", .{err});
        return error.GLFWError;
    };
    defer glfw.terminate();

    glfw.windowHint(.client_api, .no_api);

    const window = glfw.createWindow(800, 600, "Vulkan", null, null) catch |err| {
        std.log.err("Failed to create GLFW window: {}", .{err});
        return error.GLFWError;
    };
    defer window.destroy();

    var vk_context = vkr.VulkanContext.init(window, init.gpa) catch |err| {
        std.log.err("Failed to initialize VulkanContext: {}", .{err});
        return error.VulkanContextInit;
    };
    defer vk_context.deinit();

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
    defer renderer.deinit();

    window.setUserPointer(&renderer);
    _ = window.setFramebufferSizeCallback(framebufferResizeCallback);

    while (!window.shouldClose()) {
        glfw.pollEvents();
        const frame_result = renderer.drawFrame(window) catch |err| {
            std.log.err("Fatal renderer frame error: {}", .{err});
            return error.RendererFrameFailed;
        };

        switch (frame_result) {
            .rendered, .skipped => {},
            .window_closed => break,
        }
    }
}

fn framebufferResizeCallback(window: *glfw.Window, _: i32, _: i32) callconv(.c) void {
    if (window.getUserPointer(vkr.Renderer)) |renderer| {
        renderer.requestResize();
    } else {
        std.log.err("Failed to convert GLFW user pointer to Renderer object", .{});
    }
}
