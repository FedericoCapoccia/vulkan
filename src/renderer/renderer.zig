const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

const vkh = @import("vk.zig");
const VulkanContext = @import("context.zig").VulkanContext;

const MAX_FIF = 2;

pub const FrameData = struct {
    command_pool: vk.CommandPool,
    command_buffer: vk.CommandBuffer,
    image_available: vk.Semaphore,
    in_flight: vk.Fence,

    pub fn create(device: vk.DeviceProxy, queue_family: u32) !FrameData {
        const pool_cinfo = vk.CommandPoolCreateInfo{
            .flags = .{ .transient_bit = true },
            .queue_family_index = queue_family,
        };
        const pool = try device.createCommandPool(&pool_cinfo, null);
        errdefer device.destroyCommandPool(pool, null);

        var buffers: [1]vk.CommandBuffer = undefined;
        const buffer_cinfo = vk.CommandBufferAllocateInfo{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = 1,
        };
        try device.allocateCommandBuffers(&buffer_cinfo, buffers[0..].ptr);

        const image_available = try device.createSemaphore(&.{}, null);
        errdefer device.destroySemaphore(image_available, null);

        const in_flight = try device.createFence(&.{
            .flags = .{ .signaled_bit = true },
        }, null);
        errdefer device.destroyFence(in_flight, null);

        return .{
            .command_pool = pool,
            .command_buffer = buffers[0],
            .image_available = image_available,
            .in_flight = in_flight,
        };
    }

    pub fn destroy(self: *const FrameData, device: vk.DeviceProxy) void {
        device.destroySemaphore(self.image_available, null);
        device.destroyFence(self.in_flight, null);
        device.destroyCommandPool(self.command_pool, null);
    }

    pub fn cmd(self: *const FrameData, device: vk.DeviceProxy) vk.CommandBufferProxy {
        return vk.CommandBufferProxy.init(self.command_buffer, device.wrapper);
    }
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    device_handle: vk.Device,
    device_wrapper: vk.DeviceWrapper,
    graphics_queue_handle: vk.Queue,
    swapchain: vkh.Swapchain,
    graphics_pipeline: vkh.GraphicsPipeline,
    frames: [MAX_FIF]FrameData,
    render_finished: []vk.Semaphore,
    current_frame: usize = 0,

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

        var frames: [MAX_FIF]FrameData = undefined;
        var frame_count: usize = 0;
        errdefer {
            for (frames[0..frame_count]) |*frame| {
                frame.destroy(device_proxy);
            }
        }

        for (&frames) |*frame| {
            frame.* = try FrameData.create(
                device_proxy,
                info.ctx.queue_families.graphics,
            );
            frame_count += 1;
        }

        const render_finished = try info.allocator.alloc(vk.Semaphore, swapchain.images.len);
        var render_finished_count: usize = 0;
        errdefer {
            for (render_finished[0..render_finished_count]) |semaphore| {
                device_proxy.destroySemaphore(semaphore, null);
            }
            info.allocator.free(render_finished);
        }

        for (render_finished) |*semaphore| {
            semaphore.* = try device_proxy.createSemaphore(&.{}, null);
            render_finished_count += 1;
        }

        return Renderer{
            .allocator = info.allocator,
            .device_handle = device_bundle.handle,
            .device_wrapper = device_bundle.wrapper,
            .graphics_queue_handle = gq_handle,
            .swapchain = swapchain,
            .graphics_pipeline = gp,
            .frames = frames,
            .render_finished = render_finished,
        };
    }

    pub fn destroy(self: *const Renderer) void {
        const device_proxy = self.device();
        device_proxy.deviceWaitIdle() catch {};

        for (self.render_finished) |semaphore| {
            device_proxy.destroySemaphore(semaphore, null);
        }
        self.allocator.free(self.render_finished);

        for (&self.frames) |*frame| {
            frame.destroy(device_proxy);
        }

        self.graphics_pipeline.destroy(device_proxy);
        self.swapchain.destroy(device_proxy);
        device_proxy.destroyDevice(null);
    }

    pub fn device(self: *const Renderer) vk.DeviceProxy {
        return vk.DeviceProxy.init(self.device_handle, &self.device_wrapper);
    }

    pub fn graphicsQueue(self: *const Renderer) vk.QueueProxy {
        return vk.QueueProxy.init(self.graphics_queue_handle, &self.device_wrapper);
    }

    pub fn drawFrame(self: *Renderer) !void {
        const dev = self.device();
        const graphics_queue = self.graphicsQueue();
        const frame = &self.frames[self.current_frame];

        const fences = [_]vk.Fence{frame.in_flight};
        const wait_result = try dev.waitForFences(fences[0..], .true, std.math.maxInt(u64));
        if (wait_result != .success) return error.WaitForFrameFenceFailed;

        const acquire = try dev.acquireNextImageKHR(
            self.swapchain.handle,
            std.math.maxInt(u64),
            frame.image_available,
            .null_handle,
        );

        try dev.resetFences(fences[0..]);
        try dev.resetCommandPool(frame.command_pool, .{});

        const cmd = frame.cmd(dev);
        try self.recordCommandBuffer(cmd, acquire.image_index);
        const render_finished = self.render_finished[acquire.image_index];

        const command_buffers = [_]vk.CommandBufferSubmitInfo{.{
            .command_buffer = frame.command_buffer,
            .device_mask = 0,
        }};

        const wait_semaphores = [_]vk.SemaphoreSubmitInfo{.{
            .semaphore = frame.image_available,
            .stage_mask = .{ .color_attachment_output_bit = true },
            .device_index = 0,
            .value = 0,
        }};

        const signal_semaphores = [_]vk.SemaphoreSubmitInfo{.{
            .semaphore = render_finished,
            .stage_mask = .{ .color_attachment_output_bit = true },
            .device_index = 0,
            .value = 0,
        }};

        const submit_info = [_]vk.SubmitInfo2{.{
            .wait_semaphore_info_count = wait_semaphores.len,
            .p_wait_semaphore_infos = wait_semaphores[0..].ptr,
            .command_buffer_info_count = command_buffers.len,
            .p_command_buffer_infos = command_buffers[0..].ptr,
            .signal_semaphore_info_count = signal_semaphores.len,
            .p_signal_semaphore_infos = signal_semaphores[0..].ptr,
        }};

        try graphics_queue.submit2(submit_info[0..], frame.in_flight);

        const present_wait_semaphores = [_]vk.Semaphore{render_finished};
        const present_swapchains = [_]vk.SwapchainKHR{self.swapchain.handle};
        const present_image_indices = [_]u32{acquire.image_index};
        const present_info = vk.PresentInfoKHR{
            .wait_semaphore_count = present_wait_semaphores.len,
            .p_wait_semaphores = present_wait_semaphores[0..].ptr,
            .swapchain_count = present_swapchains.len,
            .p_swapchains = present_swapchains[0..].ptr,
            .p_image_indices = present_image_indices[0..].ptr,
        };
        const present_result = try graphics_queue.presentKHR(&present_info);
        if (present_result != .success) return error.PresentFailed;
        self.current_frame = (self.current_frame + 1) % self.frames.len;
    }

    fn recordCommandBuffer(self: *Renderer, cmd: vk.CommandBufferProxy, image_index: u32) !void {
        const begin_info = vk.CommandBufferBeginInfo{
            .flags = .{ .one_time_submit_bit = true },
        };
        try cmd.beginCommandBuffer(&begin_info);

        transitionImageLayout(
            cmd,
            self.swapchain.images[image_index],
            .undefined,
            .color_attachment_optimal,
            .{},
            .{ .color_attachment_write_bit = true },
            .{ .color_attachment_output_bit = true },
            .{ .color_attachment_output_bit = true },
        );

        const clear_color = vk.ClearValue{
            .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 0.0 } },
        };

        const color_attachments = [_]vk.RenderingAttachmentInfo{.{
            .image_view = self.swapchain.views[image_index],
            .image_layout = .color_attachment_optimal,
            .resolve_mode = .{},
            .resolve_image_view = .null_handle,
            .resolve_image_layout = .undefined,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = clear_color,
        }};

        const rendering_info = vk.RenderingInfo{
            .render_area = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swapchain.extent,
            },
            .layer_count = 1,
            .view_mask = 0,
            .color_attachment_count = color_attachments.len,
            .p_color_attachments = color_attachments[0..].ptr,
        };
        cmd.beginRendering(&rendering_info);

        cmd.bindPipeline(.graphics, self.graphics_pipeline.handle);

        const viewports = [_]vk.Viewport{.{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(self.swapchain.extent.width),
            .height = @floatFromInt(self.swapchain.extent.height),
            .min_depth = 0.0,
            .max_depth = 1.0,
        }};
        cmd.setViewport(0, viewports[0..]);

        const scissors = [_]vk.Rect2D{.{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain.extent,
        }};
        cmd.setScissor(0, scissors[0..]);

        cmd.draw(3, 1, 0, 0);

        cmd.endRendering();

        transitionImageLayout(
            cmd,
            self.swapchain.images[image_index],
            .color_attachment_optimal,
            .present_src_khr,
            .{ .color_attachment_write_bit = true },
            .{},
            .{ .color_attachment_output_bit = true },
            .{ .bottom_of_pipe_bit = true },
        );
        try cmd.endCommandBuffer();
    }

    // Create new swapchain with old handle, if image format changes invalidate pipeline
    pub fn recreateSwapchain(self: *Renderer, window: *glfw.Window) void {
        _ = self;
        _ = window;
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

fn transitionImageLayout(
    cmd: vk.CommandBufferProxy,
    image: vk.Image,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    src_access_mask: vk.AccessFlags2,
    dst_access_mask: vk.AccessFlags2,
    src_stage_mask: vk.PipelineStageFlags2,
    dst_stage_mask: vk.PipelineStageFlags2,
) void {
    const barriers = [_]vk.ImageMemoryBarrier2{.{
        .src_stage_mask = src_stage_mask,
        .src_access_mask = src_access_mask,
        .dst_stage_mask = dst_stage_mask,
        .dst_access_mask = dst_access_mask,
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }};
    const dependency_info = vk.DependencyInfo{
        .image_memory_barrier_count = barriers.len,
        .p_image_memory_barriers = barriers[0..].ptr,
    };
    cmd.pipelineBarrier2(&dependency_info);
}
