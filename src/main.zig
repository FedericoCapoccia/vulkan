const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

pub fn main(init: std.process.Init) !void {
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, false);

    const window = try glfw.createWindow(800, 600, "Vulkan", null, null);
    defer window.destroy();

    const app_info = vk.ApplicationInfo{
        .p_application_name = "Vulkan",
        .application_version = vk.makeApiVersion(0, 1, 0, 0).toU32(),
        .p_engine_name = "No Engine",
        .engine_version = vk.makeApiVersion(0, 1, 0, 0).toU32(),
        .api_version = vk.API_VERSION_1_4.toU32(),
    };

    const vkb = vk.BaseWrapper.load(glfw.getInstanceProcAddress);
    const glfw_ext = try glfw.getRequiredInstanceExtensions();
    {
        const available = try vkb.enumerateInstanceExtensionPropertiesAlloc(null, init.gpa);
        defer init.gpa.free(available);

        for (glfw_ext) |required_ext_z| {
            const required_ext = std.mem.span(required_ext_z);
            var found = false;
            for (available) |available_ext| {
                const available_name = std.mem.sliceTo(&available_ext.extension_name, 0);
                if (std.mem.eql(u8, required_ext, available_name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                std.log.err("Missing required GLFW Vulkan extension: {s}", .{required_ext});
                return error.MissingRequiredInstanceExtension;
            }
        }
    }

    const create_info = vk.InstanceCreateInfo{
        .p_application_info = &app_info,
        .enabled_extension_count = @intCast(glfw_ext.len),
        .pp_enabled_extension_names = glfw_ext.ptr,
    };

    const instance = try vkb.createInstance(&create_info, null);
    const vki = vk.InstanceWrapper.load(instance, vkb.dispatch.vkGetInstanceProcAddr.?);
    defer vki.destroyInstance(instance, null);

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
