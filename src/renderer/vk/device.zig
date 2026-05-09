const vk = @import("vulkan");

const physical_device = @import("physical_device.zig");
const DeviceRequirements = physical_device.DeviceRequirements;
const QueueFamilies = physical_device.QueueFamilies;

pub const Device = struct {
    handle: vk.Device,
    wrapper: vk.DeviceWrapper,
};

pub fn create(
    instance: *const vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    queue_families: QueueFamilies,
    requirements: *const DeviceRequirements,
) !Device {
    var features_1_4 = vk.PhysicalDeviceVulkan14Features{};
    var features_1_3 = vk.PhysicalDeviceVulkan13Features{
        .p_next = &features_1_4,
    };
    var features_1_2 = vk.PhysicalDeviceVulkan12Features{
        .p_next = &features_1_3,
    };
    var features_1_1 = vk.PhysicalDeviceVulkan11Features{
        .p_next = &features_1_2,
    };

    if (requirements.features.dynamic_rendering) {
        features_1_3.dynamic_rendering = .true;
    }

    if (requirements.features.synchronization_2) {
        features_1_3.synchronization_2 = .true;
    }

    if (requirements.features.shader_draw_parameters) {
        features_1_1.shader_draw_parameters = .true;
    }

    var features = vk.PhysicalDeviceFeatures2{
        .features = .{},
        .p_next = &features_1_1,
    };

    const qprio = [_]f32{0.5};
    const queue_cinfo = [_]vk.DeviceQueueCreateInfo{.{
        .queue_count = 1,
        .queue_family_index = queue_families.graphics,
        .p_queue_priorities = &qprio,
    }};

    const cinfo = vk.DeviceCreateInfo{
        .enabled_extension_count = @intCast(requirements.extensions.len),
        .pp_enabled_extension_names = requirements.extensions.ptr,
        .queue_create_info_count = @intCast(queue_cinfo.len),
        .p_queue_create_infos = queue_cinfo[0..].ptr,
        .p_next = &features,
    };

    const handle = try instance.createDevice(pdev, &cinfo, null);
    const wrapper = vk.DeviceWrapper.load(handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);

    return Device{
        .handle = handle,
        .wrapper = wrapper,
    };
}
