const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

const vkh = @import("vk.zig");
const VulkanContext = @import("context.zig").VulkanContext;

pub const Renderer = struct {
    device_handle: vk.Device,
    device_wrapper: vk.DeviceWrapper,
    graphics_queue_handle: vk.Queue,
    swapchain: vkh.Swapchain,

    pub fn init(ctx: *const VulkanContext, window: *glfw.Window, allocator: std.mem.Allocator) !Renderer {
        const instance = ctx.instance();

        const device_bundle = try vkh.createDevice(
            &instance,
            ctx.pdev,
            ctx.queue_families,
            ctx.profile,
            &ctx.requirements,
        );
        const device_proxy = vk.DeviceProxy.init(device_bundle.handle, &device_bundle.wrapper);
        errdefer device_proxy.destroyDevice(null);

        const gq_handle = device_proxy.getDeviceQueue(ctx.queue_families.graphics, 0);

        const swapchain = try vkh.Swapchain.create(&.{
            .instance = &instance,
            .pdev = ctx.pdev,
            .surface = ctx.surface,
            .device = &device_proxy,
            .window = window,
            .allocator = allocator,
        });
        errdefer swapchain.destroy();

        return Renderer{
            .device_handle = device_bundle.handle,
            .device_wrapper = device_bundle.wrapper,
            .graphics_queue_handle = gq_handle,
            .swapchain = swapchain,
        };
    }

    pub fn destroy(self: *const Renderer) void {
        const device_proxy = self.device();
        device_proxy.deviceWaitIdle() catch {};
        self.swapchain.destroy(&device_proxy);
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
