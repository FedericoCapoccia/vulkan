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

    pub fn init(
        window: *glfw.Window,
        log_messages: bool,
        device_requirements: *const vkh.DeviceRequirements,
        allocator: std.mem.Allocator,
    ) !VulkanContext {
        const base = vk.BaseWrapper.load(glfw.getInstanceProcAddress);

        var ins_extensions: std.ArrayList([*:0]const u8) = .empty;
        defer ins_extensions.deinit(allocator);

        try ins_extensions.appendSlice(allocator, try glfw.getRequiredInstanceExtensions());
        if (log_messages) {
            try ins_extensions.append(allocator, vk.extensions.ext_debug_utils.name);
        }

        const instance_bundle = try vkh.createInstance(&base, ins_extensions.items, log_messages, allocator);
        const instance_proxy = vk.InstanceProxy.init(instance_bundle.handle, &instance_bundle.wrapper);
        errdefer instance_proxy.destroyInstance(null);
        errdefer if (instance_bundle.debug_messenger) |messenger| {
            instance_proxy.destroyDebugUtilsMessengerEXT(messenger, null);
        };

        var surface: vk.SurfaceKHR = undefined;
        try glfw.createWindowSurface(instance_proxy.handle, window, null, &surface);
        errdefer instance_proxy.destroySurfaceKHR(surface, null);

        const pdev_bundle = try vkh.selectPhysicalDevice(
            &instance_proxy,
            surface,
            device_requirements,
            allocator,
        );

        return VulkanContext{
            .instance_handle = instance_bundle.handle,
            .instance_wrapper = instance_bundle.wrapper,
            .debug_messenger = instance_bundle.debug_messenger,
            .surface = surface,
            .pdev = pdev_bundle.handle,
            .queue_families = pdev_bundle.queue_families,
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
