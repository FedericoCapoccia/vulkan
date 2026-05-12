const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

const vkh = @import("vk.zig");

const extra_device_extensions = [_]vkh.EngineExtension{
    .swapchain,
};

const extra_features = [_]vkh.EngineFeature{
    .shader_draw_parameters,
};

pub const VulkanContext = struct {
    instance_handle: vk.Instance,
    instance_wrapper: vk.InstanceWrapper,
    debug_messenger: ?vk.DebugUtilsMessengerEXT,
    surface: vk.SurfaceKHR,
    pdev: vk.PhysicalDevice,
    queue_families: vkh.QueueFamilies,
    profile: vkh.EngineProfile,
    requirements: vkh.EngineRequirements,

    pub const InitInfo = struct {
        window: *glfw.Window,
        log_messages: bool,
        allocator: std.mem.Allocator,
    };

    pub fn init(info: InitInfo) !VulkanContext {
        const base = vk.BaseWrapper.load(glfw.getInstanceProcAddress);

        var instance_extensions: std.ArrayList([*:0]const u8) = .empty;
        defer instance_extensions.deinit(info.allocator);

        try instance_extensions.appendSlice(info.allocator, try glfw.getRequiredInstanceExtensions());
        if (info.log_messages) {
            try instance_extensions.append(info.allocator, vk.extensions.ext_debug_utils.name);
        }

        const requirements = vkh.EngineRequirements{
            .extra_device_extensions = extra_device_extensions[0..],
            .extra_features = extra_features[0..],
        };

        const instance_bundle = try vkh.createInstance(&base, instance_extensions.items, info.log_messages, info.allocator);
        const instance_proxy = vk.InstanceProxy.init(instance_bundle.handle, &instance_bundle.wrapper);
        errdefer {
            if (instance_bundle.debug_messenger) |messenger| {
                instance_proxy.destroyDebugUtilsMessengerEXT(messenger, null);
            }
            instance_proxy.destroyInstance(null);
        }

        var surface: vk.SurfaceKHR = .null_handle;
        try glfw.createWindowSurface(instance_proxy.handle, info.window, null, &surface);
        errdefer instance_proxy.destroySurfaceKHR(surface, null);

        const pdev_bundle = try vkh.selectPhysicalDevice(
            instance_proxy,
            surface,
            &requirements,
            info.allocator,
        );

        return VulkanContext{
            .instance_handle = instance_bundle.handle,
            .instance_wrapper = instance_bundle.wrapper,
            .debug_messenger = instance_bundle.debug_messenger,
            .surface = surface,
            .pdev = pdev_bundle.handle,
            .queue_families = pdev_bundle.queue_families,
            .requirements = requirements,
            .profile = pdev_bundle.profile,
        };
    }

    pub fn destroy(self: *const VulkanContext) void {
        const instance_proxy = self.instance();

        instance_proxy.destroySurfaceKHR(self.surface, null);

        if (self.debug_messenger) |messenger| {
            instance_proxy.destroyDebugUtilsMessengerEXT(messenger, null);
        }

        instance_proxy.destroyInstance(null);
    }

    pub fn instance(self: *const VulkanContext) vk.InstanceProxy {
        return vk.InstanceProxy.init(self.instance_handle, &self.instance_wrapper);
    }
};
