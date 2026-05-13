const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");
const vma = @import("vma");

const rvk = @import("vk.zig");
const VulkanContext = @import("context.zig").VulkanContext;

const max_frames_in_flight = 2;

const FrameData = struct {
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

    pub fn deinit(self: *FrameData, device: vk.DeviceProxy) void {
        device.destroySemaphore(self.image_available, null);
        device.destroyFence(self.in_flight, null);
        device.destroyCommandPool(self.command_pool, null);
    }

    pub fn cmd(self: *const FrameData, device: vk.DeviceProxy) vk.CommandBufferProxy {
        return vk.CommandBufferProxy.init(self.command_buffer, device.wrapper);
    }
};

const Vertex = extern struct {
    pos: [2]f32,
    color: [3]f32,

    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    const attribute_descriptions = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
    };
};

comptime {
    std.debug.assert(@sizeOf(Vertex) == 20);
    std.debug.assert(@offsetOf(Vertex, "pos") == 0);
    std.debug.assert(@offsetOf(Vertex, "color") == 8);
}

const vertices = [_]Vertex{
    .{
        .pos = .{ 0.0, -0.5 },
        .color = .{ 1.0, 0.0, 0.0 },
    },
    .{
        .pos = .{ 0.5, 0.5 },
        .color = .{ 0.0, 1.0, 0.0 },
    },
    .{
        .pos = .{ -0.5, 0.5 },
        .color = .{ 0.0, 0.0, 1.0 },
    },
};

