const std = @import("std");

const vk = @import("vulkan");

const vkh = @import("vk.zig");
const VulkanContext = @import("context.zig").VulkanContext;

pub const Renderer = struct {
    device_handle: vk.Device,
    device_wrapper: vk.DeviceWrapper,
    graphics_queue_handle: vk.Queue,

    pub const InitInfo = struct {
        ctx: *const VulkanContext,
        extensions: []const [*:0]const u8,
    };

    pub fn init(info: InitInfo) !Renderer {
        const instance = info.ctx.instance();

        const device_bundle = try vkh.createDevice(
            &instance,
            info.ctx.pdev,
            info.ctx.queue_families,
            info.extensions,
        );
        const device_proxy = vk.DeviceProxy.init(device_bundle.handle, &device_bundle.wrapper);
        errdefer device_proxy.destroyDevice(null);

        const gq_handle = device_proxy.getDeviceQueue(info.ctx.queue_families.graphics, 0);

        return Renderer{
            .device_handle = device_bundle.handle,
            .device_wrapper = device_bundle.wrapper,
            .graphics_queue_handle = gq_handle,
        };
    }

    pub fn destroy(self: *const Renderer) void {
        const device_proxy = self.device();
        device_proxy.destroyDevice(null);
    }

    pub fn drawFrame() void {}
    pub fn onResize() void {}

    pub fn device(self: *const Renderer) vk.DeviceProxy {
        return vk.DeviceProxy.init(self.device_handle, &self.device_wrapper);
    }

    pub fn graphics_queue(self: *const Renderer) vk.QueueProxy {
        return vk.QueueProxy.init(self.graphics_queue_handle, &self.device_wrapper);
    }
};
