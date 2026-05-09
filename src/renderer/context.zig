const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

const vkh = @import("vk.zig");

pub const VulkanContext = struct {
    instance_handle: vk.Instance,
    instance_wrapper: vk.InstanceWrapper,
    debug_messenger: ?vk.DebugUtilsMessengerEXT,

    pub fn init(log_messages: bool, allocator: std.mem.Allocator) !VulkanContext {
        const base = vk.BaseWrapper.load(glfw.getInstanceProcAddress);

        var extensions: std.ArrayList([*:0]const u8) = .empty;
        defer extensions.deinit(allocator);

        try extensions.appendSlice(allocator, try glfw.getRequiredInstanceExtensions());
        if (log_messages) {
            try extensions.append(allocator, "VK_EXT_debug_utils");
        }

        const instance_bundle = try vkh.createInstance(&base, extensions.items, log_messages, allocator);

        return VulkanContext{
            .instance_handle = instance_bundle.handle,
            .instance_wrapper = instance_bundle.wrapper,
            .debug_messenger = instance_bundle.debug_messenger,
        };
    }

    pub fn destroy(self: *const VulkanContext) void {
        const instance_proxy = self.instance();
        if (self.debug_messenger) |messenger| {
            instance_proxy.destroyDebugUtilsMessengerEXT(messenger, null);
        }
        instance_proxy.destroyInstance(null);
    }

    pub fn instance(self: *const VulkanContext) vk.InstanceProxy {
        return vk.InstanceProxy.init(self.instance_handle, &self.instance_wrapper);
    }
};
