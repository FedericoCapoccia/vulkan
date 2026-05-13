const vk = @import("vulkan");

const Instance = @import("instance.zig").Instance;
const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;
const profile = @import("profile.zig");

pub const Device = struct {
    handle: vk.Device,
    wrapper: vk.DeviceWrapper,

    pub const CreateInfo = struct {
        base: vk.BaseWrapper,
        instance: Instance,
        physical_device: PhysicalDevice,
        requirements: *const profile.EngineRequirements,
    };

    pub fn create(info: *const CreateInfo) !Device {
        const handle = try profile.createDevice(info.instance, info.physical_device, info.requirements);

        // TODO: add vma here

        return Device{
            .handle = handle,
            .wrapper = vk.DeviceWrapper.load(handle, info.instance.wrapper.dispatch.vkGetDeviceProcAddr.?),
        };
    }

    pub fn destroy(self: *Device) void {
        self.proxy().destroyDevice(null);
    }

    pub fn proxy(self: *const Device) vk.DeviceProxy {
        return vk.DeviceProxy.init(self.handle, &self.wrapper);
    }
};