const VertexBuffer = struct {
    handle: vk.Buffer,
    allocation: vma.VmaAllocation,

    pub fn create(
        device: *const rvk.Device,
        queue_family: u32,
        queue: vk.QueueProxy,
    ) !VertexBuffer {
        const vertex_bytes = std.mem.sliceAsBytes(vertices[0..]);

        const staging = try AllocatedBuffer.create(
            device,
            vertex_bytes.len,
            vma.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vma.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        defer staging.deinit(device);

        try checkVma(vma.vmaCopyMemoryToAllocation(
            device.vma,
            @ptrCast(&vertices),
            staging.allocation,
            0,
            @intCast(vertex_bytes.len),
        ));

        const vertex = try AllocatedBuffer.create(
            device,
            vertex_bytes.len,
            vma.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vma.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            vma.VMA_MEMORY_USAGE_GPU_ONLY,
        );
        errdefer vertex.deinit(device);

        try copyBuffer(
            device.proxy(),
            queue,
            queue_family,
            staging.handle,
            vertex.handle,
            @intCast(vertex_bytes.len),
        );

        return .{
            .handle = vertex.handle,
            .allocation = vertex.allocation,
        };
    }

    pub fn deinit(self: *const VertexBuffer, device: *const rvk.Device) void {
        vma.vmaDestroyBuffer(
            device.vma,
            @ptrFromInt(@intFromEnum(self.handle)),
            self.allocation,
        );
    }
};

const AllocatedBuffer = struct {
    handle: vk.Buffer,
    allocation: vma.VmaAllocation,

    fn create(
        device: *const rvk.Device,
        size: usize,
        usage: c_int,
        memory_usage: c_int,
    ) !AllocatedBuffer {
        const buffer_cinfo = vma.VkBufferCreateInfo{
            .sType = @intCast(vma.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO),
            .size = @intCast(size),
            .usage = @intCast(usage),
            .sharingMode = @intCast(vma.VK_SHARING_MODE_EXCLUSIVE),
        };
        const allocation_cinfo = vma.VmaAllocationCreateInfo{
            .usage = @intCast(memory_usage),
        };

        var buffer: vma.VkBuffer = null;
        var allocation: vma.VmaAllocation = null;
        try checkVma(vma.vmaCreateBuffer(
            device.vma,
            &buffer_cinfo,
            &allocation_cinfo,
            &buffer,
            &allocation,
            null,
        ));
        errdefer vma.vmaDestroyBuffer(device.vma, buffer, allocation);

        const buffer_handle = buffer orelse return error.VmaError;
        return .{
            .handle = @enumFromInt(@intFromPtr(buffer_handle)),
            .allocation = allocation,
        };
    }

    fn deinit(self: *const AllocatedBuffer, device: *const rvk.Device) void {
        vma.vmaDestroyBuffer(
            device.vma,
            @ptrFromInt(@intFromEnum(self.handle)),
            self.allocation,
        );
    }
};

pub const Renderer = struct {
    ctx: *const VulkanContext,
    io: std.Io,
    allocator: std.mem.Allocator,
    device: rvk.Device,
    graphics_queue_handle: vk.Queue,
    swapchain: rvk.Swapchain,
    shaders_dir_path: []const u8,
    graphics_pipeline: rvk.GraphicsPipeline,
    vertex_buffer: VertexBuffer,
    frames: [max_frames_in_flight]FrameData,
    render_finished: []vk.Semaphore,
    current_frame: usize = 0,
    framebuffer_resized: bool = false,

    pub const InitInfo = struct {
        ctx: *const VulkanContext,
        window: *glfw.Window,
        shaders_dir_path: []const u8,
        io: std.Io,
        allocator: std.mem.Allocator,
    };

    pub const DrawFrameError = error{
        FrameSyncFailed,
        AcquireFailed,
        CommandRecordingFailed,
        SubmitFailed,
        PresentFailed,
        SwapchainRecreateFailed,
    };

    pub const DrawFrameResult = enum {
        rendered,
        skipped,
        window_closed,
    };

    pub fn init(info: InitInfo) !Renderer {
        const instance = info.ctx.instance.proxy();

        var device = try rvk.Device.create(&.{
            .base = info.ctx.base,
            .instance = info.ctx.instance,
            .physical_device = info.ctx.pdev,
            .requirements = &info.ctx.requirements,
        });
        errdefer device.destroy();

        const device_proxy = device.proxy();
        const gq_handle = device_proxy.getDeviceQueue(info.ctx.pdev.queue_families.graphics, 0);

        const swapchain = try rvk.Swapchain.create(&.{
            .instance = instance,
            .pdev = info.ctx.pdev.handle,
            .surface = info.ctx.surface,
            .device = device_proxy,
            .window = info.window,
            .allocator = info.allocator,
        });
        errdefer swapchain.deinit(device_proxy);

        const shaders_dir_path = try info.allocator.dupe(u8, info.shaders_dir_path);
        errdefer info.allocator.free(shaders_dir_path);
        const shaders_dir = try std.Io.Dir.openDirAbsolute(info.io, shaders_dir_path, .{});
        defer shaders_dir.close(info.io);

        const triangle_shader = try loadShader(info.io, info.allocator, device_proxy, shaders_dir, "triangle.spv");
        defer device_proxy.destroyShaderModule(triangle_shader, null);

        const gp = try rvk.GraphicsPipeline.create(.{
            .device = device_proxy,
            .shader = triangle_shader,
            .format = swapchain.format.format,
            .binding_desc = Vertex.binding_description,
            .binding_attr = &Vertex.attribute_descriptions,
        });
        errdefer gp.deinit(device_proxy);

        const vertex_buffer = try VertexBuffer.create(
            &device,
            info.ctx.pdev.queue_families.graphics,
            vk.QueueProxy.init(gq_handle, &device.wrapper),
        );
        errdefer vertex_buffer.deinit(&device);

        var frames: [max_frames_in_flight]FrameData = undefined;
        var frame_count: usize = 0;
        errdefer {
            for (frames[0..frame_count]) |*frame| {
                frame.deinit(device_proxy);
            }
        }

        for (&frames) |*frame| {
            frame.* = try FrameData.create(device_proxy, info.ctx.pdev.queue_families.graphics);
            frame_count += 1;
        }

        const render_finished = try createRenderSemaphores(device_proxy, swapchain.images.len, info.allocator);

        return Renderer{
            .ctx = info.ctx,
            .io = info.io,
            .allocator = info.allocator,
            .device = device,
            .graphics_queue_handle = gq_handle,
            .swapchain = swapchain,
            .shaders_dir_path = shaders_dir_path,
            .graphics_pipeline = gp,
            .vertex_buffer = vertex_buffer,
            .frames = frames,
            .render_finished = render_finished,
        };
    }

    pub fn deinit(self: *Renderer) void {
        const device_proxy = self.device.proxy();
        device_proxy.deviceWaitIdle() catch |err| {
            std.log.err("Failed to wait for Vulkan device idle during teardown: {}", .{err});
        };

        for (self.render_finished) |semaphore| {
            device_proxy.destroySemaphore(semaphore, null);
        }
        self.allocator.free(self.render_finished);

        for (&self.frames) |*frame| {
            frame.deinit(device_proxy);
        }

        self.graphics_pipeline.deinit(device_proxy);
        self.vertex_buffer.deinit(&self.device);
        self.allocator.free(self.shaders_dir_path);

        self.swapchain.deinit(device_proxy);
        self.device.destroy();
    }

    pub fn graphicsQueue(self: *const Renderer) vk.QueueProxy {
        return vk.QueueProxy.init(self.graphics_queue_handle, &self.device.wrapper);
    }

    pub fn requestResize(self: *Renderer) void {
        self.framebuffer_resized = true;
    }

    pub fn drawFrame(self: *Renderer, window: *glfw.Window) DrawFrameError!DrawFrameResult {
        const dev = self.device.proxy();
        const graphics_queue = self.graphicsQueue();
        const frame = &self.frames[self.current_frame];

        const fences = [_]vk.Fence{frame.in_flight};
        const wait_result = dev.waitForFences(fences[0..], .true, std.math.maxInt(u64)) catch |err| {
            std.log.err("Failed to wait for frame fence: {}", .{err});
            return error.FrameSyncFailed;
        };
        if (wait_result != .success) {
            std.log.err("Frame fence wait returned {s}", .{@tagName(wait_result)});
            return error.FrameSyncFailed;
        }

        const acquire = dev.acquireNextImageKHR(
            self.swapchain.handle,
            std.math.maxInt(u64),
            frame.image_available,
            .null_handle,
        ) catch |err| switch (err) {
            error.OutOfDateKHR => {
                self.recreateSwapchain(window) catch |recreate_err| switch (recreate_err) {
                    error.WindowClosed => return .window_closed,
                    else => {
                        std.log.err("Failed to recreate swapchain after image acquire: {}", .{recreate_err});
                        return error.SwapchainRecreateFailed;
                    },
                };
                return .skipped;
            },
            else => {
                std.log.err("Failed to acquire swapchain image: {}", .{err});
                return error.AcquireFailed;
            },
        };

        const should_recreate = self.framebuffer_resized or acquire.result == .suboptimal_khr;

        dev.resetCommandPool(frame.command_pool, .{}) catch |err| {
            std.log.err("Failed to reset frame command pool: {}", .{err});
            return error.CommandRecordingFailed;
        };

        const cmd = frame.cmd(dev);
        self.recordCommandBuffer(cmd, acquire.image_index) catch |err| {
            std.log.err("Failed to record frame command buffer: {}", .{err});
            return error.CommandRecordingFailed;
        };
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
            .stage_mask = .{ .all_commands_bit = true },
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

        dev.resetFences(fences[0..]) catch |err| {
            std.log.err("Failed to reset frame fence: {}", .{err});
            return error.FrameSyncFailed;
        };
        graphics_queue.submit2(submit_info[0..], frame.in_flight) catch |err| {
            std.log.err("Failed to submit frame commands: {}", .{err});
            return error.SubmitFailed;
        };

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

        const present_result = graphics_queue.presentKHR(&present_info) catch |err| switch (err) {
            error.OutOfDateKHR => {
                self.recreateSwapchain(window) catch |recreate_err| switch (recreate_err) {
                    error.WindowClosed => return .window_closed,
                    else => {
                        std.log.err("Failed to recreate swapchain after present: {}", .{recreate_err});
                        return error.SwapchainRecreateFailed;
                    },
                };
                return .skipped;
            },
            else => {
                std.log.err("Failed to present frame: {}", .{err});
                return error.PresentFailed;
            },
        };

        if (present_result != .success and present_result != .suboptimal_khr) {
            std.log.err("Present returned {s}", .{@tagName(present_result)});
            return error.PresentFailed;
        }

        self.current_frame = (self.current_frame + 1) % self.frames.len;

        if (present_result == .suboptimal_khr or should_recreate) {
            self.recreateSwapchain(window) catch |err| switch (err) {
                error.WindowClosed => return .window_closed,
                else => {
                    std.log.err("Failed to recreate swapchain after frame: {}", .{err});
                    return error.SwapchainRecreateFailed;
                },
            };
        }

        return .rendered;
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

        const vertex_buffers = [_]vk.Buffer{self.vertex_buffer.handle};
        const vertex_offsets = [_]vk.DeviceSize{0};
        cmd.bindVertexBuffers(0, vertex_buffers[0..], vertex_offsets[0..]);

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

        cmd.draw(@intCast(vertices.len), 1, 0, 0);

        cmd.endRendering();

        transitionImageLayout(
            cmd,
            self.swapchain.images[image_index],
            .color_attachment_optimal,
            .present_src_khr,
            .{ .color_attachment_write_bit = true },
            .{},
            .{ .color_attachment_output_bit = true },
            .{},
        );
        try cmd.endCommandBuffer();
    }

    // Create new swapchain with old handle, if image format changes invalidate pipeline
    // TODO: I still need to find a way to not depend on the window object
    fn recreateSwapchain(self: *Renderer, window: *glfw.Window) !void {
        const dev = self.device.proxy();

        try dev.deviceWaitIdle();

        const old_swapchain = self.swapchain;
        const old_pipeline = self.graphics_pipeline;
        const old_render_finished = self.render_finished;

        const new_swapchain = try rvk.Swapchain.create(&.{
            .instance = self.ctx.instance.proxy(),
            .pdev = self.ctx.pdev.handle,
            .surface = self.ctx.surface,
            .device = dev,
            .window = window,
            .allocator = self.allocator,
            .old_swapchain = old_swapchain.handle,
        });
        errdefer new_swapchain.deinit(dev);

        const new_render_finished = try createRenderSemaphores(dev, new_swapchain.images.len, self.allocator);
        errdefer {
            for (new_render_finished) |semaphore| {
                dev.destroySemaphore(semaphore, null);
            }
            self.allocator.free(new_render_finished);
        }

        const format_changed = new_swapchain.format.format != old_swapchain.format.format;
        var new_pipeline: ?rvk.GraphicsPipeline = null;
        errdefer if (new_pipeline) |pipeline| {
            pipeline.deinit(dev);
        };

        if (format_changed) {
            const shaders_dir = try std.Io.Dir.openDirAbsolute(self.io, self.shaders_dir_path, .{});
            defer shaders_dir.close(self.io);
            const triangle_shader = try loadShader(self.io, self.allocator, dev, shaders_dir, "triangle.spv");
            defer dev.destroyShaderModule(triangle_shader, null);

            new_pipeline = try rvk.GraphicsPipeline.create(.{
                .device = dev,
                .shader = triangle_shader,
                .format = new_swapchain.format.format,
                .binding_desc = Vertex.binding_description,
                .binding_attr = &Vertex.attribute_descriptions,
            });
        }

        self.swapchain = new_swapchain;
        self.render_finished = new_render_finished;
        if (new_pipeline) |pipeline| {
            self.graphics_pipeline = pipeline;
        }
        self.framebuffer_resized = false;

        for (old_render_finished) |semaphore| {
            dev.destroySemaphore(semaphore, null);
        }
        self.allocator.free(old_render_finished);

        old_swapchain.deinit(dev);
        if (format_changed) {
            old_pipeline.deinit(dev);
        }
    }
};

fn loadShader(
    io: std.Io,
    allocator: std.mem.Allocator,
    device: vk.DeviceProxy,
    dir: std.Io.Dir,
    name: []const u8,
) !vk.ShaderModule {
    const shader_code_bytes = try dir.readFileAllocOptions(
        io,
        name,
        allocator,
        .limited(1024 * 1024),
        .of(u32),
        null,
    );
    defer allocator.free(shader_code_bytes);

    if (shader_code_bytes.len % @sizeOf(u32) != 0) {
        return error.InvalidSpirVSize;
    }
    const shader_code_words = std.mem.bytesAsSlice(u32, shader_code_bytes);

    const cinfo = vk.ShaderModuleCreateInfo{
        .code_size = shader_code_bytes.len,
        .p_code = shader_code_words.ptr,
    };

    return device.createShaderModule(&cinfo, null);
}

fn createRenderSemaphores(dev: vk.DeviceProxy, image_count: usize, allocator: std.mem.Allocator) ![]vk.Semaphore {
    const semaphores = try allocator.alloc(vk.Semaphore, image_count);
    var count: usize = 0;
    errdefer {
        for (semaphores[0..count]) |semaphore| {
            dev.destroySemaphore(semaphore, null);
        }
        allocator.free(semaphores);
    }

    for (semaphores) |*semaphore| {
        semaphore.* = try dev.createSemaphore(&.{}, null);
        count += 1;
    }

    return semaphores;
}

fn copyBuffer(
    device: vk.DeviceProxy,
    queue: vk.QueueProxy,
    queue_family: u32,
    src: vk.Buffer,
    dst: vk.Buffer,
    size: vk.DeviceSize,
) !void {
    const pool = try device.createCommandPool(&.{
        .flags = .{ .transient_bit = true },
        .queue_family_index = queue_family,
    }, null);
    defer device.destroyCommandPool(pool, null);

    var buffers: [1]vk.CommandBuffer = undefined;
    try device.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, buffers[0..].ptr);

    const cmd = vk.CommandBufferProxy.init(buffers[0], device.wrapper);
    try cmd.beginCommandBuffer(&.{
        .flags = .{ .one_time_submit_bit = true },
    });

    const copy_regions = [_]vk.BufferCopy{.{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    }};
    cmd.copyBuffer(src, dst, copy_regions[0..]);
    try cmd.endCommandBuffer();

    const command_buffers = [_]vk.CommandBufferSubmitInfo{.{
        .command_buffer = buffers[0],
        .device_mask = 0,
    }};
    const submit_info = [_]vk.SubmitInfo2{.{
        .command_buffer_info_count = @intCast(command_buffers.len),
        .p_command_buffer_infos = command_buffers[0..].ptr,
    }};

    try queue.submit2(submit_info[0..], .null_handle);
    try queue.waitIdle();
}

fn checkVma(result: vma.VkResult) !void {
    if (result != vma.VK_SUCCESS) {
        std.log.err("VMA call failed with VkResult {}", .{result});
        return error.VmaError;
    }
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
