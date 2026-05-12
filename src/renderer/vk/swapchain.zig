const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

pub const Swapchain = struct {
    allocator: std.mem.Allocator,
    handle: vk.SwapchainKHR,
    format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,
    extent: vk.Extent2D,
    images: []vk.Image,
    views: []vk.ImageView,

    pub const CreateInfo = struct {
        instance: vk.InstanceProxy,
        pdev: vk.PhysicalDevice,
        surface: vk.SurfaceKHR,
        device: vk.DeviceProxy,
        window: *glfw.Window,
        allocator: std.mem.Allocator,
        old_swapchain: vk.SwapchainKHR = .null_handle,
    };

    pub fn create(info: *const CreateInfo) !Swapchain {
        try waitForDrawableFramebuffer(info.window);

        const capabilities = try info.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(info.pdev, info.surface);
        const format = try selectFormat(info);
        const pmode = try selectPresentMode(info);
        const min_image_count = chooseImageCount(&capabilities);
        const extent = chooseExtent(info.window, &capabilities);

        const cinfo = vk.SwapchainCreateInfoKHR{
            .surface = info.surface,
            .min_image_count = min_image_count,
            .image_format = format.format,
            .image_color_space = format.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true },
            .image_sharing_mode = .exclusive,
            .pre_transform = capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = pmode,
            .clipped = .true,
            .old_swapchain = info.old_swapchain,
        };

        const handle = try info.device.createSwapchainKHR(&cinfo, null);
        errdefer info.device.destroySwapchainKHR(handle, null);

        const images = try info.device.getSwapchainImagesAllocKHR(handle, info.allocator);
        errdefer info.allocator.free(images);

        const views = try info.allocator.alloc(vk.ImageView, images.len);
        errdefer info.allocator.free(views);

        var created_count: usize = 0;
        errdefer {
            for (views[0..created_count]) |view| {
                info.device.destroyImageView(view, null);
            }
        }

        for (images, 0..) |image, i| {
            views[i] = try createImageView(info.device, image, format.format);
            created_count += 1;
        }

        return Swapchain{
            .allocator = info.allocator,
            .handle = handle,
            .format = format,
            .present_mode = pmode,
            .extent = extent,
            .images = images,
            .views = views,
        };
    }

    pub fn destroy(self: *const Swapchain, device: vk.DeviceProxy) void {
        for (self.views) |view| {
            device.destroyImageView(view, null);
        }
        self.allocator.free(self.views);
        self.allocator.free(self.images);
        device.destroySwapchainKHR(self.handle, null);
    }
};

fn waitForDrawableFramebuffer(window: *glfw.Window) !void {
    var fb_size = window.getFramebufferSize();
    while (fb_size[0] == 0 or fb_size[1] == 0) {
        if (window.shouldClose()) return error.WindowClosed;
        glfw.waitEvents();
        fb_size = window.getFramebufferSize();
    }
}

fn selectFormat(info: *const Swapchain.CreateInfo) !vk.SurfaceFormatKHR {
    const formats = try info.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(info.pdev, info.surface, info.allocator);
    defer info.allocator.free(formats);

    if (formats.len == 0) {
        std.log.err("No surface formats available", .{});
        return error.NoSurfaceFormatAvailable;
    }

    for (formats) |format| {
        if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr) {
            return format;
        }
    }

    return formats[0];
}

fn selectPresentMode(info: *const Swapchain.CreateInfo) !vk.PresentModeKHR {
    const modes = try info.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(info.pdev, info.surface, info.allocator);
    defer info.allocator.free(modes);

    if (modes.len == 0) {
        std.log.err("No present modes available", .{});
        return error.NoPresentModeAvailable;
    }

    for (modes) |mode| {
        if (mode == .mailbox_khr) {
            return mode;
        }
    }

    return .fifo_khr;
}

fn chooseImageCount(capabilities: *const vk.SurfaceCapabilitiesKHR) u32 {
    var count: u32 = @max(3, capabilities.min_image_count);
    if (capabilities.max_image_count > 0 and capabilities.max_image_count < count) {
        count = capabilities.max_image_count;
    }
    return count;
}

fn chooseExtent(window: *glfw.Window, capabilities: *const vk.SurfaceCapabilitiesKHR) vk.Extent2D {
    if (capabilities.current_extent.width != std.math.maxInt(u32)) {
        return capabilities.current_extent;
    }

    const fb = window.getFramebufferSize();
    return vk.Extent2D{
        .width = std.math.clamp(
            @as(u32, @intCast(fb[0])),
            capabilities.min_image_extent.width,
            capabilities.max_image_extent.width,
        ),
        .height = std.math.clamp(
            @as(u32, @intCast(fb[1])),
            capabilities.min_image_extent.height,
            capabilities.max_image_extent.height,
        ),
    };
}

fn createImageView(device: vk.DeviceProxy, image: vk.Image, format: vk.Format) !vk.ImageView {
    var cinfo = vk.ImageViewCreateInfo{
        .image = image,
        .view_type = .@"2d",
        .format = format,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .components = .{
            .a = .identity,
            .r = .identity,
            .g = .identity,
            .b = .identity,
        },
    };

    return device.createImageView(&cinfo, null);
}
