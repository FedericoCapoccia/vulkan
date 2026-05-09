pub const createInstance = @import("vk/instance.zig").create;

const physical_device = @import("vk/physical_device.zig");
pub const DeviceFeatures = physical_device.DeviceFeatures;
pub const DeviceRequirements = physical_device.DeviceRequirements;
pub const QueueFamilies = physical_device.QueueFamilies;
pub const selectPhysicalDevice = physical_device.select;

const device = @import("vk/device.zig");
pub const createDevice = device.create;
