const std = @import("std");

const vk = @import("vulkan");

pub const Device = struct {
    handle: vk.Device,
    wrapper: vk.DeviceWrapper,
    graphics_queue: vk.Queue,
    present_queue: vk.Queue,

    pub fn create(
        instance: *const vk.InstanceProxy,
        pdev: vk.PhysicalDevice,
        qfam: u32,
        required_ext: []const [*:0]const u8,
        allocator: std.mem.Allocator,
    ) !Device {
        _ = allocator;

        const queue_priority = [_]f32{1.0};
        var queue_cinfos: [1]vk.DeviceQueueCreateInfo = undefined;
        queue_cinfos[0] = .{
            .queue_count = 1,
            .queue_family_index = qfam,
            .p_queue_priorities = queue_priority[0..].ptr,
        };

        var extended_dynamic_state_features = vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT{
            .extended_dynamic_state = .true,
        };
        var vulkan_13_features = vk.PhysicalDeviceVulkan13Features{
            .p_next = &extended_dynamic_state_features,
            .dynamic_rendering = .true,
            .synchronization_2 = .true,
        };
        var vulkan_11_features = vk.PhysicalDeviceVulkan11Features{
            .p_next = &vulkan_13_features,
            .shader_draw_parameters = .true,
        };
        var features = vk.PhysicalDeviceFeatures2{
            .p_next = &vulkan_11_features,
            .features = .{},
        };

        const cinfo = vk.DeviceCreateInfo{
            .p_next = &features,
            .queue_create_info_count = 1,
            .p_queue_create_infos = queue_cinfos[0..].ptr,
            .enabled_extension_count = @intCast(required_ext.len),
            .pp_enabled_extension_names = if (required_ext.len > 0) required_ext.ptr else null,
        };

        const device_handle = try instance.createDevice(pdev, &cinfo, null);
        const device_wrapper = vk.DeviceWrapper.load(device_handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
        const device = vk.DeviceProxy.init(device_handle, &device_wrapper);

        const graphics_queue = device.getDeviceQueue(qfam, 0);
        const present_queue = device.getDeviceQueue(qfam, 0);

        return .{
            .handle = device_handle,
            .wrapper = device_wrapper,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
        };
    }

    pub fn proxy(self: *const Device) vk.DeviceProxy {
        return vk.DeviceProxy.init(self.handle, &self.wrapper);
    }
};
