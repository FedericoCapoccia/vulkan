const std = @import("std");

const vk = @import("vulkan");
const vma = @import("vma");

const Instance = @import("instance.zig").Instance;
const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;
const profile = @import("profile.zig");

pub const Device = struct {
    handle: vk.Device,
    wrapper: vk.DeviceWrapper,
    vma: vma.VmaAllocator,

    pub const CreateInfo = struct {
        base: vk.BaseWrapper,
        instance: Instance,
        physical_device: PhysicalDevice,
        requirements: *const profile.EngineRequirements,
    };

    pub fn create(info: *const CreateInfo) !Device {
        const handle = try profile.createDevice(info.physical_device, info.requirements);
        const wrapper = vk.DeviceWrapper.load(handle, info.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
        errdefer wrapper.destroyDevice(handle, null);

        const vkfn = vma.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = @ptrCast(info.base.dispatch.vkGetInstanceProcAddr),
            .vkGetDeviceProcAddr = @ptrCast(info.instance.wrapper.dispatch.vkGetDeviceProcAddr),
        };

        const alloc_cinfo = vma.VmaAllocatorCreateInfo{
            .instance = @ptrFromInt(@intFromEnum(info.instance.handle)),
            .physicalDevice = @ptrFromInt(@intFromEnum(info.physical_device.handle)),
            .device = @ptrFromInt(@intFromEnum(handle)),
            .vulkanApiVersion = info.physical_device.api_version,
            .pVulkanFunctions = &vkfn,
        };

        var allocator: vma.VmaAllocator = undefined;
        const res = vma.vmaCreateAllocator(&alloc_cinfo, &allocator);
        if (res != vma.VK_SUCCESS) {
            std.log.err("Failed to create VmaAllocator", .{});
            return error.VmaError;
        }

        return Device{
            .handle = handle,
            .wrapper = wrapper,
            .vma = allocator,
        };
    }

    pub fn destroy(self: *Device) void {
        vma.vmaDestroyAllocator(self.vma);
        self.proxy().destroyDevice(null);
    }

    pub fn proxy(self: *const Device) vk.DeviceProxy {
        return vk.DeviceProxy.init(self.handle, &self.wrapper);
    }
};
