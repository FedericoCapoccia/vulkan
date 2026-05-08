const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

const PhysicalDevice = @import("vk/physical_device.zig").PhysicalDevice;
const Instance = @import("vk/instance.zig").Instance;
const Device = @import("vk/device.zig").Device;
const Swapchain = @import("vk/swapchain.zig").Swapchain;
const GraphicPipeline = @import("vk/pipeline.zig").GraphicPipeline;

pub fn main(init: std.process.Init) !void {
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.resizable, false);

    const window = try glfw.createWindow(800, 600, "Vulkan", null, null);
    defer window.destroy();

    const required_layers = [_][*:0]const u8{};
    const glfw_ext = try glfw.getRequiredInstanceExtensions();
    const extensions = [_][*:0]const u8{
        "VK_EXT_debug_utils", // TODO: enable this only on debug mode or feature flag
    };
    const required_ext = try std.mem.concat(
        init.gpa,
        [*:0]const u8,
        &.{ glfw_ext, extensions[0..] },
    );
    defer init.gpa.free(required_ext);

    const vk_instance = try Instance.create(required_layers[0..], required_ext, init.gpa);
    defer vk_instance.destroy();
    const instance = vk_instance.proxy();

    var surface: vk.SurfaceKHR = undefined;
    try glfw.createWindowSurface(vk_instance.handle, window, null, &surface);
    defer instance.destroySurfaceKHR(surface, null);

    const required_device_ext = [_][*:0]const u8{
        "VK_KHR_swapchain",
        "VK_EXT_extended_dynamic_state",
    };

    const physical_device = try PhysicalDevice.select(
        &instance,
        surface,
        required_device_ext[0..],
        init.gpa,
    );
    {
        const props = instance.getPhysicalDeviceProperties(physical_device.handle);
        const device_name = std.mem.sliceTo(&props.device_name, 0);
        const api_version: vk.Version = @bitCast(props.api_version);

        std.log.info("Selected Physical Device:", .{});
        std.log.info("\tName: {s}", .{device_name});
        std.log.info("\tType: {s}", .{@tagName(props.device_type)});
        std.log.info("\tVulkan API: {}.{}.{}", .{ api_version.major, api_version.minor, api_version.patch });
        std.log.info("\tVendor ID: 0x{x}", .{props.vendor_id});
        std.log.info("\tDevice ID: 0x{x}", .{props.device_id});
        std.log.info("\tGraphics queue family: {}", .{physical_device.graphics_queue_family_index});
        std.log.info("\tPresent queue family: {}", .{physical_device.present_queue_family_index});
    }

    const vk_device = try Device.create(&instance, physical_device, required_device_ext[0..], init.gpa);
    const device = vk_device.proxy();
    defer device.destroyDevice(null);

    const exe_dir = try std.process.executableDirPathAlloc(init.io, init.gpa);
    defer init.gpa.free(exe_dir);

    const shader_dir = try std.fs.path.join(init.gpa, &.{ exe_dir, "resources", "shaders" });
    defer init.gpa.free(shader_dir);

    const swapchain = try Swapchain.create(
        &instance,
        &physical_device,
        surface,
        &device,
        window,
        init.gpa,
    );
    defer swapchain.destroy(device);

    const triangle_shader = try createShaderModule(
        init.io,
        init.gpa,
        &device,
        shader_dir,
        "triangle.spv",
    );
    defer device.destroyShaderModule(triangle_shader, null);

    const pipeline = try GraphicPipeline.create(&device, triangle_shader, swapchain.extent, swapchain.format.format);
    defer pipeline.destroy(device);

    const present_complete_sem = try device.createSemaphore(&.{}, null);
    defer device.destroySemaphore(present_complete_sem, null);
    const render_finished_sem = try device.createSemaphore(&.{}, null);
    defer device.destroySemaphore(render_finished_sem, null);
    const fence_info = vk.FenceCreateInfo{ .flags = .{ .signaled_bit = true } };
    const draw_fence = try device.createFence(&fence_info, null);
    defer device.destroyFence(draw_fence, null);
    const draw_fences = [_]vk.Fence{draw_fence};

    const pool_cinfo = vk.CommandPoolCreateInfo{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = physical_device.graphics_queue_family_index,
    };
    const cmd_pool = try device.createCommandPool(&pool_cinfo, null);
    defer device.destroyCommandPool(cmd_pool, null);

    const alloc_cinfo = vk.CommandBufferAllocateInfo{
        .command_pool = cmd_pool,
        .level = .primary,
        .command_buffer_count = 1,
    };
    var vk_cmds: [1]vk.CommandBuffer = undefined;
    try device.allocateCommandBuffers(&alloc_cinfo, vk_cmds[0..].ptr);
    const cmd = vk.CommandBufferProxy.init(vk_cmds[0], &vk_device.wrapper);
    const present_queue = vk.QueueProxy.init(vk_device.present_queue, &vk_device.wrapper);

    while (!window.shouldClose()) {
        glfw.pollEvents();

        const fence_result = try device.waitForFences(draw_fences[0..], .true, std.math.maxInt(u64));
        if (fence_result != .success) return error.WaitForDrawFenceFailed;
        try device.resetFences(draw_fences[0..]);

        const res = try device.acquireNextImageKHR(
            swapchain.handle,
            std.math.maxInt(u64),
            present_complete_sem,
            .null_handle,
        );

        try recordCmd(cmd, swapchain, pipeline, res.image_index);

        const wait_dst_stage_mask = [_]vk.PipelineStageFlags{
            .{ .color_attachment_output_bit = true },
        };
        const wait_semaphores = [_]vk.Semaphore{present_complete_sem};
        const command_buffers = [_]vk.CommandBuffer{cmd.handle};
        const signal_semaphores = [_]vk.Semaphore{render_finished_sem};
        const submit_info = vk.SubmitInfo{
            .wait_semaphore_count = wait_semaphores.len,
            .p_wait_semaphores = wait_semaphores[0..].ptr,
            .p_wait_dst_stage_mask = wait_dst_stage_mask[0..].ptr,
            .command_buffer_count = command_buffers.len,
            .p_command_buffers = command_buffers[0..].ptr,
            .signal_semaphore_count = signal_semaphores.len,
            .p_signal_semaphores = signal_semaphores[0..].ptr,
        };
        const submits = [_]vk.SubmitInfo{submit_info};
        try device.queueSubmit(vk_device.graphics_queue, submits[0..], draw_fence);

        const present_wait_semaphores = [_]vk.Semaphore{render_finished_sem};
        const present_swapchains = [_]vk.SwapchainKHR{swapchain.handle};
        const present_image_indices = [_]u32{res.image_index};
        const present_info = vk.PresentInfoKHR{
            .wait_semaphore_count = present_wait_semaphores.len,
            .p_wait_semaphores = present_wait_semaphores[0..].ptr,
            .swapchain_count = present_swapchains.len,
            .p_swapchains = present_swapchains[0..].ptr,
            .p_image_indices = present_image_indices[0..].ptr,
        };

        const present_result = try present_queue.presentKHR(&present_info);
        if (present_result != .success) return error.PresentFailed;
    }
}

