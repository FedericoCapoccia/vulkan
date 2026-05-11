const vk = @import("vulkan");

const physical_device = @import("physical_device.zig");
const profile = @import("profile.zig");
const QueueFamilies = physical_device.QueueFamilies;

pub const Device = struct {
    handle: vk.Device,
    wrapper: vk.DeviceWrapper,
};

pub fn create(
    instance: vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    queue_families: QueueFamilies,
    engine_profile: profile.EngineProfile,
    requirements: *const profile.EngineRequirements,
) !Device {
    const handle = try profile.createDevice(
        pdev,
        queue_families.graphics,
        engine_profile,
        requirements,
    );
    const wrapper = vk.DeviceWrapper.load(handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);

    return Device{
        .handle = handle,
        .wrapper = wrapper,
    };
}
