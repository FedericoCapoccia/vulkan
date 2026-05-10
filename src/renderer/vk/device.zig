const vk = @import("vulkan");

const physical_device = @import("physical_device.zig");
const profile = @import("profile.zig");
const QueueFamilies = physical_device.QueueFamilies;

pub const Device = struct {
    handle: vk.Device,
    wrapper: vk.DeviceWrapper,
};

pub fn create(
    instance: *const vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    queue_families: QueueFamilies,
    extensions: []const [*:0]const u8,
) !Device {
    const handle = try profile.createDevice(
        pdev,
        queue_families.graphics,
        extensions,
    );
    const wrapper = vk.DeviceWrapper.load(handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);

    return Device{
        .handle = handle,
        .wrapper = wrapper,
    };
}