fn recordCmd(cmd: vk.CommandBufferProxy, swapchain: Swapchain, pipeline: GraphicPipeline, img_idx: u32) !void {
    const begin_info = vk.CommandBufferBeginInfo{};
    try cmd.beginCommandBuffer(&begin_info);
    transitionImageLayout(
        cmd,
        swapchain.images,
        img_idx,
        .undefined,
        .color_attachment_optimal,
        .{},
        .{ .color_attachment_write_bit = true },
        .{ .color_attachment_output_bit = true },
        .{ .color_attachment_output_bit = true },
    );

    const clear_color: vk.ClearValue = vk.ClearValue{ .color = .{ .int_32 = .{ 0, 0, 0, 1 } } };

    const attachment_info = vk.RenderingAttachmentInfo{
        .image_view = swapchain.views[img_idx],
        .image_layout = .color_attachment_optimal,
        .load_op = .clear,
        .store_op = .store,
        .clear_value = clear_color,
        .resolve_mode = .{},
        .resolve_image_layout = .undefined,
    };
    const color_attachments = [_]vk.RenderingAttachmentInfo{attachment_info};

    const rendering_info = vk.RenderingInfo{
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = swapchain.extent },
        .layer_count = 1,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = color_attachments[0..].ptr,
    };
    cmd.beginRendering(&rendering_info);
    cmd.bindPipeline(.graphics, pipeline.handle);

    const viewport = vk.Viewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(swapchain.extent.width),
        .height = @floatFromInt(swapchain.extent.height),
        .min_depth = 0.0,
        .max_depth = 1.0,
    };
    const viewports = [_]vk.Viewport{viewport};
    cmd.setViewport(0, viewports[0..]);

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain.extent,
    };
    const scissors = [_]vk.Rect2D{scissor};
    cmd.setScissor(0, scissors[0..]);

    cmd.draw(3, 1, 0, 0);

    cmd.endRendering();

    transitionImageLayout(
        cmd,
        swapchain.images,
        img_idx,
        .color_attachment_optimal,
        .present_src_khr,
        .{ .color_attachment_write_bit = true },
        .{},
        .{ .color_attachment_output_bit = true },
        .{ .bottom_of_pipe_bit = true },
    );

    try cmd.endCommandBuffer();
}

fn createShaderModule(
    io: std.Io,
    allocator: std.mem.Allocator,
    device: *const vk.DeviceProxy,
    shader_dir: []const u8,
    filename: []const u8,
) !vk.ShaderModule {
    const path = try std.fs.path.join(allocator, &.{ shader_dir, filename });
    defer allocator.free(path);

    const code = try std.Io.Dir.cwd().readFileAllocOptions(
        io,
        path,
        allocator,
        .limited(1024 * 1024),
        .of(u32),
        null,
    );
    defer allocator.free(code);

    if (code.len % @sizeOf(u32) != 0) return error.InvalidSpirVSize;

    const cinfo = vk.ShaderModuleCreateInfo{
        .code_size = code.len,
        .p_code = std.mem.bytesAsSlice(u32, code).ptr,
    };

    return device.createShaderModule(&cinfo, null);
}

fn transitionImageLayout(
    cmd: vk.CommandBufferProxy,
    images: []const vk.Image,
    image_index: u32,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    src_access_mask: vk.AccessFlags2,
    dst_access_mask: vk.AccessFlags2,
    src_stage_mask: vk.PipelineStageFlags2,
    dst_stage_mask: vk.PipelineStageFlags2,
) void {
    const barrier = vk.ImageMemoryBarrier2{
        .src_stage_mask = src_stage_mask,
        .src_access_mask = src_access_mask,
        .dst_stage_mask = dst_stage_mask,
        .dst_access_mask = dst_access_mask,
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = images[image_index],
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };

    const barriers = [_]vk.ImageMemoryBarrier2{barrier};
    const dependency_info = vk.DependencyInfo{
        .dependency_flags = .{},
        .image_memory_barrier_count = barriers.len,
        .p_image_memory_barriers = barriers[0..].ptr,
    };

    cmd.pipelineBarrier2(&dependency_info);
}
