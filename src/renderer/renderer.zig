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
    graphics_pipeline: vkh.GraphicsPipeline,

    pub const InitInfo = struct {
        ctx: *const VulkanContext,
        window: *glfw.Window,
        shaders_dir: std.Io.Dir,
        io: std.Io,
        allocator: std.mem.Allocator,
    };

    pub fn init(info: InitInfo) !Renderer {
        const instance = info.ctx.instance();

        const device_bundle = try vkh.createDevice(
            instance,
            info.ctx.pdev,
            info.ctx.queue_families,
            info.ctx.profile,
            &info.ctx.requirements,
        );
        const device_proxy = vk.DeviceProxy.init(device_bundle.handle, &device_bundle.wrapper);
        errdefer device_proxy.destroyDevice(null);

        const gq_handle = device_proxy.getDeviceQueue(info.ctx.queue_families.graphics, 0);

        const swapchain = try vkh.Swapchain.create(&.{
            .instance = instance,
            .pdev = info.ctx.pdev,
            .surface = info.ctx.surface,
            .device = device_proxy,
            .window = info.window,
            .allocator = info.allocator,
        });
        errdefer swapchain.destroy(device_proxy);

        const triangle_shader = try loadShader(info.io, info.allocator, device_proxy, info.shaders_dir, "triangle.spv");
        defer device_proxy.destroyShaderModule(triangle_shader, null);

        const gp = try vkh.GraphicsPipeline.create(.{
            .device = device_proxy,
            .shader = triangle_shader,
            .extent = swapchain.extent,
            .format = swapchain.format.format,
        });
        errdefer gp.destroy(device_proxy);

        return Renderer{
            .device_handle = device_bundle.handle,
            .device_wrapper = device_bundle.wrapper,
            .graphics_queue_handle = gq_handle,
            .swapchain = swapchain,
            .graphics_pipeline = gp,
        };
    }

    pub fn destroy(self: *const Renderer) void {
        const device_proxy = self.device();
        device_proxy.deviceWaitIdle() catch {};
        self.graphics_pipeline.destroy(device_proxy);
        self.swapchain.destroy(device_proxy);
        device_proxy.destroyDevice(null);
    }

    pub fn drawFrame() void {}

    // Create new swapchain with old handle, if image format changes invalidate pipeline
    pub fn recreateSwapchain(self: *Renderer, window: *glfw.Window) void {
        _ = self;
        _ = window;
    }

    pub fn device(self: *const Renderer) vk.DeviceProxy {
        return vk.DeviceProxy.init(self.device_handle, &self.device_wrapper);
    }

    pub fn graphicsQueue(self: *const Renderer) vk.QueueProxy {
        return vk.QueueProxy.init(self.graphics_queue_handle, &self.device_wrapper);
    }
};

fn loadShader(
    io: std.Io,
    allocator: std.mem.Allocator,
    device: vk.DeviceProxy,
    dir: std.Io.Dir,
    name: []const u8,
) !vk.ShaderModule {
    const code = try dir.readFileAllocOptions(
        io,
        name,
        allocator,
        .limited(1024 * 1024),
        .of(u32),
        null,
    );
    defer allocator.free(code);

    if (code.len % @sizeOf(u32) != 0) {
        return error.InvalidSpirVSize;
    }

    const cinfo = vk.ShaderModuleCreateInfo{
        .code_size = code.len,
        .p_code = std.mem.bytesAsSlice(u32, code).ptr,
    };

    return device.createShaderModule(&cinfo, null);
}
