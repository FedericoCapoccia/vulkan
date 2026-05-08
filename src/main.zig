const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

const PhysicalDevice = @import("vk/physical_device.zig").PhysicalDevice;
const Instance = @import("vk/instance.zig").Instance;
const Device = @import("vk/device.zig").Device;
const Swapchain = @import("vk/swapchain.zig").Swapchain;

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
    defer vk_instance.destroy();
    const instance = vk_instance.proxy();

    var surface: vk.SurfaceKHR = undefined;
    try glfw.createWindowSurface(vk_instance.handle, window, null, &surface);
    defer instance.destroySurfaceKHR(surface, null);

    const required_device_ext = [_][*:0]const u8{
        "VK_KHR_swapchain",
        "VK_EXT_extended_dynamic_state",
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

    const vk_device = try Device.create(&instance, physical_device, required_device_ext[0..], init.gpa);
    const device = vk_device.proxy();
    defer device.destroyDevice(null);

    const exe_dir = try std.process.executableDirPathAlloc(init.io, init.gpa);
    defer init.gpa.free(exe_dir);

    const shader_dir = try std.fs.path.join(init.gpa, &.{ exe_dir, "resources", "shaders" });
    defer init.gpa.free(shader_dir);

    const swapchain = try Swapchain.create(
        &instance,
        &physical_device,
        surface,
        &device,
        window,
        init.gpa,
    );
    defer swapchain.destroy(device);

    const triangle_shader = try createShaderModule(
        init.io,
        init.gpa,
        &device,
        shader_dir,
        "triangle.spv",
    );
    defer device.destroyShaderModule(triangle_shader, null);

    // while (!window.shouldClose()) {
    //     glfw.pollEvents();
    // }
}

fn createShaderModule(
    io: std.Io,
    allocator: std.mem.Allocator,
    device: *const vk.DeviceProxy,
    shader_dir: []const u8,
    filename: []const u8,
) !vk.ShaderModule {
    const path = try std.fs.path.join(allocator, &.{ shader_dir, filename });
    defer allocator.free(path);

    const code = try std.Io.Dir.cwd().readFileAllocOptions(
        io,
        path,
        allocator,
        .limited(1024 * 1024),
        .of(u32),
        null,
    );
    defer allocator.free(code);

    if (code.len % @sizeOf(u32) != 0) return error.InvalidSpirVSize;

    const cinfo = vk.ShaderModuleCreateInfo{
        .code_size = code.len,
        .p_code = std.mem.bytesAsSlice(u32, code).ptr,
    };

    return device.createShaderModule(&cinfo, null);
}
