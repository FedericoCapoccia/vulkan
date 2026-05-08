const std = @import("std");

const vk = @import("vulkan");
const glfw = @import("zglfw");

const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;

pub const Swapchain = struct {
    allocator: std.mem.Allocator,
    handle: vk.SwapchainKHR,
    format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,
    extent: vk.Extent2D,
    min_image_count: u32,
    images: []vk.Image,
    views: []vk.ImageView,

    pub fn create(
        instance: *const vk.InstanceProxy,
        pdev: *const PhysicalDevice,
        surface: vk.SurfaceKHR,
        device: *const vk.DeviceProxy,
        window: *glfw.Window,
        allocator: std.mem.Allocator,
    ) !Swapchain {
        const capabilities = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
            pdev.handle,
            surface,
        );

        const format = try selectFormat(instance, pdev, surface, allocator);
        const present = try selectPresentMode(instance, pdev, surface, allocator);

        var min_image_count = @max(@as(u32, 3), capabilities.min_image_count);
        if (capabilities.max_image_count > 0 and capabilities.max_image_count < min_image_count) {
            min_image_count = capabilities.max_image_count;
        }

        const extent = if (capabilities.current_extent.width != std.math.maxInt(u32))
            capabilities.current_extent
        else blk: {
            const framebuffer_size = window.getFramebufferSize();
            break :blk vk.Extent2D{
                .width = std.math.clamp(
                    @as(u32, @intCast(framebuffer_size[0])),
                    capabilities.min_image_extent.width,
                    capabilities.max_image_extent.width,
                ),
                .height = std.math.clamp(
                    @as(u32, @intCast(framebuffer_size[1])),
                    capabilities.min_image_extent.height,
                    capabilities.max_image_extent.height,
                ),
            };
        };

        const cinfo = vk.SwapchainCreateInfoKHR{
            .surface = surface,
            .min_image_count = min_image_count,
            .image_format = format.format,
            .image_color_space = format.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true },
            .image_sharing_mode = .exclusive,
            .pre_transform = capabilities.current_transform,
            .composite_alpha = .{
                .opaque_bit_khr = true,
            },
            .present_mode = present,
            .clipped = .true,
        };

        const handle = try device.createSwapchainKHR(&cinfo, null);
        errdefer device.destroySwapchainKHR(handle, null);

        const images = try device.getSwapchainImagesAllocKHR(handle, allocator);
        errdefer allocator.free(images);

        const image_views = try allocator.alloc(vk.ImageView, images.len);
        errdefer allocator.free(image_views);

        var created_count: usize = 0;
        errdefer {
            for (image_views[0..created_count]) |view| {
                device.destroyImageView(view, null);
            }
        }

        var view_cinfo = vk.ImageViewCreateInfo{
            .image = .null_handle,
            .view_type = .@"2d",
            .format = format.format,
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

        for (images, 0..) |image, i| {
            view_cinfo.image = image;
            image_views[i] = try device.createImageView(&view_cinfo, null);
            created_count += 1;
        }

        return Swapchain{
            .allocator = allocator,
            .handle = handle,
            .format = format,
            .present_mode = present,
            .extent = extent,
            .min_image_count = min_image_count,
            .images = images,
            .views = image_views,
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

fn selectPresentMode(
    instance: *const vk.InstanceProxy,
    pdev: *const PhysicalDevice,
    surface: vk.SurfaceKHR,
    allocator: std.mem.Allocator,
) !vk.PresentModeKHR {
    const available = try instance.getPhysicalDeviceSurfacePresentModesAllocKHR(
        pdev.handle,
        surface,
        allocator,
    );
    defer allocator.free(available);

    if (available.len == 0) return error.NoPresentModeAvailable;

    for (available) |present| {
        if (present == .mailbox_khr) {
            return present;
        }
    }

    return .fifo_khr;
}

fn selectFormat(
    instance: *const vk.InstanceProxy,
    pdev: *const PhysicalDevice,
    surface: vk.SurfaceKHR,
    allocator: std.mem.Allocator,
) !vk.SurfaceFormatKHR {
    const available = try instance.getPhysicalDeviceSurfaceFormatsAllocKHR(
        pdev.handle,
        surface,
        allocator,
    );
    defer allocator.free(available);

    if (available.len == 0) return error.NoSurfaceFormatAvailable;

    for (available) |format| {
        if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr) {
            return format;
        }
    }

    return available[0];
}
