const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

const vkh = @import("vk.zig");

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

        const device_extensions = [_][*:0]const u8{
            vk.extensions.khr_swapchain.name,
        };

        const requirements = try vkh.EngineRequirements.init(
            info.allocator,
            instance_extensions.items,
            device_extensions[0..],
            &.{
                .shader_draw_parameters,
            },
        );
        errdefer requirements.deinit();

        const instance_bundle = try vkh.createInstance(&base, &requirements, info.log_messages, info.allocator);
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
            &instance_proxy,
            surface,
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
            .profile = .minimal, // TODO: fetch from selected pdev
        };
    }

    pub fn destroy(self: *const VulkanContext) void {
        self.requirements.deinit();

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
