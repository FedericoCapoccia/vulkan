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
        instance: *const vk.InstanceProxy,
        pdev: vk.PhysicalDevice,
        surface: vk.SurfaceKHR,
        device: *const vk.DeviceProxy,
        window: *glfw.Window,
        allocator: std.mem.Allocator,
    };

    pub fn create(info: *const CreateInfo) !Swapchain {
        _ = info;
        return error.NotImpl;
    }

    pub fn recreate(self: *const Swapchain, info: *const CreateInfo) void {
        _ = self;
        _ = info;
    }

    pub fn destroy(self: *const Swapchain) void {
        _ = self;
    }
};
