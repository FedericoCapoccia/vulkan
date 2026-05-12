const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

const rvk = @import("vk.zig");

const extra_device_extensions = [_]rvk.EngineExtension{
    .swapchain,
};

const extra_features = [_]rvk.EngineFeature{
    .shader_draw_parameters,
};

const enable_validation = switch (@import("builtin").mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

pub const VulkanContext = struct {
    instance: rvk.Instance,
    surface: vk.SurfaceKHR,
    pdev: rvk.PhysicalDevice,
    requirements: rvk.EngineRequirements,

    pub const InitError = error{
        OutOfMemory,
        InstanceInitFailed,
        SurfaceCreationFailed,
        PhysicalDeviceSelectionFailed,
    };

    pub fn init(window: *glfw.Window, allocator: std.mem.Allocator) InitError!VulkanContext {
        const base = vk.BaseWrapper.load(glfw.getInstanceProcAddress);

        var instance_extensions: std.ArrayList([*:0]const u8) = .empty;
        defer instance_extensions.deinit(allocator);

        const glfw_ext = glfw.getRequiredInstanceExtensions() catch |err| {
            std.log.err("Failed to get required GLFW instance extensions: {}", .{err});
            return InitError.InstanceInitFailed;
        };
        try instance_extensions.appendSlice(allocator, glfw_ext);

        if (enable_validation) {
            try instance_extensions.append(allocator, vk.extensions.ext_debug_utils.name);
        }

        const requirements = rvk.EngineRequirements{
            .extra_device_extensions = extra_device_extensions[0..],
            .extra_features = extra_features[0..],
        };

        var instance = rvk.Instance.init(&.{
            .base = base,
            .enable_messenger = enable_validation,
            .extensions = instance_extensions.items,
            .allocator = allocator,
        }) catch |err| {
            std.log.err("Failed to initialize Vulkan instance: {}", .{err});
            return error.InstanceInitFailed;
        };
        errdefer instance.deinit();

        const instance_proxy = instance.proxy();

        var surface: vk.SurfaceKHR = .null_handle;
        glfw.createWindowSurface(instance.handle, window, null, &surface) catch |err| {
            std.log.err("Failed to create Vulkan window surface: {}", .{err});
            return error.SurfaceCreationFailed;
        };
        errdefer instance_proxy.destroySurfaceKHR(surface, null);

        const pdev = rvk.PhysicalDevice.select(&.{
            .instance = instance_proxy,
            .surface = surface,
            .requirements = &requirements,
            .allocator = allocator,
        }) catch |err| {
            std.log.err("Failed to select Vulkan physical device: {}", .{err});
            return error.PhysicalDeviceSelectionFailed;
        };

        return VulkanContext{
            .instance = instance,
            .surface = surface,
            .pdev = pdev,
            .requirements = requirements,
        };
    }

    pub fn destroy(self: *VulkanContext) void {
        self.instance.proxy().destroySurfaceKHR(self.surface, null);
        self.instance.deinit();
    }
};
